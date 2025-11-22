import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:uuid/uuid.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import '../models/builtin_player_event.dart';
import 'debug_logger.dart';
import 'settings_service.dart';

enum MAConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class MusicAssistantAPI {
  final String serverUrl;
  WebSocketChannel? _channel;
  final _uuid = const Uuid();
  final _logger = DebugLogger();

  final _connectionStateController = StreamController<MAConnectionState>.broadcast();
  Stream<MAConnectionState> get connectionState => _connectionStateController.stream;

  MAConnectionState _currentState = MAConnectionState.disconnected;
  MAConnectionState get currentConnectionState => _currentState;

  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  final Map<String, StreamController<Map<String, dynamic>>> _eventStreams = {};

  Completer<void>? _connectionCompleter;

  // Cached custom port setting
  int? _cachedCustomPort;

  // Built-in player
  String? _builtinPlayerId;
  final _builtinPlayerEventController = StreamController<BuiltinPlayerEvent>.broadcast();
  Stream<BuiltinPlayerEvent> get builtinPlayerEvents => _builtinPlayerEventController.stream;

  MusicAssistantAPI(this.serverUrl);

  Future<void> connect() async {
    if (_currentState == MAConnectionState.connected ||
        _currentState == MAConnectionState.connecting) {
      return;
    }

    try {
      _updateConnectionState(MAConnectionState.connecting);

      // Load and cache custom port setting
      _cachedCustomPort = await SettingsService.getWebSocketPort();

      // Parse server URL and construct WebSocket URL
      var wsUrl = serverUrl;
      var useSecure = true; // Default to secure connection

      _logger.log('Original server URL: $serverUrl');

      if (!wsUrl.startsWith('ws://') && !wsUrl.startsWith('wss://')) {
        // Determine protocol
        if (wsUrl.startsWith('https://')) {
          wsUrl = wsUrl.replaceFirst('https://', 'wss://');
          useSecure = true;
        } else if (wsUrl.startsWith('http://')) {
          wsUrl = wsUrl.replaceFirst('http://', 'ws://');
          useSecure = false;
        } else {
          // Default to secure WebSocket for plain domains
          wsUrl = 'wss://$wsUrl';
          useSecure = true;
        }
      } else {
        useSecure = wsUrl.startsWith('wss://');
      }

      // Construct WebSocket URL with proper port handling
      final uri = Uri.parse(wsUrl);

      Uri finalUri;
      if (_cachedCustomPort != null) {
        // Use custom port from settings
        finalUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: _cachedCustomPort,
          path: '/ws',
        );
        _logger.log('Using custom WebSocket port from settings: $_cachedCustomPort');
      } else if (uri.hasPort) {
        // Port is already specified in URL, keep it
        finalUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.port,
          path: '/ws',
        );
        _logger.log('Using port from URL: ${uri.port}');
      } else {
        // No port specified
        if (!useSecure) {
          // For WS (unsecure WebSocket), add Music Assistant default port 8095
          finalUri = Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: 8095,
            path: '/ws',
          );
          _logger.log('Using port 8095 for unsecure connection');
        } else {
          // For WSS (secure WebSocket), DON'T specify port - use implicit default
          // This is critical for Cloudflare WebSocket support
          finalUri = Uri(
            scheme: uri.scheme,
            host: uri.host,
            // NO PORT - let it use default 443 implicitly
            path: '/ws',
          );
          _logger.log('Using implicit default port (443) for secure connection');
        }
      }

      wsUrl = finalUri.toString();

      _logger.log('Attempting ${useSecure ? "secure (WSS)" : "unsecure (WS)"} connection');
      _logger.log('Final WebSocket URL: $wsUrl');

      // Get authentication token for WebSocket connection
      final authToken = await SettingsService.getAuthToken();
      final headers = <String, dynamic>{};

      if (authToken != null && authToken.isNotEmpty && authToken != 'authenticated') {
        // Add session cookie to WebSocket handshake
        headers['Cookie'] = 'authelia_session=$authToken';
        _logger.log('🔑 Adding session cookie to WebSocket handshake');
      } else if (authToken == 'authenticated') {
        _logger.log('✓ Authenticated (no cookie needed for WebSocket)');
      } else {
        _logger.log('ℹ️ No authentication configured for WebSocket');
      }

      // Use WebSocket.connect with headers, then wrap in IOWebSocketChannel
      final webSocket = await WebSocket.connect(
        wsUrl,
        headers: headers.isNotEmpty ? headers : null,
      );
      _channel = IOWebSocketChannel(webSocket);

      // Wait for server info message before considering connected
      _connectionCompleter = Completer<void>();

      // Listen to messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          _logger.log('WebSocket error: $error');
          _updateConnectionState(MAConnectionState.error);
          _reconnect();
        },
        onDone: () {
          _logger.log('WebSocket connection closed');
          _updateConnectionState(MAConnectionState.disconnected);
          _connectionCompleter?.completeError(Exception('Connection closed'));
          _reconnect();
        },
      );

      // Wait for server info message with timeout
      await _connectionCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout - no server info received');
        },
      );

      _logger.log('Connected to Music Assistant successfully');
    } catch (e) {
      _logger.log('Connection error: $e');
      _updateConnectionState(MAConnectionState.error);
      rethrow;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      _logger.log('Received message: ${data.keys}');

      // Check for server info message (first message on connect)
      if (data.containsKey('server_version')) {
        _logger.log('Received server info: ${data['server_version']}');
        _updateConnectionState(MAConnectionState.connected);
        _connectionCompleter?.complete();

        // Register as built-in player after connection established
        registerBuiltinPlayer().catchError((e) {
          _logger.log('Failed to register built-in player: $e');
        });

        return;
      }

      final messageId = data['message_id'] as String?;

      // Handle response to a request
      if (messageId != null && _pendingRequests.containsKey(messageId)) {
        final completer = _pendingRequests.remove(messageId);

        if (data.containsKey('error_code')) {
          _logger.log('Command error: ${data['error_code']} - ${data['details']}');
          completer!.completeError(
            Exception('${data['error_code']}: ${data['details']}'),
          );
        } else {
          completer!.complete(data);
        }
        return;
      }

      // Handle event
      final eventType = data['event'] as String?;
      if (eventType != null) {
        _logger.log('Event received: $eventType');

        // Handle builtin_player events specially
        if (eventType == 'builtin_player') {
          final objectId = data['object_id'] as String?;
          if (objectId == _builtinPlayerId) {
            try {
              final eventData = data['data'] as Map<String, dynamic>;
              final playerEvent = BuiltinPlayerEvent.fromJson(eventData);
              _logger.log('Builtin player event: ${playerEvent.type.value}');
              _builtinPlayerEventController.add(playerEvent);
            } catch (e) {
              _logger.log('Error parsing builtin player event: $e');
            }
          }
        }

        _eventStreams[eventType]?.add(data['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      _logger.log('Error handling message: $e');
    }
  }

  Future<Map<String, dynamic>> _sendCommand(
    String command, {
    Map<String, dynamic>? args,
  }) async {
    if (_currentState != MAConnectionState.connected) {
      throw Exception('Not connected to Music Assistant server');
    }

    final messageId = _uuid.v4();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[messageId] = completer;

    final message = {
      'message_id': messageId,
      'command': command,
      if (args != null) 'args': args,
    };

    _channel!.sink.add(jsonEncode(message));

    // Timeout after 30 seconds
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(messageId);
        throw TimeoutException('Command timeout: $command');
      },
    );
  }

  // Library browsing methods
  Future<List<Artist>> getArtists({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
  }) async {
    try {
      _logger.log('Fetching artists with limit=$limit, offset=$offset, search=$search');
      final response = await _sendCommand(
        'music/artists/library_items',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite': favoriteOnly,
        },
      );

      _logger.log('Artists response: ${response.keys}');
      final items = response['result'] as List<dynamic>?;
      if (items == null) {
        _logger.log('No result field in response');
        return [];
      }

      _logger.log('Got ${items.length} artists');
      return items
          .map((item) => Artist.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting artists: $e');
      return [];
    }
  }

  Future<List<Album>> getAlbums({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
    String? artistId,
  }) async {
    try {
      _logger.log('Fetching albums with limit=$limit, offset=$offset');
      final response = await _sendCommand(
        'music/albums/library_items',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite': favoriteOnly,
          if (artistId != null) 'artist': artistId,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((item) => Album.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting albums: $e');
      return [];
    }
  }

  Future<List<Track>> getTracks({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
    String? artistId,
    String? albumId,
  }) async {
    try {
      _logger.log('Fetching tracks with limit=$limit, offset=$offset');
      final response = await _sendCommand(
        'music/tracks/library_items',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite': favoriteOnly,
          if (artistId != null) 'artist': artistId,
          if (albumId != null) 'album': albumId,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      _logger.log('Got ${items.length} tracks');

      // Debug: Log the first track's raw data to see what fields are available
      if (items.isNotEmpty) {
        _logger.log('🔍 DEBUG: First track raw data: ${items[0]}');
      }

      return items
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting tracks: $e');
      return [];
    }
  }

  Future<Album?> getAlbumDetails(String provider, String itemId) async {
    try {
      final response = await _sendCommand(
        'music/album',
        args: {
          'provider': provider,
          'item_id': itemId,
        },
      );

      final result = response['result'];
      if (result == null) return null;

      return Album.fromJson(result as Map<String, dynamic>);
    } catch (e) {
      _logger.log('Error getting album details: $e');
      return null;
    }
  }

  Future<List<Track>> getAlbumTracks(String provider, String itemId) async {
    try {
      _logger.log('Fetching album tracks for provider=$provider, itemId=$itemId');
      final response = await _sendCommand(
        'music/albums/album_tracks',
        args: {
          'provider_instance_id_or_domain': provider,
          'item_id': itemId,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) {
        _logger.log('No result for album tracks');
        return [];
      }

      _logger.log('Got ${items.length} album tracks');

      // Debug: Log the first track's raw data to see what fields are available
      if (items.isNotEmpty) {
        _logger.log('🔍 DEBUG: First album track raw data: ${items[0]}');
      }

      return items
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting album tracks: $e');
      return [];
    }
  }

  // Search
  Future<Map<String, List<MediaItem>>> search(String query) async {
    try {
      final response = await _sendCommand(
        'music/search',
        args: {'search': query},
      );

      final result = response['result'] as Map<String, dynamic>?;
      if (result == null) {
        return {'artists': [], 'albums': [], 'tracks': []};
      }

      return {
        'artists': (result['artists'] as List<dynamic>?)
                ?.map((item) => Artist.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
        'albums': (result['albums'] as List<dynamic>?)
                ?.map((item) => Album.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
        'tracks': (result['tracks'] as List<dynamic>?)
                ?.map((item) => Track.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
      };
    } catch (e) {
      _logger.log('Error searching: $e');
      return {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  // ============================================================================
  // PLAYER AND QUEUE MANAGEMENT (Queue-based streaming for full track playback)
  // ============================================================================

  /// Get all available players
  Future<List<Player>> getPlayers() async {
    try {
      _logger.log('Fetching available players...');
      final response = await _sendCommand('players/all');

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      final players = items
          .map((item) => Player.fromJson(item as Map<String, dynamic>))
          .toList();

      _logger.log('Got ${players.length} players');
      return players;
    } catch (e) {
      _logger.log('Error getting players: $e');
      return [];
    }
  }

  /// Get player queue
  Future<PlayerQueue?> getQueue(String playerId) async {
    try {
      _logger.log('Fetching queue for player: $playerId');
      final response = await _sendCommand(
        'player_queues/items',
        args: {'queue_id': playerId},
      );

      final result = response['result'];
      if (result == null) return null;

      return PlayerQueue.fromJson(result as Map<String, dynamic>);
    } catch (e) {
      _logger.log('Error getting queue: $e');
      return null;
    }
  }

  /// Play a single track via queue
  Future<void> playTrack(String playerId, Track track) async {
    try {
      // Build URI from provider mappings
      final uri = _buildTrackUri(track);
      _logger.log('Playing track via queue: $uri on player $playerId');

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri], // Array of URI strings, not objects
          'option': 'play', // Play immediately
        },
      );

      _logger.log('✓ Track queued successfully');
    } catch (e) {
      _logger.log('Error playing track: $e');
      rethrow;
    }
  }

  /// Play multiple tracks via queue
  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex}) async {
    try {
      // Build array of URI strings (not objects!)
      final mediaUris = tracks.map((track) => _buildTrackUri(track)).toList();

      _logger.log('Playing ${tracks.length} tracks via queue on player $playerId');

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': mediaUris, // Array of URI strings
          'option': 'play', // Play immediately
          if (startIndex != null) 'start_item': startIndex,
        },
      );

      _logger.log('✓ ${tracks.length} tracks queued successfully');
    } catch (e) {
      _logger.log('Error playing tracks: $e');
      rethrow;
    }
  }

  /// Build track URI from provider mappings
  String _buildTrackUri(Track track) {
    // Use provider mappings to get the actual provider instance
    if (track.providerMappings != null && track.providerMappings!.isNotEmpty) {
      final mapping = track.providerMappings!.firstWhere(
        (m) => m.available,
        orElse: () => track.providerMappings!.first,
      );

      return '${mapping.providerInstance}://track/${mapping.itemId}';
    }

    // Fallback to top-level provider/itemId
    return '${track.provider}://track/${track.itemId}';
  }

  /// Get current stream URL from queue
  Future<String?> getCurrentStreamUrl(String playerId) async {
    try {
      final queue = await getQueue(playerId);
      if (queue == null || queue.items.isEmpty) {
        _logger.log('⚠️ Queue is empty');
        return null;
      }

      // Get the current item (or first item if no current index)
      final currentItem = queue.currentItem ?? queue.items.first;

      if (currentItem.streamdetails == null) {
        _logger.log('⚠️ No stream details available yet');
        return null;
      }

      final streamId = currentItem.streamdetails!.streamId;
      final contentType = currentItem.streamdetails!.contentType;
      final extension = _getExtension(contentType);

      // Music Assistant uses port 8097 for streaming (not 8095!)
      var baseUrl = serverUrl;
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      final uri = Uri.parse(baseUrl);
      final streamUrl = '${uri.scheme}://${uri.host}:8097/flow/$playerId/$streamId.$extension';

      _logger.log('🎵 Stream URL from queue: $streamUrl');
      return streamUrl;
    } catch (e) {
      _logger.log('Error getting stream URL: $e');
      return null;
    }
  }

  String _getExtension(String contentType) {
    if (contentType.contains('flac')) return 'flac';
    if (contentType.contains('mp3')) return 'mp3';
    if (contentType.contains('aac')) return 'aac';
    if (contentType.contains('ogg')) return 'ogg';
    return 'audio';
  }

  // Player control commands
  Future<void> pausePlayer(String playerId) async {
    await _sendPlayerCommand(playerId, 'pause');
  }

  Future<void> resumePlayer(String playerId) async {
    await _sendPlayerCommand(playerId, 'play');
  }

  Future<void> nextTrack(String playerId) async {
    await _sendPlayerCommand(playerId, 'next');
  }

  Future<void> previousTrack(String playerId) async {
    await _sendPlayerCommand(playerId, 'previous');
  }

  Future<void> stopPlayer(String playerId) async {
    await _sendPlayerCommand(playerId, 'stop');
  }

  Future<void> _sendPlayerCommand(String playerId, String command) async {
    try {
      _logger.log('Sending player command: $command to $playerId');
      await _sendCommand(
        'player_command/$command',
        args: {'player_id': playerId},
      );
    } catch (e) {
      _logger.log('Error sending player command: $e');
      rethrow;
    }
  }

  // ============================================================================
  // END PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  // Get stream URL for a track
  String getStreamUrl(String provider, String itemId, {String? uri, List<ProviderMapping>? providerMappings}) {
    // Debug logging
    _logger.log('📍 getStreamUrl called: provider=$provider, itemId=$itemId, uri=$uri, mappings count=${providerMappings?.length ?? 0}');

    var baseUrl = serverUrl;
    var useSecure = true;

    // Determine protocol
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'https://$baseUrl';
      useSecure = true;
    } else if (baseUrl.startsWith('http://')) {
      useSecure = false;
    }

    // Add port if not specified
    final uriObj = Uri.parse(baseUrl);

    if (_cachedCustomPort != null) {
      // Use cached custom port from settings
      baseUrl = '${uriObj.scheme}://${uriObj.host}:$_cachedCustomPort';
    } else if (!uriObj.hasPort) {
      if (useSecure) {
        // For HTTPS, don't add port 443 (it's the default)
        baseUrl = '${uriObj.scheme}://${uriObj.host}';
      } else {
        // For HTTP, default to Music Assistant port 8095
        baseUrl = '${uriObj.scheme}://${uriObj.host}:8095';
      }
    } else {
      baseUrl = '${uriObj.scheme}://${uriObj.host}:${uriObj.port}';
    }

    String actualProvider = provider;
    String actualItemId = itemId;

    // PRIORITY 1: Use provider_mappings to get the ACTUAL provider instance
    // The top-level "provider: library" is just a virtual view, not a real provider
    if (providerMappings != null && providerMappings.isNotEmpty) {
      _logger.log('🔍 Using provider_mappings to get real provider instance');

      // Try to find the first available mapping
      final mapping = providerMappings.firstWhere(
        (m) => m.available,
        orElse: () => providerMappings.first,
      );

      actualProvider = mapping.providerInstance; // e.g., "opensubsonic--ETwFWrKe"
      actualItemId = mapping.itemId; // e.g., "HNF3R3sfsGVgelPM5hiolL"

      _logger.log('✓ Using provider mapping: provider=${mapping.providerInstance}, itemId=${mapping.itemId}, domain=${mapping.providerDomain}');
    }
    // PRIORITY 2: Try to parse the URI if no provider mappings
    else if (uri != null && uri.isNotEmpty && !uri.startsWith('library://')) {
      _logger.log('🔍 Parsing URI: $uri');
      try {
        // Split by "://" to get provider and path
        final parts = uri.split('://');
        if (parts.length == 2) {
          actualProvider = parts[0]; // e.g., "builtin" or "opensubsonic--ETwFWrKe"

          // Get item_id from path: "track/413" -> "413"
          final pathParts = parts[1].split('/');
          if (pathParts.isNotEmpty) {
            actualItemId = pathParts.last;
          }
          _logger.log('✓ Parsed URI: provider=$actualProvider, itemId=$actualItemId');
        }
      } catch (e) {
        _logger.log('⚠️ Failed to parse track URI: $uri, using provider=$provider, itemId=$itemId');
      }
    } else {
      _logger.log('⚠️ No provider mappings or URI, using provider=$provider (may not be valid provider instance ID)');
    }

    // Music Assistant stream endpoint - use /preview endpoint
    // Format: /preview?item_id={itemId}&provider={provider}
    final streamUrl = '$baseUrl/preview?item_id=$actualItemId&provider=$actualProvider';
    _logger.log('🎵 Final stream URL: $streamUrl');
    return streamUrl;
  }

  // Get image URL
  String? getImageUrl(MediaItem item, {int size = 256}) {
    final imageUrl = item.metadata?['image'];
    if (imageUrl == null) return null;

    var baseUrl = serverUrl;
    var useSecure = true;

    // Determine protocol
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'https://$baseUrl';
      useSecure = true;
    } else if (baseUrl.startsWith('http://')) {
      useSecure = false;
    }

    // Add port if not specified
    final uri = Uri.parse(baseUrl);

    if (_cachedCustomPort != null) {
      // Use cached custom port from settings
      baseUrl = '${uri.scheme}://${uri.host}:$_cachedCustomPort';
    } else if (!uri.hasPort) {
      if (useSecure) {
        // For HTTPS, don't add port 443 (it's the default)
        baseUrl = '${uri.scheme}://${uri.host}';
      } else {
        // For HTTP, default to Music Assistant port 8095
        baseUrl = '${uri.scheme}://${uri.host}:8095';
      }
    } else {
      baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';
    }

    return '$baseUrl/api/image/$size/${Uri.encodeComponent(imageUrl)}';
  }

  // ============================================================================
  // BUILT-IN PLAYER (Local playback on device)
  // ============================================================================

  /// Register this app as a built-in player with Music Assistant
  Future<void> registerBuiltinPlayer() async {
    try {
      // Generate or get cached player ID
      _builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (_builtinPlayerId == null) {
        _builtinPlayerId = _uuid.v4();
        await SettingsService.setBuiltinPlayerId(_builtinPlayerId!);
      }

      _logger.log('Registering built-in player: $_builtinPlayerId');

      await _sendCommand(
        'builtin_player/register',
        args: {
          'player_name': 'Music Assistant Mobile',
          'player_id': _builtinPlayerId,
        },
      );

      _logger.log('✓ Built-in player registered');
    } catch (e) {
      _logger.log('Error registering built-in player: $e');
      rethrow;
    }
  }

  /// Update the built-in player state (position, playing, etc.)
  Future<void> updateBuiltinPlayerState(BuiltinPlayerState state) async {
    if (_builtinPlayerId == null) return;

    try {
      await _sendCommand(
        'builtin_player/update_state',
        args: {
          'player_id': _builtinPlayerId,
          'state': state.toJson(),
        },
      );
    } catch (e) {
      _logger.log('Error updating built-in player state: $e');
    }
  }

  /// Get the built-in player ID
  String? get builtinPlayerId => _builtinPlayerId;

  // ============================================================================
  // END BUILT-IN PLAYER
  // ============================================================================

  void _updateConnectionState(MAConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);
  }

  Future<void> _reconnect() async {
    await Future.delayed(const Duration(seconds: 3));
    if (_currentState != MAConnectionState.connected) {
      try {
        await connect();
      } catch (e) {
        _logger.log('Reconnection failed: $e');
      }
    }
  }

  Future<void> disconnect() async {
    _updateConnectionState(MAConnectionState.disconnected);
    await _channel?.sink.close();
    _channel = null;
    _pendingRequests.clear();
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
    for (final stream in _eventStreams.values) {
      stream.close();
    }
    _eventStreams.clear();
  }
}
