import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:uuid/uuid.dart';
import '../constants/network.dart';
import '../constants/timings.dart' show Timings, LibraryConstants;
import '../models/media_item.dart';
import '../models/player.dart';
import '../models/provider_instance.dart';
import '../models/provider_manifest.dart';
import 'debug_logger.dart';
import 'settings_service.dart';
import 'device_id_service.dart';
import 'retry_helper.dart';
import 'auth/auth_manager.dart';

enum MAConnectionState {
  disconnected,
  connecting,
  connected,
  authenticating,
  authenticated,
  error,
}

/// Wrapper for pending requests with timestamp for age-based cleanup
class _PendingRequest {
  final Completer<Map<String, dynamic>> completer;
  final DateTime createdAt;

  _PendingRequest({required this.completer, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  bool get isStale {
    const staleThreshold = Duration(minutes: 2);
    return DateTime.now().difference(createdAt) > staleThreshold;
  }
}

class MusicAssistantAPI {
  final String serverUrl;
  final AuthManager authManager;
  WebSocketChannel? _channel;
  final _uuid = const Uuid();
  final _logger = DebugLogger();

  final _connectionStateController = StreamController<MAConnectionState>.broadcast();
  Stream<MAConnectionState> get connectionState => _connectionStateController.stream;

  MAConnectionState _currentState = MAConnectionState.disconnected;
  MAConnectionState get currentConnectionState => _currentState;

  final Map<String, _PendingRequest> _pendingRequests = {};
  final Map<String, StreamController<Map<String, dynamic>>> _eventStreams = {};

  Completer<void>? _connectionCompleter;

  // Heartbeat timer to keep WebSocket connection alive
  Timer? _heartbeatTimer;

  // Cached custom port setting
  int? _cachedCustomPort;

  // Server info from initial connection
  Map<String, dynamic>? _serverInfo;
  bool _authRequired = false;
  int? _schemaVersion;

  // Auth state
  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;
  bool get authRequired => _authRequired;
  int? get schemaVersion => _schemaVersion;
  Map<String, dynamic>? get serverInfo => _serverInfo;

  // Provider manifests (contains icons)
  final Map<String, ProviderManifest> _providerManifests = {};
  Map<String, ProviderManifest> get providerManifests => _providerManifests;

  // Remote mode flag - when true, images go through WebRTC bridge which doesn't support HTTP
  // In this mode, we use external CDN URLs directly instead of imageproxy
  bool _isRemoteMode = false;
  bool get isRemoteMode => _isRemoteMode;
  set isRemoteMode(bool value) => _isRemoteMode = value;

  MusicAssistantAPI(this.serverUrl, this.authManager);

  // Guard to prevent multiple simultaneous connection attempts
  Completer<void>? _connectionInProgress;
  bool _isDisposed = false;

  Future<void> connect() async {
    // If disposed, don't try to connect
    if (_isDisposed) {
      _logger.log('Connection: API disposed, skipping connect');
      return;
    }

    // If already connected or authenticated, nothing to do
    if (_currentState == MAConnectionState.connected ||
        _currentState == MAConnectionState.authenticated) {
      _logger.log('Connection: Already connected, skipping');
      return;
    }

    // Atomic check-and-set: create new completer first, then check if one exists
    // This ensures no async operations happen between check and set
    final newCompleter = Completer<void>();
    if (_connectionInProgress != null && !_connectionInProgress!.isCompleted) {
      _logger.log('Connection already in progress, waiting...');
      return _connectionInProgress!.future;
    }
    // Set immediately before any async operations to close the race window
    _connectionInProgress = newCompleter;

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

      // Get client ID for WebSocket connection
      // Use a unique session ID for the WebSocket connection itself
      // The player ID is separate and managed during registration
      final clientId = 'session_${_uuid.v4()}';
      _logger.log('Using WebSocket session ID: $clientId');

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
          queryParameters: {'client_id': clientId},
        );
        _logger.log('Using custom WebSocket port from settings: $_cachedCustomPort');
      } else if (uri.hasPort) {
        // Port is already specified in URL, keep it
        finalUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.port,
          path: '/ws',
          queryParameters: {'client_id': clientId},
        );
        _logger.log('Using port from URL: ${uri.port}');
      } else {
        // No port specified
        if (!useSecure) {
          // For WS (unsecure WebSocket), add Music Assistant default port
          finalUri = Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: NetworkConstants.defaultWsPort,
            path: '/ws',
            queryParameters: {'client_id': clientId},
          );
          _logger.log('Using port ${NetworkConstants.defaultWsPort} for unsecure connection');
        } else {
          // For WSS (secure WebSocket), DON'T specify port - use implicit default
          // This is critical for Cloudflare WebSocket support
          finalUri = Uri(
            scheme: uri.scheme,
            host: uri.host,
            // NO PORT - let it use default 443 implicitly
            path: '/ws',
            queryParameters: {'client_id': clientId},
          );
          _logger.log('Using implicit default port (443) for secure connection');
        }
      }

      wsUrl = finalUri.toString();

      _logger.log('Attempting ${useSecure ? "secure (WSS)" : "unsecure (WS)"} connection');
      _logger.log('Final WebSocket URL: $wsUrl');

      // Get authentication headers from AuthManager
      final headers = authManager.getWebSocketHeaders();

      if (headers.isNotEmpty) {
        _logger.log('Connection: Using authentication');
      } else {
        _logger.log('Connection: No authentication configured');
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
          if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
            _connectionCompleter!.completeError(Exception('Connection closed'));
          }
          _reconnect();
        },
      );

      // Wait for server info message with timeout
      await _connectionCompleter!.future.timeout(
        Timings.connectionTimeout,
        onTimeout: () {
          throw Exception('Connection timeout - no server info received');
        },
      );

      _logger.log('Connection: Connected to server');
      if (_connectionInProgress != null && !_connectionInProgress!.isCompleted) {
        _connectionInProgress!.complete();
      }
      _connectionInProgress = null;
    } catch (e) {
      _logger.log('Connection: Failed - $e');
      _updateConnectionState(MAConnectionState.error);
      if (_connectionInProgress != null && !_connectionInProgress!.isCompleted) {
        _connectionInProgress!.completeError(e);
      }
      _connectionInProgress = null;
      rethrow;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      _logger.log('Received message: ${data.keys}');

      // Check for server info message (first message on connect)
      if (data.containsKey('server_version')) {
        _serverInfo = data;
        _schemaVersion = data['schema_version'] as int?;
        final serverVersion = data['server_version'] as String?;

        _logger.log('Received server info: $serverVersion (schema: $_schemaVersion)');

        // Check if authentication is required (schema 28+)
        // The server sends 'needs_auth' or 'auth_enabled' field
        final needsAuth = data['needs_auth'] as bool? ?? false;
        final authEnabled = data['auth_enabled'] as bool? ?? false;
        _authRequired = needsAuth || authEnabled || (_schemaVersion != null && _schemaVersion! >= 28);

        if (_authRequired) {
          _logger.log('Server: Requires authentication');
        } else {
          _logger.log('Server: No authentication required');
          _isAuthenticated = true; // No auth needed = effectively authenticated
        }

        _updateConnectionState(MAConnectionState.connected);
        if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
          _connectionCompleter!.complete();
        }
        _startHeartbeat();

        return;
      }

      final messageId = data['message_id'] as String?;

      // Handle response to a request
      if (messageId != null && _pendingRequests.containsKey(messageId)) {
        final pending = _pendingRequests.remove(messageId);

        if (data.containsKey('error_code')) {
          _logger.log('Command error: ${data['error_code']} - ${data['details']}');
          pending!.completer.completeError(
            Exception('${data['error_code']}: ${data['details']}'),
          );
        } else {
          pending!.completer.complete(data);
        }
        return;
      }

      // Handle event
      final eventType = data['event'] as String?;
      if (eventType != null) {
        // Get the object_id (player_id for player events)
        final objectId = data['object_id'] as String?;
        final eventData = data['data'] as Map<String, dynamic>? ?? {};


        // Include object_id in event data so listeners can filter by player
        final enrichedData = {
          ...eventData,
          'player_id': objectId,
        };

        _eventStreams[eventType]?.add(enrichedData);
      }
    } catch (e) {
      _logger.log('Error handling message: $e');
    }
  }

  Future<Map<String, dynamic>> _sendCommand(
    String command, {
    Map<String, dynamic>? args,
  }) async {
    // Allow auth commands when connected or authenticating
    // For all other commands, require authenticated state if auth is required
    final isAuthCommand = command == 'auth' || command == 'auth/login';

    if (isAuthCommand) {
      // Auth commands can be sent when connected or authenticating
      final allowedStates = [
        MAConnectionState.connected,
        MAConnectionState.authenticating,
      ];
      if (!allowedStates.contains(_currentState)) {
        throw Exception('Not connected to Music Assistant server');
      }
    } else {
      // Non-auth commands require proper authentication state
      if (_authRequired && !_isAuthenticated) {
        throw Exception('Not authenticated to Music Assistant server');
      }

      final allowedStates = [
        MAConnectionState.connected,
        MAConnectionState.authenticating,
        MAConnectionState.authenticated,
      ];
      if (!allowedStates.contains(_currentState)) {
        throw Exception('Not connected to Music Assistant server');
      }
    }

    // Clean up stale requests before checking limits
    _cleanupStaleRequests();

    // Prevent memory leaks by limiting pending requests
    if (_pendingRequests.length >= NetworkConstants.maxPendingRequests) {
      throw Exception(
        'Too many pending requests (${_pendingRequests.length}). '
        'Please wait for existing requests to complete.',
      );
    }

    final messageId = _uuid.v4();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[messageId] = _PendingRequest(completer: completer);

    final message = {
      'message_id': messageId,
      'command': command,
      if (args != null) 'args': args,
    };

    _channel!.sink.add(jsonEncode(message));

    // Timeout after configured duration, ensure cleanup in all cases
    try {
      return await completer.future.timeout(
        Timings.commandTimeout,
        onTimeout: () {
          throw TimeoutException('Command timeout: $command');
        },
      );
    } finally {
      _pendingRequests.remove(messageId);
    }
  }

  /// Clean up stale pending requests that have been waiting too long
  void _cleanupStaleRequests() {
    final staleIds = <String>[];
    for (final entry in _pendingRequests.entries) {
      if (entry.value.isStale && !entry.value.completer.isCompleted) {
        staleIds.add(entry.key);
      }
    }
    if (staleIds.isNotEmpty) {
      _logger.log('Cleanup: Removing ${staleIds.length} stale pending requests');
      for (final id in staleIds) {
        final pending = _pendingRequests.remove(id);
        if (pending != null && !pending.completer.isCompleted) {
          pending.completer.completeError(
            TimeoutException('Request expired after 2 minutes'),
          );
        }
      }
    }
  }

  // Library browsing methods
  Future<List<Artist>> getArtists({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
    bool albumArtistsOnly = true,
    String? orderBy,
    List<String>? providerInstanceIds,
  }) async {
    try {
      final args = {
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (search != null) 'search': search,
        if (favoriteOnly != null) 'favorite': favoriteOnly,
        'album_artists_only': albumArtistsOnly,
        if (orderBy != null) 'order_by': orderBy,
        if (providerInstanceIds != null && providerInstanceIds.isNotEmpty)
          'provider': providerInstanceIds,
      };
      _logger.log('🔍 API getArtists args: $args');
      final response = await _sendCommand(
        'music/artists/library_items',
        args: args,
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) {
        return [];
      }
      _logger.log('🔍 API getArtists returned ${items.length} items');
      return items
          .map((item) => Artist.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting artists: $e');
      return [];
    }
  }

  Future<List<Artist>> getRandomArtists({
    int limit = 10,
    bool albumArtistsOnly = true,
    List<String>? providerInstanceIds,
  }) async {
    try {
      final response = await _sendCommand(
        'music/artists/library_items',
        args: {
          'limit': limit,
          'order_by': 'random',
          'album_artists_only': albumArtistsOnly,
          if (providerInstanceIds != null && providerInstanceIds.isNotEmpty)
            'provider': providerInstanceIds,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((item) => Artist.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting random artists: $e');
      return [];
    }
  }

  Future<List<Album>> getAlbums({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
    String? artistId,
    String? orderBy,
    List<String>? providerInstanceIds,
  }) async {
    try {
      final args = <String, dynamic>{
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (search != null) 'search': search,
        if (favoriteOnly != null) 'favorite': favoriteOnly,
        if (artistId != null) 'artist_id': artistId,
        if (orderBy != null) 'order_by': orderBy,
        if (providerInstanceIds != null && providerInstanceIds.isNotEmpty)
          'provider': providerInstanceIds,
      };
      _logger.log('🔍 API getAlbums args: $args');

      final response = await _sendCommand(
        'music/albums/library_items',
        args: args,
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];
      _logger.log('🔍 API getAlbums returned ${items.length} items');

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
    String? orderBy,
    List<String>? providerInstanceIds,
  }) async {
    try {
      final response = await _sendCommand(
        'music/tracks/library_items',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite': favoriteOnly,
          if (artistId != null) 'artist': artistId,
          if (albumId != null) 'album': albumId,
          if (orderBy != null) 'order_by': orderBy,
          if (providerInstanceIds != null && providerInstanceIds.isNotEmpty)
            'provider': providerInstanceIds,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];


      return items
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting tracks: $e');
      return [];
    }
  }

  Future<List<MediaItem>> getRadioStations({
    int? limit,
    int? offset,
    bool? favoriteOnly,
    String? orderBy,
  }) async {
    try {
      final response = await _sendCommand(
        'music/radios/library_items',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (favoriteOnly != null) 'favorite': favoriteOnly,
          if (orderBy != null) 'order_by': orderBy,
        },
      );

      final items = response['items'] as List<dynamic>? ?? response['result'] as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting radio stations: $e');
      return [];
    }
  }

  /// Search for radio stations globally (across all providers like TuneIn)
  Future<List<MediaItem>> searchRadioStations(String query, {int limit = 25}) async {
    try {
      final response = await _sendCommand(
        'music/search',
        args: {
          'search_query': query,
          'media_types': ['radio'],
          'limit': limit,
        },
      );

      final result = response['result'] as Map<String, dynamic>?;
      if (result == null) return [];

      // Radio results might be under 'radios' or 'radio' key
      final radios = (result['radios'] as List<dynamic>?) ??
                     (result['radio'] as List<dynamic>?) ??
                     [];

      return radios
          .map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error searching radio stations: $e');
      return [];
    }
  }

  // ============ PODCASTS ============

  /// Get all podcasts from the library
  Future<List<MediaItem>> getPodcasts({
    int? limit,
    int? offset,
    bool? favoriteOnly,
    String? orderBy,
  }) async {
    try {
      final response = await _sendCommand(
        'music/podcasts/library_items',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (favoriteOnly != null) 'favorite': favoriteOnly,
          if (orderBy != null) 'order_by': orderBy,
        },
      );

      final items = response['items'] as List<dynamic>? ?? response['result'] as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting podcasts: $e');
      return [];
    }
  }

  /// Get episodes for a specific podcast
  Future<List<MediaItem>> getPodcastEpisodes(String podcastId, {
    String? provider,
    int? limit,
    int? offset,
  }) async {
    try {
      final response = await _sendCommand(
        'music/podcasts/podcast_episodes',
        args: {
          'item_id': podcastId,
          if (provider != null) 'provider_instance_id_or_domain': provider,
        },
      );

      final episodes = response['result'] as List<dynamic>?;
      if (episodes != null && episodes.isNotEmpty) {
        return episodes
            .map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      return [];
    } catch (e) {
      _logger.log('Error getting podcast episodes: $e');
      return [];
    }
  }

  /// Get best available image URL for a podcast
  /// Falls back to first episode's image if podcast image is unavailable or low quality
  Future<String?> getPodcastCoverUrl(MediaItem podcast, {int size = 1024}) async {
    // First try the podcast's own image
    final podcastImage = getImageUrl(podcast, size: size);

    // Check if podcast has images in metadata
    final images = podcast.metadata?['images'] as List<dynamic>?;
    if (images != null && images.isNotEmpty) {
      // Podcast has images, use them
      return podcastImage;
    }

    // No podcast image, try to get first episode's image
    try {
      final episodes = await getPodcastEpisodes(
        podcast.itemId,
        provider: podcast.provider,
      );

      if (episodes.isNotEmpty) {
        final firstEpisode = episodes.first;
        final episodeImage = getImageUrl(firstEpisode, size: size);
        if (episodeImage != null) {
          return episodeImage;
        }
      }
    } catch (e) {
      // Fall through to return podcast image
    }

    // Fall back to podcast image even if it might be low quality
    return podcastImage;
  }

  /// Parse browse results into MediaItem episodes
  List<MediaItem> _parseBrowseEpisodes(List<dynamic> items) {
    final episodes = <MediaItem>[];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final name = item['name'] as String? ??
                    item['label'] as String? ??
                    'Episode';
        final uri = item['uri'] as String? ?? item['path'] as String?;
        final itemId = item['item_id'] as String? ?? uri ?? '';
        final provider = item['provider'] as String? ?? 'library';

        // Parse media type from string
        final mediaTypeStr = item['media_type'] as String?;
        MediaType mediaType = MediaType.track;
        if (mediaTypeStr != null) {
          mediaType = MediaType.values.firstWhere(
            (e) => e.name == mediaTypeStr || e.name == mediaTypeStr.toLowerCase(),
            orElse: () => MediaType.track,
          );
        }

        // Get duration if available
        Duration? duration;
        final durationVal = item['duration'];
        if (durationVal is int) {
          duration = Duration(seconds: durationVal);
        } else if (durationVal is double) {
          duration = Duration(seconds: durationVal.toInt());
        }

        episodes.add(MediaItem(
          itemId: itemId,
          provider: provider,
          name: name,
          uri: uri,
          metadata: item['metadata'] as Map<String, dynamic>?,
          mediaType: mediaType,
          duration: duration,
        ));
      }
    }
    return episodes;
  }

  /// Play a podcast episode
  Future<void> playPodcastEpisode(String playerId, MediaItem episode) async {
    try {
      // Try episode.uri first, then construct from itemId
      String uri;
      if (episode.uri != null && episode.uri!.isNotEmpty) {
        uri = episode.uri!;
      } else {
        // Construct URI based on media type
        uri = 'library://podcast_episode/${episode.itemId}';
      }

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri],
          'option': 'replace',
        },
      );
    } catch (e) {
      _logger.log('Error playing podcast episode: $e');
      rethrow;
    }
  }

  Future<List<Audiobook>> getAudiobooks({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
    String? authorId,
    List<String>? providerInstanceIds,
  }) async {
    try {
      final allAudiobooks = <Audiobook>[];
      final seenIds = <String>{};

      // Check if library filtering is enabled (for ABS providers)
      final enabledLibraries = await SettingsService.getEnabledAbsLibraries();

      // Extract ABS provider IDs from library paths
      final absProviderIds = <String>{};
      if (enabledLibraries != null && enabledLibraries.isNotEmpty) {
        for (final libPath in enabledLibraries) {
          final providerEnd = libPath.indexOf('://');
          if (providerEnd != -1) {
            absProviderIds.add(libPath.substring(0, providerEnd));
          }
        }
      }

      _logger.log('📚 getAudiobooks: absProviderIds=$absProviderIds, providerInstanceIds=$providerInstanceIds');

      // PART 1: Fetch from ABS providers using browse API (for library filtering support)
      if (enabledLibraries != null && enabledLibraries.isNotEmpty) {
        // If specific providers are requested, filter libraries to only matching ABS providers
        var librariesToBrowse = enabledLibraries;
        if (providerInstanceIds != null && providerInstanceIds.isNotEmpty) {
          librariesToBrowse = enabledLibraries.where((libPath) {
            final providerEnd = libPath.indexOf('://');
            if (providerEnd == -1) return false;
            final providerId = libPath.substring(0, providerEnd);
            return providerInstanceIds.contains(providerId);
          }).toList();
        }

        if (librariesToBrowse.isNotEmpty) {
          final browseBooks = await _getAudiobooksFromBrowse(librariesToBrowse, favoriteOnly: favoriteOnly);
          for (final book in browseBooks) {
            if (!seenIds.contains(book.itemId)) {
              seenIds.add(book.itemId);
              allAudiobooks.add(book);
            }
          }
          _logger.log('📚 Got ${browseBooks.length} audiobooks from ABS browse API');

          // If browse returned nothing, the saved library paths may be stale
          // (e.g., after provider was removed and re-added with new instance ID)
          // Clear the stale settings so we fall back to library_items API
          if (browseBooks.isEmpty) {
            _logger.log('📚 Browse returned 0 books - clearing stale library settings');
            await SettingsService.clearEnabledAbsLibraries();
            await SettingsService.setDiscoveredAbsLibraries([]);
          }
        }
      }

      // PART 2: Fetch from non-ABS providers using library_items API
      // This gets audiobooks from Spotify, Plex, Jellyfin, etc.
      List<String>? nonAbsProviders;
      if (providerInstanceIds != null && providerInstanceIds.isNotEmpty) {
        // Filter to only non-ABS providers from the requested list
        nonAbsProviders = providerInstanceIds.where((id) => !absProviderIds.contains(id)).toList();
      } else if (absProviderIds.isNotEmpty) {
        // No specific providers requested, but we have ABS - need to also fetch from non-ABS
        // Pass null to get all, then we'll deduplicate
        nonAbsProviders = null; // Will fetch all
      }

      // Only call library_items API if:
      // 1. No ABS libraries configured (traditional mode), OR
      // 2. We have specific non-ABS providers to query, OR
      // 3. ABS browse returned 0 items (stale paths were cleared above)
      // NOTE: Do NOT call when ABS filtering is active but no non-ABS providers exist,
      // as library_items API would return all audiobooks bypassing the library filter
      final shouldFetchFromApi = enabledLibraries == null ||
                                  enabledLibraries.isEmpty ||
                                  allAudiobooks.isEmpty ||  // Fall back if browse got nothing
                                  (nonAbsProviders != null && nonAbsProviders.isNotEmpty);

      if (shouldFetchFromApi) {
        final args = <String, dynamic>{
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite': favoriteOnly,
          if (authorId != null) 'author_id': authorId,
          if (nonAbsProviders != null && nonAbsProviders.isNotEmpty)
            'provider': nonAbsProviders,
        };

        final response = await _sendCommand(
          'music/audiobooks/library_items',
          args: args,
        );

        if (!response.containsKey('error_code')) {
          final items = response['result'] as List<dynamic>?;
          if (items != null) {
            int addedCount = 0;
            for (int i = 0; i < items.length; i++) {
              try {
                final book = Audiobook.fromJson(items[i] as Map<String, dynamic>);
                // Deduplicate by itemId
                if (!seenIds.contains(book.itemId)) {
                  seenIds.add(book.itemId);
                  allAudiobooks.add(book);
                  addedCount++;
                }
              } catch (e) {
                // Skip items that fail to parse
              }
            }
            _logger.log('📚 Got $addedCount audiobooks from library_items API');
          }
        }
      }

      _logger.log('📚 Total audiobooks: ${allAudiobooks.length}');
      return allAudiobooks;
    } catch (e, stack) {
      _logger.log('Error getting audiobooks: $e');
      _logger.log('Stack: $stack');
      return [];
    }
  }

  /// Get audiobooks using the browse API with library filtering
  Future<List<Audiobook>> _getAudiobooksFromBrowse(
    List<String> enabledLibraryPaths, {
    bool? favoriteOnly,
  }) async {
    final allAudiobooks = <Audiobook>[];

    for (final libraryPath in enabledLibraryPaths) {
      try {
        _logger.log('📚 Browsing library: $libraryPath');

        // Browse the library to find the Audiobooks folder
        final libraryContents = await browse(libraryPath);

        // Find the Audiobooks folder (path ends with /b)
        String? audiobooksPath;
        for (final item in libraryContents) {
          final itemMap = item as Map<String, dynamic>;
          final path = itemMap['path'] as String? ?? '';
          final name = (itemMap['name'] as String? ?? '').toLowerCase();

          if (path.endsWith('/b') || name == 'audiobooks') {
            audiobooksPath = path;
            _logger.log('📚 Found Audiobooks folder: $audiobooksPath');
            break;
          }
        }

        if (audiobooksPath == null) {
          _logger.log('📚 No Audiobooks folder found in library $libraryPath');
          continue;
        }

        // Browse the Audiobooks folder
        final audiobookItems = await browse(audiobooksPath);
        _logger.log('📚 Found ${audiobookItems.length} items in Audiobooks folder');

        for (final item in audiobookItems) {
          final itemMap = item as Map<String, dynamic>;
          final mediaType = itemMap['media_type'] as String?;
          final name = itemMap['name'] as String? ?? '';

          // Skip navigation items
          if (name == '..') continue;

          // Only include audiobooks
          if (mediaType == 'audiobook') {
            try {
              final book = Audiobook.fromJson(itemMap);

              // Apply favorite filter if requested
              if (favoriteOnly == true && book.favorite != true) {
                continue;
              }

              allAudiobooks.add(book);
            } catch (e) {
              _logger.log('📚 Error parsing audiobook "$name": $e');
            }
          }
        }
      } catch (e) {
        _logger.log('📚 Error browsing library $libraryPath: $e');
      }
    }

    _logger.log('📚 Total audiobooks from browse: ${allAudiobooks.length}');
    return allAudiobooks;
  }

  /// Play an audiobook
  Future<void> playAudiobook(String playerId, Audiobook audiobook) async {
    try {
      // Build the audiobook URI
      final uri = audiobook.uri ?? 'library://audiobook/${audiobook.itemId}';
      _logger.log('📚 Playing audiobook: ${audiobook.name} with URI: $uri');

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri],
          'option': 'replace',
        },
      );
    } catch (e) {
      _logger.log('Error playing audiobook: $e');
      rethrow;
    }
  }

  /// Play a radio station
  Future<void> playRadioStation(String playerId, MediaItem station) async {
    try {
      final uri = station.uri ?? 'library://radio/${station.itemId}';
      _logger.log('📻 Playing radio station: ${station.name} with URI: $uri');

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri],
          'option': 'replace',
        },
      );
    } catch (e) {
      _logger.log('Error playing radio station: $e');
      rethrow;
    }
  }

  /// Get full audiobook details including chapters
  Future<Audiobook?> getAudiobookDetails(String provider, String itemId) async {
    try {
      _logger.log('📚 Getting audiobook details: provider=$provider, itemId=$itemId');

      // Try different API patterns to find the correct one
      final apiPatterns = [
        {'cmd': 'music/get_item', 'args': {'media_type': 'audiobook', 'item_id': itemId, 'provider_instance_id_or_domain': provider}},
        {'cmd': 'music/audiobooks/get', 'args': {'item_id': itemId, 'provider_instance_id_or_domain': provider}},
        {'cmd': 'music/item/audiobook/$itemId', 'args': <String, dynamic>{}},
      ];

      Map<String, dynamic>? response;
      String? successCmd;

      for (final pattern in apiPatterns) {
        final cmd = pattern['cmd'] as String;
        final args = pattern['args'] as Map<String, dynamic>;
        _logger.log('📚 Trying: $cmd');

        try {
          response = await _sendCommand(cmd, args: args);
          if (!response.containsKey('error_code')) {
            successCmd = cmd;
            _logger.log('📚 SUCCESS with: $cmd');
            break;
          } else {
            _logger.log('📚 Failed: ${response['error_code']}');
          }
        } catch (e) {
          _logger.log('📚 Exception with $cmd: $e');
        }
      }

      if (successCmd == null || response == null || response.containsKey('error_code')) {
        _logger.log('📚 All API patterns failed, using list data instead');
        // Fall back to fetching from list (which includes metadata)
        final audiobooks = await getAudiobooks(limit: 10000);
        final match = audiobooks.where((b) => b.itemId == itemId).firstOrNull;
        if (match != null) {
          _logger.log('📚 Found in list: ${match.name}');
          return match;
        }
        return null;
      }

      final result = response['result'];
      if (result == null) {
        _logger.log('📚 Audiobook details: result is null');
        return null;
      }

      // Log raw response to understand what MA returns
      final resultMap = result as Map<String, dynamic>;
      _logger.log('📚 ============ AUDIOBOOK DETAILS RAW RESPONSE ============');
      _logger.log('📚 All keys: ${resultMap.keys.toList()}');

      // Log each field for discovery
      for (final key in resultMap.keys) {
        final value = resultMap[key];
        if (value is List) {
          _logger.log('📚 [$key] (List, ${value.length} items): ${value.take(2)}...');
        } else if (value is Map) {
          _logger.log('📚 [$key] (Map): ${(value as Map).keys.toList()}');
        } else {
          _logger.log('📚 [$key]: $value');
        }
      }

      // Check for chapters specifically
      if (resultMap.containsKey('chapters')) {
        final chapters = resultMap['chapters'];
        _logger.log('📚 CHAPTERS FOUND! Type: ${chapters.runtimeType}');
        if (chapters is List && chapters.isNotEmpty) {
          _logger.log('📚 First chapter: ${chapters.first}');
        }
      } else {
        _logger.log('📚 NO chapters field! Checking alternatives...');
        final possibleFields = ['chapters', 'chapter', 'tracks', 'parts', 'segments', 'media_items', 'items', 'content'];
        for (final field in possibleFields) {
          if (resultMap.containsKey(field)) {
            _logger.log('📚 Alternative field "$field" found: ${resultMap[field]}');
          }
        }
      }

      // Check for series info
      if (resultMap.containsKey('metadata')) {
        final metadata = resultMap['metadata'] as Map<String, dynamic>?;
        if (metadata != null) {
          _logger.log('📚 METADATA keys: ${metadata.keys.toList()}');
          for (final key in metadata.keys) {
            _logger.log('📚   metadata[$key]: ${metadata[key]}');
          }
        }
      }

      _logger.log('📚 ============ END RAW RESPONSE ============');

      final audiobook = Audiobook.fromJson(resultMap);
      _logger.log('📚 Parsed audiobook: ${audiobook.name}, chapters: ${audiobook.chapters?.length ?? 0}');
      return audiobook;
    } catch (e, stack) {
      _logger.log('📚 Error getting audiobook details: $e');
      _logger.log('📚 Stack: $stack');
      return null;
    }
  }

  /// Get lyrics for a track
  /// Returns the lyrics text if available, null otherwise
  /// Uses the dedicated metadata/get_track_lyrics endpoint
  Future<String?> getTrackLyrics(Map<String, dynamic> track) async {
    try {
      _logger.log('🎤 Getting lyrics for track: ${track['name']}');

      // Use the dedicated lyrics endpoint
      final response = await _sendCommand(
        'metadata/get_track_lyrics',
        args: {
          'track': track,
        },
      );

      if (response.containsKey('error_code')) {
        _logger.log('🎤 Error getting lyrics: ${response['error_code']}');
        return null;
      }

      // Result is a tuple: [plain_lyrics, synced_lyrics]
      // We prefer synced lyrics if available, otherwise plain
      final result = response['result'];
      if (result is List && result.length >= 2) {
        final plainLyrics = result[0] as String?;
        final syncedLyrics = result[1] as String?;

        if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
          _logger.log('🎤 Found synced lyrics: ${syncedLyrics.length} chars');
          return syncedLyrics;
        }
        if (plainLyrics != null && plainLyrics.isNotEmpty) {
          _logger.log('🎤 Found plain lyrics: ${plainLyrics.length} chars');
          return plainLyrics;
        }
      }

      _logger.log('🎤 No lyrics found in result: $result');
      return null;
    } catch (e) {
      _logger.log('🎤 Error getting lyrics: $e');
      return null;
    }
  }

  /// Browse Music Assistant content by path
  /// Returns a list of browse items (folders or media items)
  Future<List<dynamic>> browse(String? path) async {
    try {
      _logger.log('📚 Browse: path=$path');

      final response = await _sendCommand(
        'music/browse',
        args: path != null ? {'path': path} : <String, dynamic>{},
      );

      if (response.containsKey('error_code')) {
        _logger.log('📚 Browse error: ${response['error_code']}');
        return [];
      }

      final result = response['result'] as List<dynamic>?;
      if (result == null) {
        _logger.log('📚 Browse: result is null');
        return [];
      }

      _logger.log('📚 Browse: found ${result.length} items');

      // Log first few items for debugging
      for (var i = 0; i < result.length && i < 3; i++) {
        final item = result[i] as Map<String, dynamic>;
        _logger.log('📚 Browse[$i]: ${item.keys.toList()}');
        _logger.log('📚 Browse[$i]: path=${item['path']}, name=${item['name']}, label=${item['label']}');
      }

      return result;
    } catch (e) {
      _logger.log('📚 Browse error: $e');
      return [];
    }
  }

  /// Get the audiobookshelf provider instance ID
  Future<String?> getAudiobookshelfProviderId() async {
    try {
      // Get an audiobook and extract the provider instance from it
      final audiobooks = await getAudiobooks(limit: 1);
      if (audiobooks.isEmpty) return null;

      final book = audiobooks.first;
      final mapping = book.providerMappings?.firstWhere(
        (m) => m.providerDomain == 'audiobookshelf',
        orElse: () => book.providerMappings!.first,
      );

      return mapping?.providerInstance;
    } catch (e) {
      _logger.log('📚 Error getting ABS provider ID: $e');
      return null;
    }
  }

  /// Get audiobook series from the browse API
  Future<List<AudiobookSeries>> getAudiobookSeries() async {
    try {
      _logger.log('📚 Getting audiobook series...');

      // First, browse the root to discover available providers
      final rootItems = await browse(null);
      _logger.log('📚 Browse root has ${rootItems.length} items');

      // Find audiobookshelf provider in browse results
      String? providerPath;
      for (final item in rootItems) {
        final itemMap = item as Map<String, dynamic>;
        final path = itemMap['path'] as String? ?? '';

        if (path.contains('audiobookshelf')) {
          providerPath = path;
          _logger.log('📚 Found audiobookshelf provider at: $providerPath');
          break;
        }
      }

      if (providerPath == null) {
        _logger.log('📚 No audiobookshelf provider found in browse root');
        return [];
      }

      // Browse the provider to find libraries
      final providerRoot = await browse(providerPath);
      _logger.log('📚 Provider has ${providerRoot.length} items (libraries)');

      // Discover and save libraries
      final discoveredLibraries = <Map<String, String>>[];
      for (final item in providerRoot) {
        final itemMap = item as Map<String, dynamic>;
        final path = itemMap['path'] as String? ?? '';
        final name = (itemMap['name'] as String?) ?? (itemMap['label'] as String?) ?? '';
        if (path != 'root' && name != '..') {
          discoveredLibraries.add({'path': path, 'name': name});
        }
      }
      if (discoveredLibraries.isNotEmpty) {
        await SettingsService.setDiscoveredAbsLibraries(discoveredLibraries);
        _logger.log('📚 Saved ${discoveredLibraries.length} discovered libraries');
      }

      // Get enabled libraries (null means all enabled)
      final enabledLibraries = await SettingsService.getEnabledAbsLibraries();

      // Collect series from enabled libraries only
      final allSeries = <AudiobookSeries>[];

      for (final libraryItem in providerRoot) {
        final libraryMap = libraryItem as Map<String, dynamic>;
        final libraryPath = libraryMap['path'] as String? ?? '';
        final libraryName = (libraryMap['name'] as String?) ?? (libraryMap['label'] as String?) ?? '';

        // Skip "root" (parent navigation) item
        if (libraryPath == 'root' || libraryName == '..') continue;

        // Check if this library is enabled
        if (enabledLibraries != null && !enabledLibraries.contains(libraryPath)) {
          _logger.log('📚 Skipping disabled library: $libraryName');
          continue;
        }

        _logger.log('📚 Checking library: $libraryName at $libraryPath');

        // Browse into the library to find categories
        final libraryContents = await browse(libraryPath);
        _logger.log('📚 Library "$libraryName" has ${libraryContents.length} items');

        // Log library contents to find series
        for (final item in libraryContents) {
          final itemMap = item as Map<String, dynamic>;
          final name = (itemMap['name'] as String?) ?? (itemMap['label'] as String?) ?? '';
          final path = itemMap['path'] as String? ?? '';
          _logger.log('📚   Library item: name=$name, path=$path');
        }

        // Look for "Series" folder in the library
        for (final item in libraryContents) {
          final itemMap = item as Map<String, dynamic>;
          final name = ((itemMap['name'] as String?) ?? (itemMap['label'] as String?) ?? '').toLowerCase();
          final path = itemMap['path'] as String? ?? '';

          // Check for "series" in name/path, or abbreviated path ending with "/s"
          if (name.contains('series') || path.contains('series') || path.endsWith('/s')) {
            _logger.log('📚 Found series folder: $path');

            // Browse the series folder
            final seriesItems = await browse(path);
            _logger.log('📚 Found ${seriesItems.length} series in library "$libraryName"');

            for (final seriesItem in seriesItems) {
              final seriesMap = seriesItem as Map<String, dynamic>;
              final seriesName = (seriesMap['name'] as String?) ?? (seriesMap['label'] as String?) ?? '';
              final seriesPath = seriesMap['path'] as String? ?? '';
              // Skip parent navigation
              if (seriesPath == 'root' || seriesName == '..' || seriesPath.endsWith('://')) continue;
              // Skip actual audiobook items (we only want series folders)
              final mediaType = seriesMap['media_type'] as String?;
              if (mediaType == 'audiobook' || mediaType == 'track') continue;

              _logger.log('📚 Series: name=$seriesName, path=$seriesPath, media_type=$mediaType');
              allSeries.add(AudiobookSeries.fromJson(seriesMap));
            }
            break; // Found series in this library, move to next library
          }
        }
      }

      _logger.log('📚 Total series found: ${allSeries.length}');
      return allSeries;
    } catch (e, stack) {
      _logger.log('📚 Error getting series: $e');
      _logger.log('📚 Stack: $stack');
      return [];
    }
  }

  /// Get audiobooks in a specific series
  Future<List<Audiobook>> getSeriesAudiobooks(String seriesPath) async {
    try {
      _logger.log('📚 Getting audiobooks for series: $seriesPath');
      _logger.log('📚 About to call browse...');

      final items = await browse(seriesPath);
      _logger.log('📚 Browse returned ${items.length} items');

      final audiobooks = <Audiobook>[];

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        _logger.log('📚 Processing item $i: ${item.runtimeType}');

        if (item is! Map<String, dynamic>) {
          _logger.log('📚 Item $i is not a Map, skipping');
          continue;
        }

        final itemMap = item;
        final mediaType = itemMap['media_type'];
        _logger.log('📚 Item $i: media_type=$mediaType, name=${itemMap['name']}');

        // Only include audiobooks (items with media_type)
        if (mediaType == 'audiobook') {
          _logger.log('📚 Parsing audiobook $i...');
          // Debug: Log key fields for sequence detection
          _logger.log('📚 Raw data $i: position=${itemMap['position']}, sort_name=${itemMap['sort_name']}, metadata.series=${(itemMap['metadata'] as Map?)?['series']}');
          try {
            // Inject browse_order as fallback for series sequencing
            // This preserves the order returned by MA/Audiobookshelf browse API
            if (itemMap['position'] == null) {
              itemMap['_browse_order'] = i + 1; // 1-indexed like series numbers
            }
            audiobooks.add(Audiobook.fromJson(itemMap));
            _logger.log('📚 Parsed audiobook $i successfully');
          } catch (e) {
            _logger.log('📚 Error parsing audiobook $i: $e');
          }
        }
      }

      _logger.log('📚 Found ${audiobooks.length} audiobooks in series');
      return audiobooks;
    } catch (e, stack) {
      _logger.log('📚 Error getting series audiobooks: $e');
      _logger.log('📚 Stack: $stack');
      return [];
    }
  }

  /// Legacy method - now uses browse API
  @Deprecated('Use getAudiobookSeries instead')
  Future<void> exploreSeries() async {
    _logger.log('📚 exploreSeries is deprecated, use getAudiobookSeries instead');
    final series = await getAudiobookSeries();
    _logger.log('📚 Found ${series.length} series via browse API');
  }

  /// Get recently played albums
  /// Gets recently played tracks, then fetches full track details to extract album info
  /// Optimized: batches track lookups to avoid N+1 query problem
  Future<List<Album>> getRecentAlbums({int limit = 10}) async {
    try {
      // Get recently played tracks (simplified objects)
      final response = await _sendCommand(
        'music/recently_played_items',
        args: {
          'limit': limit * 5,
          'media_types': ['track'],
        },
      );

      final items = response['result'] as List<dynamic>?;
      _logger.log('📋 recently_played_items returned ${items?.length ?? 0} items');
      if (items == null || items.isEmpty) {
        _logger.log('⚠️ No recently played tracks found');
        return [];
      }

      // Collect track URIs for batch lookup
      final trackUris = <String>[];
      for (final item in items) {
        final trackUri = (item as Map<String, dynamic>)['uri'] as String?;
        final name = (item as Map<String, dynamic>)['name'] as String?;
        _logger.log('  📀 Track: $name');
        if (trackUri != null) {
          trackUris.add(trackUri);
        }
      }

      if (trackUris.isEmpty) {
        return [];
      }

      // Step 1: Fetch tracks in batches and collect unique album URIs
      final seenAlbumUris = <String>{};
      final albumUris = <String>[];

      const batchSize = LibraryConstants.recentAlbumsBatchSize;
      for (var i = 0; i < trackUris.length && albumUris.length < limit; i += batchSize) {
        final batch = trackUris.skip(i).take(batchSize).toList();

        final futures = batch.map((uri) => _sendCommand(
          'music/item_by_uri',
          args: {'uri': uri},
        ).timeout(const Duration(seconds: 5), onTimeout: () => <String, dynamic>{'result': null}));

        final results = await Future.wait(futures, eagerError: false);

        for (final trackResponse in results) {
          if (albumUris.length >= limit) break;

          try {
            final fullTrack = trackResponse['result'] as Map<String, dynamic>?;
            final trackName = fullTrack?['name'] as String?;
            final albumData = fullTrack?['album'] as Map<String, dynamic>?;
            final albumUri = albumData?['uri'] as String?;
            final albumName = albumData?['name'] as String?;

            if (albumUri != null && !seenAlbumUris.contains(albumUri)) {
              seenAlbumUris.add(albumUri);
              albumUris.add(albumUri);
              _logger.log('  📀 Found album: $albumName from track: $trackName');
            } else if (albumUri == null) {
              _logger.log('  ⚠️ Track "$trackName" has no album');
            }
          } catch (_) {
            continue;
          }
        }
      }

      if (albumUris.isEmpty) {
        return [];
      }

      // Step 2: Fetch full album details (with images) for each album URI
      final albums = <Album>[];
      for (var i = 0; i < albumUris.length; i += batchSize) {
        final batch = albumUris.skip(i).take(batchSize).toList();

        final futures = batch.map((uri) => _sendCommand(
          'music/item_by_uri',
          args: {'uri': uri},
        ).timeout(const Duration(seconds: 5), onTimeout: () => <String, dynamic>{'result': null}));

        final results = await Future.wait(futures, eagerError: false);

        for (final albumResponse in results) {
          try {
            final albumData = albumResponse['result'] as Map<String, dynamic>?;
            if (albumData != null) {
              albums.add(Album.fromJson(albumData));
            }
          } catch (_) {
            continue;
          }
        }
      }

      _logger.log('📚 Fetched ${albums.length} recent albums with full details');
      return albums;
    } catch (e) {
      _logger.log('❌ Error getting recent albums: $e');
      return [];
    }
  }

  /// Get random albums
  Future<List<Album>> getRandomAlbums({
    int limit = 10,
    List<String>? providerInstanceIds,
  }) async {
    try {
      final response = await _sendCommand(
        'music/albums/library_items',
        args: {
          'limit': limit,
          'order_by': 'random',
          if (providerInstanceIds != null && providerInstanceIds.isNotEmpty)
            'provider': providerInstanceIds,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((item) => Album.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting random albums: $e');
      return [];
    }
  }

  /// Get library statistics
  Future<Map<String, int>> getLibraryStats() async {
    try {

      // Get counts for each media type
      final artistsResp = await _sendCommand('music/artists/library_items', args: {'limit': 1});
      final albumsResp = await _sendCommand('music/albums/library_items', args: {'limit': 1});
      final tracksResp = await _sendCommand('music/tracks/library_items', args: {'limit': 1});

      return {
        'artists': (artistsResp['count'] as int?) ?? 0,
        'albums': (albumsResp['count'] as int?) ?? 0,
        'tracks': (tracksResp['count'] as int?) ?? 0,
      };
    } catch (e) {
      _logger.log('Error getting library stats: $e');
      return {'artists': 0, 'albums': 0, 'tracks': 0};
    }
  }

  /// Get album details by URI
  /// Use the album's uri field (e.g., "library://album/123" or "spotify://album/xyz")
  Future<Album?> getAlbumByUri(String uri) async {
    try {
      final response = await _sendCommand(
        'music/item_by_uri',
        args: {
          'uri': uri,
        },
      );

      final result = response['result'];
      if (result == null) return null;

      return Album.fromJson(result as Map<String, dynamic>);
    } catch (e) {
      _logger.log('Error getting album by URI: $e');
      return null;
    }
  }

  /// Get artist details by URI
  Future<Artist?> getArtistByUri(String uri) async {
    try {
      final response = await _sendCommand(
        'music/item_by_uri',
        args: {
          'uri': uri,
        },
      );

      final result = response['result'];
      if (result == null) return null;

      return Artist.fromJson(result as Map<String, dynamic>);
    } catch (e) {
      _logger.log('Error getting artist by URI: $e');
      return null;
    }
  }

  Future<List<Track>> getAlbumTracks(String provider, String itemId) async {
    return await RetryHelper.retryNetwork(
      operation: () async {
        try {
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
            return <Track>[];
          }


          return items
              .map((item) => Track.fromJson(item as Map<String, dynamic>))
              .toList();
        } catch (e) {
          _logger.log('Error getting album tracks: $e');
          return <Track>[];
        }
      },
    ).catchError((e) {
      _logger.log('Error getting album tracks after retries: $e');
      return <Track>[];
    });
  }

  /// Get playlists
  Future<List<Playlist>> getPlaylists({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
    String? orderBy,
    List<String>? providerInstanceIds,
  }) async {
    try {
      final response = await _sendCommand(
        'music/playlists/library_items',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite': favoriteOnly,
          if (orderBy != null) 'order_by': orderBy,
          if (providerInstanceIds != null && providerInstanceIds.isNotEmpty)
            'provider': providerInstanceIds,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      return items
          .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting playlists: $e');
      return [];
    }
  }

  /// Get playlist details
  Future<Playlist?> getPlaylistDetails(String provider, String itemId) async {
    try {
      final response = await _sendCommand(
        'music/playlist',
        args: {
          'provider_instance_id_or_domain': provider,
          'item_id': itemId,
        },
      );

      final result = response['result'];
      if (result == null) return null;

      return Playlist.fromJson(result as Map<String, dynamic>);
    } catch (e) {
      _logger.log('Error getting playlist details: $e');
      return null;
    }
  }

  /// Get playlist tracks
  Future<List<Track>> getPlaylistTracks(String provider, String itemId) async {
    return await RetryHelper.retryNetwork(
      operation: () async {
        try {
          final response = await _sendCommand(
            'music/playlists/playlist_tracks',
            args: {
              'provider_instance_id_or_domain': provider,
              'item_id': itemId,
            },
          );

          final items = response['result'] as List<dynamic>?;
          if (items == null) {
            _logger.log('No result for playlist tracks');
            return <Track>[];
          }

          return items
              .map((item) => Track.fromJson(item as Map<String, dynamic>))
              .toList();
        } catch (e) {
          _logger.log('Error getting playlist tracks: $e');
          return <Track>[];
        }
      },
    ).catchError((e) {
      _logger.log('Error getting playlist tracks after retries: $e');
      return <Track>[];
    });
  }

  // Favorites
  /// Mark item as favorite using URI format
  /// The item parameter should be a URI like "spotify://album/6XyFhbFtcRRR9peJ16em4h"
  Future<void> addToFavorites(String mediaType, String itemId, String provider) async {
    try {
      // Build the URI for the item
      final uri = '$provider://$mediaType/$itemId';
      _logger.log('Adding to favorites: $uri');

      await _sendCommand(
        'music/favorites/add_item',
        args: {
          'item': uri,
        },
      );
    } catch (e) {
      _logger.log('Error adding to favorites: $e');
      rethrow;
    }
  }

  /// Remove item from favorites
  /// Requires the library_item_id (the numeric ID in the MA library)
  Future<void> removeFromFavorites(String mediaType, int libraryItemId) async {
    await _sendCommand(
      'music/favorites/remove_item',
      args: {
        'media_type': mediaType,
        'library_item_id': libraryItemId,
      },
    );
  }

  // Library
  /// Add item to library using URI format
  /// The item parameter should be a URI like "spotify://artist/4tZwfgrHOc3mvqYlEYSvVi"
  Future<void> addItemToLibrary(String mediaType, String itemId, String provider) async {
    final uri = '$provider://$mediaType/$itemId';
    await _sendCommand(
      'music/library/add_item',
      args: {
        'item': uri,
      },
    );
  }

  /// Remove item from library
  /// Requires the library_item_id (the numeric ID in the MA library)
  Future<void> removeItemFromLibrary(String mediaType, int libraryItemId) async {
    await _sendCommand(
      'music/library/remove_item',
      args: {
        'media_type': mediaType,
        'library_item_id': libraryItemId,
      },
    );
  }

  // Search
  /// Search across all providers (Spotify, etc.) and library
  /// Set libraryOnly to true to search only local library
  Future<Map<String, List<MediaItem>>> search(String query, {bool libraryOnly = false}) async {
    return await RetryHelper.retryNetwork(
      operation: () async {
        try {

          // Use the global search command that searches across all providers
          final searchResponse = await _sendCommand(
            'music/search',
            args: {
              'search_query': query,
              'limit': 50, // Results per media type
              'library_only': libraryOnly,
            },
          );

          final result = searchResponse['result'] as Map<String, dynamic>?;
          if (result == null) {
            return <String, List<MediaItem>>{'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': [], 'radios': []};
          }

          // Parse results from the search response
          final artists = (result['artists'] as List<dynamic>?)
                  ?.map((item) => Artist.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              [];

          final albums = (result['albums'] as List<dynamic>?)
                  ?.map((item) => Album.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              [];

          final tracks = (result['tracks'] as List<dynamic>?)
                  ?.map((item) => Track.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              [];

          final playlists = (result['playlists'] as List<dynamic>?)
                  ?.map((item) => Playlist.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              [];

          final audiobooks = (result['audiobooks'] as List<dynamic>?)
                  ?.map((item) => Audiobook.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              [];

          final radios = (result['radios'] as List<dynamic>?)
                  ?.map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              [];

          final podcasts = (result['podcasts'] as List<dynamic>?)
                  ?.map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              [];

          // Deduplicate results by name
          // MA returns both library items and provider items for the same content
          // Prefer library items (provider='library') as they have all provider mappings
          return <String, List<MediaItem>>{
            'artists': _deduplicateResults(artists),
            'albums': _deduplicateResults(albums),
            'tracks': _deduplicateResults(tracks),
            'playlists': _deduplicateResults(playlists),
            'audiobooks': _deduplicateResults(audiobooks),
            'radios': _deduplicateResults(radios),
            'podcasts': _deduplicateResults(podcasts),
          };
        } catch (e) {
          _logger.log('Error searching: $e');
          return <String, List<MediaItem>>{'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': [], 'radios': [], 'podcasts': []};
        }
      },
    ).catchError((e) {
      _logger.log('Error searching after retries: $e');
      return <String, List<MediaItem>>{'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': [], 'radios': [], 'podcasts': []};
    });
  }

  /// Search for podcasts globally (across all providers)
  Future<List<MediaItem>> searchPodcasts(String query, {int limit = 25}) async {
    try {
      _logger.log('🎙️ Searching podcasts for: $query');
      final response = await _sendCommand(
        'music/search',
        args: {
          'search_query': query,
          'media_types': ['podcast'],
          'limit': limit,
        },
      );

      final result = response['result'] as Map<String, dynamic>?;
      if (result == null) {
        _logger.log('🎙️ Podcast search: no result');
        return [];
      }

      // Podcast results might be under 'podcasts' or 'podcast' key
      final podcasts = (result['podcasts'] as List<dynamic>?) ??
                       (result['podcast'] as List<dynamic>?) ??
                       [];

      _logger.log('🎙️ Podcast search found ${podcasts.length} results');

      return podcasts
          .map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('🎙️ Error searching podcasts: $e');
      return [];
    }
  }

  /// Deduplicate search results by name (case-insensitive)
  /// Prefers library items (provider='library') over provider-specific items
  /// since library items have complete provider mappings
  List<T> _deduplicateResults<T extends MediaItem>(List<T> items) {
    final Map<String, T> seen = {};

    for (final item in items) {
      // Use lowercase name as key for deduplication
      final key = item.name.toLowerCase();
      final existing = seen[key];
      if (existing == null) {
        // First time seeing this name
        seen[key] = item;
      } else if (item.provider == 'library' && existing.provider != 'library') {
        // Prefer library item over provider item
        seen[key] = item;
      }
      // Otherwise keep the existing item (first occurrence or already library)
    }

    return seen.values.toList();
  }

  // ============================================================================
  // PLAYER AND QUEUE MANAGEMENT (Queue-based streaming for full track playback)
  // ============================================================================

  /// Get all available players
  Future<List<Player>> getPlayers() async {
    return await RetryHelper.retryNetwork(
      operation: () async {
        final response = await _sendCommand('players/all');

        final items = response['result'] as List<dynamic>?;
        if (items == null) return <Player>[];

        // Debug: Log raw player data for the first playing player
        for (var item in items) {
          if (item['state'] == 'playing') {
            break;
          }
        }

        final players = items
            .map((item) => Player.fromJson(item as Map<String, dynamic>))
            .toList();

        return players;
      },
    ).catchError((e) {
      _logger.log('Error getting players after retries: $e');
      return <Player>[];
    });
  }

  /// Get player queue
  Future<PlayerQueue?> getQueue(String playerId) async {
    return await RetryHelper.retryNetwork(
      operation: () async {
        try {

          // Try to get full queue object first
          // First, get the queue metadata which includes current_index, shuffle, repeat, etc
          int? currentIndex;
          bool? shuffleEnabled;
          String? repeatMode;

          try {
            final queueResponse = await _sendCommand(
              'player_queues/get',
              args: {'queue_id': playerId},
            );

            // Extract metadata from the queue object
            final queueResult = queueResponse['result'] as Map<String, dynamic>?;
            if (queueResult != null) {
              currentIndex = queueResult['current_index'] as int?;
              shuffleEnabled = queueResult['shuffle_enabled'] as bool?;
              repeatMode = queueResult['repeat_mode'] as String?;
              _logger.log('🔀 Queue metadata: shuffle_enabled=$shuffleEnabled, repeat_mode=$repeatMode');

              final currentItemData = queueResult['current_item'] as Map<String, dynamic>?;
              final currentItemName = currentItemData?['name'] as String?;
              final totalItems = queueResult['items'] as int?;

            }
          } catch (e) {
            _logger.log('⚠️ player_queues/get not available: $e');
          }

          // Now get the queue items
          final response = await _sendCommand(
            'player_queues/items',
            args: {'queue_id': playerId},
          );

          final result = response['result'];
          if (result == null) {
            _logger.log('❌ player_queues/items returned null result');
            return null;
          }


          // The API returns a List of items directly, not a PlayerQueue object
          final items = <QueueItem>[];
          for (var i in (result as List<dynamic>)) {
            try {
              items.add(QueueItem.fromJson(i as Map<String, dynamic>));
            } catch (e) {
              _logger.log('⚠️ Failed to parse queue item: $e');
              // Continue parsing other items
            }
          }

          if (items.isEmpty) {
            _logger.log('⚠️ Queue is empty or all items failed to parse');
            return null;
          }


          // Validate current index
          if (currentIndex != null && (currentIndex < 0 || currentIndex >= items.length)) {
            currentIndex = null;
          }

          return PlayerQueue(
            playerId: playerId,
            items: items,
            currentIndex: currentIndex,
            shuffleEnabled: shuffleEnabled,
            repeatMode: repeatMode,
          );
        } catch (e) {
          _logger.log('Error getting queue: $e');
          return null;
        }
      },
    ).catchError((e) {
      _logger.log('Error getting queue after retries: $e');
      return null;
    });
  }

  /// Play a single track via queue
  /// If clearQueue is true, replaces the queue (default behavior)
  Future<void> playTrack(String playerId, Track track, {bool clearQueue = true}) async {
    try {
      // Build URI from provider mappings
      final uri = _buildTrackUri(track);
      final option = clearQueue ? 'replace' : 'play';

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri], // Array of URI strings, not objects
          'option': option, // 'replace' clears queue, 'play' adds to queue
        },
      );

    } catch (e) {
      _logger.log('Error playing track: $e');
      rethrow;
    }
  }

  /// Add a single track to the queue without starting playback
  Future<void> addTrackToQueue(String playerId, Track track) async {
    try {
      final uri = _buildTrackUri(track);

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri],
          'option': 'add',  // Add to queue without starting
        },
      );
    } catch (e) {
      _logger.log('Error adding track to queue: $e');
      rethrow;
    }
  }

  /// Play album on player
  Future<void> playAlbum(String playerId, Album album) async {
    try {
      final uri = album.uri ?? 'library://album/${album.itemId}';
      _logger.log('💿 Playing album: ${album.name} with URI: $uri');

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri],
          'option': 'replace',
        },
      );
    } catch (e) {
      _logger.log('Error playing album: $e');
      rethrow;
    }
  }

  /// Add album tracks to queue
  Future<void> addAlbumToQueue(String playerId, Album album) async {
    try {
      final uri = album.uri ?? 'library://album/${album.itemId}';
      _logger.log('💿 Adding album to queue: ${album.name} with URI: $uri');

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri],
          'option': 'add',
        },
      );
    } catch (e) {
      _logger.log('Error adding album to queue: $e');
      rethrow;
    }
  }

  /// Add artist tracks to queue
  Future<void> addArtistToQueue(String playerId, Artist artist) async {
    try {
      final uri = artist.uri ?? 'library://artist/${artist.itemId}';
      _logger.log('🎤 Adding artist to queue: ${artist.name} with URI: $uri');

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri],
          'option': 'add',
        },
      );
    } catch (e) {
      _logger.log('Error adding artist to queue: $e');
      rethrow;
    }
  }

  /// Play playlist on player
  Future<void> playPlaylist(String playerId, Playlist playlist) async {
    try {
      final uri = playlist.uri ?? 'library://playlist/${playlist.itemId}';
      _logger.log('📝 Playing playlist: ${playlist.name} with URI: $uri');

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri],
          'option': 'replace',
        },
      );
    } catch (e) {
      _logger.log('Error playing playlist: $e');
      rethrow;
    }
  }

  /// Play multiple tracks via queue
  /// If clearQueue is true, replaces the queue (default behavior)
  /// If startIndex is provided, only tracks from that index onwards will be queued
  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex, bool clearQueue = true}) async {
    return await RetryHelper.retry(
      maxAttempts: 3,
      initialDelaySeconds: 1,
      maxDelaySeconds: 4,
      // Don't retry errors about missing/unavailable tracks - those won't resolve with retries
      shouldRetry: (error) {
        final errorStr = error.toString().toLowerCase();
        if (errorStr.contains('no playable') ||
            errorStr.contains('no tracks') ||
            errorStr.contains('lack available')) {
          return false;
        }
        return true;
      },
      operation: () async {
        // If startIndex is provided, slice the tracks list to start from that index
        // This is a workaround since Music Assistant ignores the start_item parameter
        final tracksToPlay = startIndex != null && startIndex > 0
            ? tracks.sublist(startIndex)
            : tracks;

        if (tracksToPlay.isEmpty) {
          throw Exception('No tracks to play');
        }

        // Filter to only tracks with available provider mappings
        final playableTracks = tracksToPlay.where((track) {
          if (track.providerMappings == null || track.providerMappings!.isEmpty) {
            _logger.log('⚠️ Track "${track.name}" has no provider mappings');
            return false;
          }
          final hasAvailable = track.providerMappings!.any((m) => m.available);
          if (!hasAvailable) {
            _logger.log('⚠️ Track "${track.name}" has no available providers');
          }
          return hasAvailable;
        }).toList();

        if (playableTracks.isEmpty) {
          _logger.log('❌ No playable tracks found (${tracksToPlay.length} tracks had no available providers)');
          throw Exception('No playable tracks - all ${tracksToPlay.length} tracks lack available providers');
        }

        if (playableTracks.length < tracksToPlay.length) {
          _logger.log('⚠️ ${tracksToPlay.length - playableTracks.length} tracks skipped (no available providers)');
        }

        // Build array of URI strings (not objects!)
        final mediaUris = playableTracks.map((track) => _buildTrackUri(track)).toList();

        _logger.log('🎵 Playing ${mediaUris.length} tracks: ${mediaUris.take(3).join(", ")}${mediaUris.length > 3 ? "..." : ""}');

        final option = clearQueue ? 'replace' : 'play';

        final args = {
          'queue_id': playerId,
          'media': mediaUris, // Array of URI strings
          'option': option, // 'replace' clears queue, 'play' adds to queue
        };


        await _sendCommand(
          'player_queues/play_media',
          args: args,
        );

      },
    );
  }

  /// Play radio based on a track (generates similar tracks)
  /// Prefers streaming provider URIs (Spotify, Tidal, etc.) for better recommendations
  Future<void> playRadio(String playerId, Track track) async {
    return await RetryHelper.retryCritical(
      operation: () async {
        // For radio mode, prefer streaming providers (Spotify, Tidal, etc.)
        // as they provide better dynamic track recommendations
        final trackUri = _buildRadioUri(track);
        _logger.log('Radio: Starting with URI $trackUri');

        final args = {
          'queue_id': playerId,
          'media': [trackUri],
          'option': 'replace',
          'radio_mode': true, // Enable radio mode for similar tracks
        };

        await _sendCommand(
          'player_queues/play_media',
          args: args,
        );

      },
    );
  }

  /// Build URI for radio mode, preferring streaming providers for better recommendations
  /// Priority: Spotify > Tidal > Deezer > Apple > YTM > Subsonic > any available > library
  /// Note: Qobuz does NOT support radio mode (no dynamic_tracks API)
  String _buildRadioUri(Track track) {
    if (track.providerMappings != null && track.providerMappings!.isNotEmpty) {
      // Providers that support dynamic radio recommendations (in priority order)
      // Qobuz is excluded - it doesn't support similar tracks API
      const radioProviders = ['spotify', 'tidal', 'deezer', 'apple', 'ytmusic', 'subsonic', 'opensubsonic'];

      // Try to find a streaming provider first
      for (final providerPrefix in radioProviders) {
        final mapping = track.providerMappings!.firstWhere(
          (m) => m.available && m.providerInstance.toLowerCase().startsWith(providerPrefix),
          orElse: () => ProviderMapping(providerInstance: '', providerDomain: '', itemId: '', available: false),
        );
        if (mapping.providerInstance.isNotEmpty) {
          return '${mapping.providerInstance}://track/${mapping.itemId}';
        }
      }

      // Fall back to any available provider (but not library)
      final nonLibraryMapping = track.providerMappings!.firstWhere(
        (m) => m.available && m.providerInstance != 'library',
        orElse: () => ProviderMapping(providerInstance: '', providerDomain: '', itemId: '', available: false),
      );
      if (nonLibraryMapping.providerInstance.isNotEmpty) {
        return '${nonLibraryMapping.providerInstance}://track/${nonLibraryMapping.itemId}';
      }
    }

    // Last resort: use library URI or build from top-level provider
    return track.uri ?? _buildTrackUri(track);
  }

  /// Play radio based on an artist (generates tracks from and similar to the artist)
  /// Prefers streaming provider URIs (Spotify, Tidal, etc.) for better recommendations
  Future<void> playArtistRadio(String playerId, Artist artist) async {
    return await RetryHelper.retryCritical(
      operation: () async {
        final artistUri = _buildArtistRadioUri(artist);
        _logger.log('Radio: Starting artist radio with URI $artistUri');

        final args = {
          'queue_id': playerId,
          'media': [artistUri],
          'option': 'replace',
          'radio_mode': true,
        };

        await _sendCommand(
          'player_queues/play_media',
          args: args,
        );
      },
    );
  }

  /// Add artist radio to queue (instead of replacing)
  Future<void> playArtistRadioToQueue(String playerId, Artist artist) async {
    return await RetryHelper.retryCritical(
      operation: () async {
        final artistUri = _buildArtistRadioUri(artist);
        _logger.log('Radio: Adding artist radio to queue with URI $artistUri');

        final args = {
          'queue_id': playerId,
          'media': [artistUri],
          'option': 'add',  // Add to queue instead of replace
          'radio_mode': true,
        };

        await _sendCommand(
          'player_queues/play_media',
          args: args,
        );
      },
    );
  }

  /// Build URI for artist radio mode, preferring streaming providers
  /// Note: Qobuz does NOT support radio mode (no dynamic_tracks API)
  String _buildArtistRadioUri(Artist artist) {
    if (artist.providerMappings != null && artist.providerMappings!.isNotEmpty) {
      // Qobuz is excluded - it doesn't support similar tracks API
      const radioProviders = ['spotify', 'tidal', 'deezer', 'apple', 'ytmusic', 'subsonic', 'opensubsonic'];

      for (final providerPrefix in radioProviders) {
        final mapping = artist.providerMappings!.firstWhere(
          (m) => m.available && m.providerInstance.toLowerCase().startsWith(providerPrefix),
          orElse: () => ProviderMapping(providerInstance: '', providerDomain: '', itemId: '', available: false),
        );
        if (mapping.providerInstance.isNotEmpty) {
          return '${mapping.providerInstance}://artist/${mapping.itemId}';
        }
      }

      final nonLibraryMapping = artist.providerMappings!.firstWhere(
        (m) => m.available && m.providerInstance != 'library',
        orElse: () => ProviderMapping(providerInstance: '', providerDomain: '', itemId: '', available: false),
      );
      if (nonLibraryMapping.providerInstance.isNotEmpty) {
        return '${nonLibraryMapping.providerInstance}://artist/${nonLibraryMapping.itemId}';
      }
    }

    return artist.uri ?? '${artist.provider}://artist/${artist.itemId}';
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
      if (streamId == null) {
        _logger.log('⚠️ Stream ID not available yet');
        return null;
      }

      final contentType = currentItem.streamdetails!.contentType;
      final extension = _getExtension(contentType);

      // Construct streaming URL using correct port
      // Logic should match connect() but for HTTP/HTTPS streaming endpoint
      
      var baseUrl = serverUrl;
      var useSecure = true;

      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        // Determine protocol based on ws/wss if present, or default to http
        if (baseUrl.startsWith('wss://')) {
          baseUrl = 'https://' + baseUrl.substring(6);
          useSecure = true;
        } else if (baseUrl.startsWith('ws://')) {
          baseUrl = 'http://' + baseUrl.substring(5);
          useSecure = false;
        } else {
          // Default to secure
          baseUrl = 'https://$baseUrl';
          useSecure = true;
        }
      } else {
        useSecure = baseUrl.startsWith('https://');
      }

      final uri = Uri.parse(baseUrl);
      
      // Construct stream URL
      // For reverse proxy compatibility, don't add default ports (80/443)
      Uri finalUri;
      if (_cachedCustomPort != null) {
        // Use custom port from settings
        finalUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: _cachedCustomPort,
          path: '/flow/$playerId/$streamId.$extension',
        );
      } else if (uri.hasPort) {
        // Use port from URL
        finalUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.port,
          path: '/flow/$playerId/$streamId.$extension',
        );
      } else if (useSecure) {
        // For HTTPS with no custom port, omit port (implicit 443)
        finalUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          path: '/flow/$playerId/$streamId.$extension',
        );
      } else {
        // For HTTP with no custom port, use MA default port 8095
        finalUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: NetworkConstants.defaultWsPort,
          path: '/flow/$playerId/$streamId.$extension',
        );
      }

      final streamUrl = finalUri.toString();
      _logger.log('Generated stream URL: $streamUrl');

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
  Future<void> setPower(String playerId, bool powered) async {
    _logger.log('🔋 API setPower: playerId=$playerId, powered=$powered');
    await _sendCommand(
      'players/cmd/power',
      args: {
        'player_id': playerId,
        'powered': powered,
      },
    );
    _logger.log('🔋 API setPower command completed');
  }

  Future<void> pausePlayer(String playerId) async {
    await _sendQueueCommand(playerId, 'pause');
  }

  Future<void> resumePlayer(String playerId) async {
    await _sendQueueCommand(playerId, 'play');
  }

  Future<void> nextTrack(String playerId) async {
    await _sendQueueCommand(playerId, 'next');
  }

  Future<void> previousTrack(String playerId) async {
    await _sendQueueCommand(playerId, 'previous');
  }

  Future<void> stopPlayer(String playerId) async {
    await _sendQueueCommand(playerId, 'stop');
  }

  /// Set player volume (0-100)
  Future<void> setVolume(String playerId, int volumeLevel) async {
    try {
      await _sendCommand(
        'players/cmd/volume_set',
        args: {
          'player_id': playerId,
          'volume_level': volumeLevel.clamp(0, 100),
        },
      );
    } catch (e) {
      _logger.log('Error setting volume: $e');
      rethrow;
    }
  }

  /// Mute or unmute player
  Future<void> setMute(String playerId, bool muted) async {
    try {
      await _sendCommand(
        'players/cmd/volume_mute',
        args: {
          'player_id': playerId,
          'muted': muted,
        },
      );
    } catch (e) {
      _logger.log('Error setting mute: $e');
      rethrow;
    }
  }

  /// Sync a player to a leader/group (temporary group)
  /// The player will join the leader's sync group and play the same audio
  Future<void> syncPlayerToLeader(String playerId, String leaderPlayerId) async {
    try {
      _logger.log('🔗 API syncPlayerToLeader called');
      _logger.log('🔗 player_id: $playerId');
      _logger.log('🔗 target_player: $leaderPlayerId');

      final response = await _sendCommand(
        'players/cmd/group',
        args: {
          'player_id': playerId,
          'target_player': leaderPlayerId,
        },
      );
      _logger.log('✅ Player synced successfully, response: $response');
    } catch (e) {
      _logger.log('❌ Error syncing player: $e');
      rethrow;
    }
  }

  /// Remove a player from its sync group
  Future<void> unsyncPlayer(String playerId) async {
    try {
      _logger.log('🔓 Unsyncing player: $playerId');
      await _sendCommand(
        'players/cmd/ungroup',
        args: {
          'player_id': playerId,
        },
      );
      _logger.log('✅ Player unsynced successfully');
    } catch (e) {
      _logger.log('Error unsyncing player: $e');
      rethrow;
    }
  }

  /// Toggle shuffle mode for queue
  Future<void> toggleShuffle(String queueId, bool shuffleEnabled) async {
    try {
      await _sendCommand(
        'player_queues/shuffle',
        args: {'queue_id': queueId, 'shuffle_enabled': shuffleEnabled},
      );
    } catch (e) {
      _logger.log('Error toggling shuffle: $e');
      rethrow;
    }
  }

  /// Set repeat mode for queue: 'off', 'one', 'all'
  Future<void> setRepeatMode(String queueId, String mode) async {
    try {
      await _sendCommand(
        'player_queues/repeat',
        args: {
          'queue_id': queueId,
          'repeat_mode': mode, // 'off', 'one', 'all'
        },
      );
    } catch (e) {
      _logger.log('Error setting repeat mode: $e');
      rethrow;
    }
  }

  /// Seek to position in seconds
  Future<void> seek(String queueId, int position) async {
    try {
      await _sendCommand(
        'player_queues/seek',
        args: {
          'queue_id': queueId,
          'position': position,
        },
      );
    } catch (e) {
      _logger.log('Error seeking: $e');
      rethrow;
    }
  }

  /// Delete an item from the queue
  Future<void> queueCommandDeleteItem(String queueId, String itemId) async {
    try {
      await _sendCommand(
        'player_queues/delete_item',
        args: {
          'queue_id': queueId,
          'item_id_or_index': itemId,
        },
      );
    } catch (e) {
      _logger.log('Error deleting queue item: $e');
      rethrow;
    }
  }

  /// Move an item in the queue by a relative position shift
  /// pos_shift > 0: move down, pos_shift < 0: move up, pos_shift = 0: move to next
  Future<void> queueCommandMoveItem(String queueId, String itemId, int posShift) async {
    try {
      await _sendCommand(
        'player_queues/move_item',
        args: {
          'queue_id': queueId,
          'queue_item_id': itemId,
          'pos_shift': posShift,
        },
      );
    } catch (e) {
      _logger.log('Error moving queue item: $e');
      rethrow;
    }
  }

  /// Play a specific item in the queue by its queue_item_id
  Future<void> queueCommandPlayIndex(String queueId, String queueItemId) async {
    try {
      await _sendCommand(
        'player_queues/play_index',
        args: {
          'queue_id': queueId,
          'index': queueItemId,
        },
      );
    } catch (e) {
      _logger.log('Error playing queue item: $e');
      rethrow;
    }
  }

  /// Clear all items from the queue
  Future<void> queueCommandClear(String queueId) async {
    try {
      await _sendCommand(
        'player_queues/clear',
        args: {
          'queue_id': queueId,
        },
      );
    } catch (e) {
      _logger.log('Error clearing queue: $e');
      rethrow;
    }
  }

  /// Transfer the current queue to another player
  /// This moves the entire playback queue from source player to target player,
  /// including shuffle and repeat settings.
  ///
  /// [sourceQueueId] - The queue ID of the source player (optional, uses first playing player if null)
  /// [targetQueueId] - The queue ID of the target player (required)
  /// [autoPlay] - Whether to automatically start playback on the target player (default: true)
  Future<void> transferQueue({
    String? sourceQueueId,
    required String targetQueueId,
    bool autoPlay = true,
  }) async {
    try {
      _logger.log('🔄 Transferring queue to player: $targetQueueId (source: ${sourceQueueId ?? "auto"}, autoPlay: $autoPlay)');

      final args = <String, dynamic>{
        'target_queue_id': targetQueueId,
        'auto_play': autoPlay,
      };

      // Only include source_queue_id if explicitly provided
      // When null, MA will use the first playing player
      if (sourceQueueId != null) {
        args['source_queue_id'] = sourceQueueId;
      }

      await _sendCommand(
        'player_queues/transfer',
        args: args,
      );

      _logger.log('✅ Queue transferred successfully');
    } catch (e) {
      _logger.log('❌ Error transferring queue: $e');
      rethrow;
    }
  }

  // ============================================================================
  // BUILT-IN PLAYER MANAGEMENT
  // ============================================================================

  Stream<Map<String, dynamic>> get builtinPlayerEvents {
    if (!_eventStreams.containsKey('builtin_player')) {
      _eventStreams['builtin_player'] = StreamController<Map<String, dynamic>>.broadcast();
    }
    return _eventStreams['builtin_player']!.stream;
  }

  /// Stream of player_updated events (for metadata extraction)
  Stream<Map<String, dynamic>> get playerUpdatedEvents {
    if (!_eventStreams.containsKey('player_updated')) {
      _eventStreams['player_updated'] = StreamController<Map<String, dynamic>>.broadcast();
    }
    return _eventStreams['player_updated']!.stream;
  }

  /// Stream of player_added events (for refreshing player list when new players join)
  Stream<Map<String, dynamic>> get playerAddedEvents {
    if (!_eventStreams.containsKey('player_added')) {
      _eventStreams['player_added'] = StreamController<Map<String, dynamic>>.broadcast();
    }
    return _eventStreams['player_added']!.stream;
  }

  /// Stream of media_item_added events (for refreshing library when items are added)
  Stream<Map<String, dynamic>> get mediaItemAddedEvents {
    if (!_eventStreams.containsKey('media_item_added')) {
      _eventStreams['media_item_added'] = StreamController<Map<String, dynamic>>.broadcast();
    }
    return _eventStreams['media_item_added']!.stream;
  }

  /// Stream of media_item_deleted events (for refreshing library when items are removed)
  Stream<Map<String, dynamic>> get mediaItemDeletedEvents {
    if (!_eventStreams.containsKey('media_item_deleted')) {
      _eventStreams['media_item_deleted'] = StreamController<Map<String, dynamic>>.broadcast();
    }
    return _eventStreams['media_item_deleted']!.stream;
  }

  /// Stream of queue_updated events (for queue metadata changes)
  Stream<Map<String, dynamic>> get queueUpdatedEvents {
    if (!_eventStreams.containsKey('queue_updated')) {
      _eventStreams['queue_updated'] = StreamController<Map<String, dynamic>>.broadcast();
    }
    return _eventStreams['queue_updated']!.stream;
  }

  /// Stream of queue_items_updated events (for queue item add/remove/reorder)
  /// This is critical for keeping queue UI in sync, especially in radio mode
  Stream<Map<String, dynamic>> get queueItemsUpdatedEvents {
    if (!_eventStreams.containsKey('queue_items_updated')) {
      _eventStreams['queue_items_updated'] = StreamController<Map<String, dynamic>>.broadcast();
    }
    return _eventStreams['queue_items_updated']!.stream;
  }

  /// Register this device as a player with retry logic
  /// CRITICAL: This creates a player config in MA's settings.json
  /// The server expects: player_id and player_name
  /// The server SHOULD set: provider=builtin_player, enabled=true, available=true
  ///
  /// Implements retry pattern from research: exponential backoff for reliability
  Future<void> registerBuiltinPlayer(String playerId, String name) async {
    const maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        attempt++;
        if (attempt > 1) {
          final delay = Duration(milliseconds: 500 * (1 << (attempt - 2))); // 500ms, 1s, 2s
          _logger.log('Player: Retrying... (attempt $attempt/$maxRetries)');
          await Future.delayed(delay);
        }

        _logger.log('Player: Registering "$name" (attempt $attempt/$maxRetries)');

        final response = await _sendCommand(
          'builtin_player/register',
          args: {
            'player_id': playerId,
            'player_name': name,  // Server expects 'player_name', not 'name'
          },
        );

        _logger.log('Player: Registered successfully');
        // Internal: Registration response logged for debugging

        // NOTE: config/players/save removed - official MA clients don't use it
        // and it causes error 999. Registration alone is sufficient.

        // VERIFICATION: Check that the player was actually created properly
        // Wait a moment for server to process, then verify
        await Future.delayed(const Duration(milliseconds: 500));

        final players = await getPlayers();
        final registeredPlayer = players.where((p) => p.playerId == playerId).firstOrNull;

        if (registeredPlayer == null) {
          _logger.log('Player: Warning - not found in player list after registration');
          // This is concerning but not fatal - player might appear later
        } else if (!registeredPlayer.available) {
          _logger.log('Player: Warning - registered but marked unavailable');
          // This could indicate a timing issue - consider retrying
          if (attempt < maxRetries) {
            throw Exception('Player registered but unavailable - will retry');
          }
        } else {
          _logger.log('Player: Verified and available');
        }

        // Success - exit retry loop
        return;
      } catch (e) {
        _logger.log('Player: Registration attempt $attempt failed - $e');

        if (attempt >= maxRetries) {
          _logger.log('Player: All $maxRetries registration attempts failed');
          rethrow; // Final failure - propagate up
        }
        // Otherwise, continue to next retry
      }
    }
  }

  /// Unregister a builtin player
  Future<void> unregisterBuiltinPlayer(String playerId) async {
    try {
      _logger.log('🗑️ Unregistering builtin player: id=$playerId');
      await _sendCommand(
        'builtin_player/unregister',
        args: {
          'player_id': playerId,
        },
      );
      _logger.log('✅ Builtin player unregistered successfully');
    } catch (e) {
      _logger.log('❌ Error unregistering built-in player: $e');
      // Don't rethrow - cleanup should be non-fatal
    }
  }

  // NOTE: removePlayer, cleanupGhostPlayers, and repairCorruptPlayers have been removed.
  // These functions used MA APIs (config/players/save, config/players/remove) that don't
  // work reliably and actually CAUSED corrupt player entries in settings.json.
  // Ghost player cleanup must be done manually by editing settings.json while MA is stopped.
  // See PLAYER_LIFECYCLE_GUIDE.md for the correct procedure.

  /// Find an unavailable ghost player that matches the owner name pattern
  /// Used to "adopt" a previous installation's player ID instead of creating a new ghost
  /// Returns the player ID to adopt, or null if no match found
  Future<String?> findAdoptableGhostPlayer(String ownerName) async {
    try {
      _logger.log('Ghost adoption: Looking for existing player for "$ownerName"');

      final allPlayers = await getPlayers();

      // Build the expected player name pattern (e.g., "Chris' Phone" or "Chris's Phone")
      final expectedName1 = ownerName.endsWith('s')
          ? "$ownerName' Phone"
          : "$ownerName's Phone";
      final expectedName2 = "$ownerName's Phone"; // Always check this variant too

      _logger.log('Ghost adoption: Searching for "$expectedName1" or "$expectedName2"');

      // Find players that match the name pattern
      // Prioritize: 1) ensemble_ + unavailable, 2) ensemble_ + available, 3) other unavailable
      // Key insight: When app disconnects cleanly, player may still show as "available"
      // So we must also adopt available ensemble_ players to prevent ghost accumulation
      Player? matchedPlayer;
      int matchPriority = 0; // Higher = better match

      for (final player in allPlayers) {
        final nameMatch = player.name == expectedName1 ||
                         player.name == expectedName2 ||
                         player.name.toLowerCase() == expectedName1.toLowerCase() ||
                         player.name.toLowerCase() == expectedName2.toLowerCase();

        if (nameMatch) {
          final isEnsemblePlayer = player.playerId.startsWith('ensemble_');
          final isUnavailable = !player.available;

          // Priority scoring: ensemble prefix (2 points) + unavailable (1 point)
          final priority = (isEnsemblePlayer ? 2 : 0) + (isUnavailable ? 1 : 0);

          _logger.log('Ghost adoption: Found "${player.name}" (${player.playerId}) '
                     'available=${player.available} priority=$priority');

          if (priority > matchPriority) {
            matchedPlayer = player;
            matchPriority = priority;

            // Perfect match: ensemble_ and unavailable
            if (priority == 3) {
              break;
            }
          }
        }
      }

      if (matchedPlayer != null) {
        _logger.log('Ghost adoption: Will adopt "${matchedPlayer.name}"');

        // CRITICAL: Verify the player's config is not corrupted before adopting
        // Corrupted configs (missing player_id field) cause error 999 on playback
        final configValid = await _verifyPlayerConfig(matchedPlayer.playerId);
        if (!configValid) {
          _logger.log('Ghost adoption: Player config corrupted, skipping');
          return null;
        }

        return matchedPlayer.playerId;
      }

      _logger.log('Ghost adoption: No existing player found');
      return null;
    } catch (e) {
      _logger.log('Ghost adoption: Error - $e');
      return null;
    }
  }

  /// Verify a player's config is complete and not corrupted
  /// Returns true if config is valid, false if corrupted or missing required fields
  Future<bool> _verifyPlayerConfig(String playerId) async {
    try {
      _logger.log('🔍 Verifying player config for: $playerId');

      // Try to get player config - this will fail with error 999 if corrupted
      final response = await _sendCommand(
        'config/players/get',
        args: {'player_id': playerId},
      );

      final result = response['result'];
      if (result == null) {
        _logger.log('⚠️ Player config returned null');
        return false;
      }

      // Check for required fields that indicate a complete config
      final hasPlayerId = result['player_id'] != null;
      final hasProvider = result['provider'] != null;

      if (!hasPlayerId || !hasProvider) {
        _logger.log('⚠️ Player config missing required fields: player_id=$hasPlayerId, provider=$hasProvider');
        return false;
      }

      _logger.log('✅ Player config is valid');
      return true;
    } catch (e) {
      // Error 999 with "player_id missing" means corrupted config
      final errorStr = e.toString();
      if (errorStr.contains('999') || errorStr.contains('player_id') || errorStr.contains('missing')) {
        _logger.log('⚠️ Player config is corrupted: $e');
        return false;
      }
      // Other errors might just mean config doesn't exist yet (which is fine for new players)
      _logger.log('⚠️ Could not verify player config: $e');
      // For ghost adoption, if we can't verify, safer to skip
      return false;
    }
  }

  /// Send player state update to server
  /// Fixed: Server expects state as a dataclass object, not a string
  /// See: music_assistant_models.builtin_player.BuiltinPlayerState
  Future<void> updateBuiltinPlayerState(
    String playerId, {
    required bool powered,
    required bool playing,
    required bool paused,
    required int position,
    required int volume,
    required bool muted,
  }) async {
    // This command allows the local player to report its status back to MA
    // so the server UI updates correctly
    try {
      _logger.log('📊 Updating builtin player state: powered=$powered, playing=$playing, paused=$paused, position=$position, volume=$volume, muted=$muted');
      await _sendCommand(
        'builtin_player/update_state',
        args: {
          'player_id': playerId,
          'state': {
            'powered': powered,
            'playing': playing,
            'paused': paused,
            'position': position,
            'volume': volume,
            'muted': muted,
          },
        },
      );
    } catch (e) {
      _logger.log('❌ Error updating built-in player state: $e');
      // Do not rethrow, as state updates are frequent and should not block the app
    }
  }

  // ============================================================================
  // SENDSPIN PLAYER MANAGEMENT (MA 2.7.0b20+ replacement for builtin_player)
  // ============================================================================

  /// Stream of Sendspin player events
  Stream<Map<String, dynamic>> get sendspinPlayerEvents {
    if (!_eventStreams.containsKey('sendspin_player')) {
      _eventStreams['sendspin_player'] = StreamController<Map<String, dynamic>>.broadcast();
    }
    return _eventStreams['sendspin_player']!.stream;
  }

  // NOTE: The following Sendspin API methods were removed because they don't exist in MA:
  // - getSendspinConnectionInfo (sendspin/connection_info)
  // - sendspinOffer (sendspin/webrtc_offer)
  // - sendspinAnswer (sendspin/webrtc_answer)
  // - sendspinIceCandidate (sendspin/ice_candidate)
  //
  // Sendspin connection is handled directly via WebSocket to:
  // - Local: ws://{server-ip}:8927/sendspin
  // - External: wss://{server}/sendspin (via MA's proxy with auth)

  /// Update Sendspin player state
  /// Similar to updateBuiltinPlayerState but for Sendspin protocol
  Future<void> updateSendspinPlayerState(
    String playerId, {
    required bool powered,
    required bool playing,
    required bool paused,
    required int position,
    required int volume,
    required bool muted,
  }) async {
    try {
      _logger.log('Sendspin: Updating player state: powered=$powered, playing=$playing, paused=$paused');
      await _sendCommand(
        'sendspin/update_state',
        args: {
          'player_id': playerId,
          'state': {
            'powered': powered,
            'playing': playing,
            'paused': paused,
            'position': position,
            'volume': volume,
            'muted': muted,
          },
        },
      );
    } catch (e) {
      _logger.log('Sendspin: Error updating player state: $e');
      // Non-fatal, don't rethrow
    }
  }

  /// Disconnect Sendspin player from server
  Future<void> disconnectSendspinPlayer(String playerId) async {
    try {
      _logger.log('Sendspin: Disconnecting player $playerId');
      await _sendCommand(
        'sendspin/disconnect',
        args: {
          'player_id': playerId,
        },
      );
    } catch (e) {
      _logger.log('Sendspin: Error disconnecting player: $e');
      // Non-fatal during cleanup
    }
  }

  // ============================================================================
  // END SENDSPIN PLAYER MANAGEMENT
  // ============================================================================

  Future<void> _sendQueueCommand(String queueId, String command) async {
    try {
      final response = await _sendCommand(
        'player_queues/$command',
        args: {'queue_id': queueId},
      );
    } catch (e) {
      _logger.log('❌ Error sending queue command $command: $e');
      rethrow;
    }
  }

  // ============================================================================
  // END PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  // Get stream URL for a track
  String getStreamUrl(String provider, String itemId, {String? uri, List<ProviderMapping>? providerMappings}) {
    // Debug logging

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

      // Try to find the first available mapping
      final mapping = providerMappings.firstWhere(
        (m) => m.available,
        orElse: () => providerMappings.first,
      );

      actualProvider = mapping.providerInstance; // e.g., "opensubsonic--ETwFWrKe"
      actualItemId = mapping.itemId; // e.g., "HNF3R3sfsGVgelPM5hiolL"

    }
    // PRIORITY 2: Try to parse the URI if no provider mappings
    else if (uri != null && uri.isNotEmpty && !uri.startsWith('library://')) {
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
        }
      } catch (e) {
        _logger.log('⚠️ Error parsing stream URI "$uri": $e');
      }
    }

    // Music Assistant stream endpoint - use /preview endpoint
    // Format: /preview?item_id={itemId}&provider={provider}
    final streamUrl = '$baseUrl/preview?item_id=$actualItemId&provider=$actualProvider';
    return streamUrl;
  }

  // Get image URL
  String? getImageUrl(MediaItem item, {int size = 256}) {
    // Images are in metadata.images as an array
    final images = item.metadata?['images'] as List<dynamic>?;
    if (images == null || images.isEmpty) {
      return null;
    }

    // In remote mode (WebRTC bridge), HTTP requests don't work through the tunnel
    // So we need to use external CDN URLs directly when available
    if (_isRemoteMode) {
      return _getImageUrlForRemoteMode(images, size);
    }

    // Try to find a non-remotely accessible image first (prefer local/opensubsonic)
    Map<String, dynamic>? selectedImage;
    for (var img in images) {
      final imgMap = img as Map<String, dynamic>;
      final provider = imgMap['provider'] as String?;

      // Prefer opensubsonic images over spotify/remote
      if (provider != null && provider.startsWith('opensubsonic')) {
        selectedImage = imgMap;
        break;
      }
    }

    // If no opensubsonic image, use first image
    if (selectedImage == null) {
      selectedImage = images.first as Map<String, dynamic>;
    }

    final imagePath = selectedImage['path'] as String?;
    if (imagePath == null) return null;

    // ALWAYS use imageproxy endpoint to ensure images route through MA server
    // This fixes images not loading when connecting via external domain:
    // - Direct URLs may contain internal IPs not reachable from outside the network
    // - Streaming service URLs (Spotify, Tidal) may require auth or have CORS issues
    // - MA's imageproxy fetches the image server-side and serves it through your server

    // Build the imageproxy URL
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

    final provider = selectedImage['provider'] as String?;
    // Use the imageproxy endpoint
    return '$baseUrl/imageproxy?provider=${Uri.encodeComponent(provider ?? "")}&size=$size&fmt=jpeg&path=${Uri.encodeComponent(imagePath)}';
  }

  /// Get image URL for remote mode - uses external CDN URLs directly
  /// since HTTP requests don't work through the WebRTC bridge
  String? _getImageUrlForRemoteMode(List<dynamic> images, int size) {
    // Known external CDN domains that are publicly accessible
    const externalDomains = [
      'i.scdn.co',           // Spotify
      'mosaic.scdn.co',      // Spotify playlists
      'image-cdn-ak.spotifycdn.com',  // Spotify
      'cdns-images.dzcdn.net',  // Deezer
      'resources.tidal.com',    // Tidal
      'e-cdns-images.dzcdn.net',  // Deezer
      'is1-ssl.mzstatic.com',   // Apple Music
      'is2-ssl.mzstatic.com',   // Apple Music
      'is3-ssl.mzstatic.com',   // Apple Music
      'is4-ssl.mzstatic.com',   // Apple Music
      'is5-ssl.mzstatic.com',   // Apple Music
      'lastfm.freetls.fastly.net',  // Last.fm
      'coverartarchive.org',    // MusicBrainz
      'archive.org',            // Internet Archive
      'fanart.tv',              // Fanart.tv
    ];

    // First pass: look for images with paths that are external URLs
    for (var img in images) {
      final imgMap = img as Map<String, dynamic>;
      final path = imgMap['path'] as String?;
      if (path == null) continue;

      // Check if path is already an external URL
      if (path.startsWith('https://')) {
        try {
          final uri = Uri.parse(path);
          // Check if it's from a known CDN
          for (final domain in externalDomains) {
            if (uri.host.contains(domain)) {
              _logger.log('🖼️ Remote mode: using external CDN URL from ${uri.host}');
              // For Spotify, we can request different sizes
              if (uri.host.contains('scdn.co') || uri.host.contains('spotifycdn.com')) {
                // Spotify image URLs can have size in path, but we'll use as-is
                return path;
              }
              return path;
            }
          }
          // Even if not a known CDN, if it's HTTPS it might work
          _logger.log('🖼️ Remote mode: trying external URL from ${uri.host}');
          return path;
        } catch (e) {
          // Not a valid URL, continue
        }
      }
    }

    // Second pass: try any image with a provider that typically has external URLs
    for (var img in images) {
      final imgMap = img as Map<String, dynamic>;
      final provider = imgMap['provider'] as String?;
      final path = imgMap['path'] as String?;
      if (path == null) continue;

      // Providers that typically have external URLs in their paths
      if (provider != null) {
        if (provider.contains('spotify') ||
            provider.contains('tidal') ||
            provider.contains('deezer') ||
            provider.contains('apple_music') ||
            provider.contains('musicbrainz')) {
          if (path.startsWith('https://')) {
            _logger.log('🖼️ Remote mode: using $provider image URL');
            return path;
          }
        }
      }
    }

    // No external URLs found - images won't load in remote mode for local files
    _logger.log('🖼️ Remote mode: no external image URL available');
    return null;
  }

  // ==================== iTunes Artwork Lookup ====================

  /// Search iTunes for a podcast and return high-res artwork URL
  /// Returns null if not found or on error
  Future<String?> getITunesPodcastArtwork(String podcastName) async {
    try {
      final searchTerm = Uri.encodeComponent(podcastName);
      final url = 'https://itunes.apple.com/search?term=$searchTerm&entity=podcast&limit=1';

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        _logger.log('🎨 iTunes search failed for "$podcastName": ${response.statusCode}');
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final results = json['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        _logger.log('🎨 No iTunes results for "$podcastName"');
        return null;
      }

      final podcast = results.first as Map<String, dynamic>;
      var artworkUrl = podcast['artworkUrl600'] as String?;

      if (artworkUrl == null) {
        artworkUrl = podcast['artworkUrl100'] as String?;
      }

      if (artworkUrl != null) {
        // Use 800x800 - good quality without being excessive (was 1400x1400)
        artworkUrl = artworkUrl
            .replaceAll('600x600', '800x800')
            .replaceAll('100x100', '800x800');
        _logger.log('🎨 Found iTunes artwork for "$podcastName": $artworkUrl');
      }

      return artworkUrl;
    } catch (e) {
      _logger.log('🎨 iTunes lookup error for "$podcastName": $e');
      return null;
    }
  }

  // ==================== Authentication Methods ====================

  /// Authenticate the WebSocket session with a token
  /// Call this after connect() if authRequired is true
  Future<bool> authenticateWithToken(String token) async {
    // Allow auth when connected or authenticating (in case of retry)
    final allowedStates = [
      MAConnectionState.connected,
      MAConnectionState.authenticating,
    ];
    if (!allowedStates.contains(_currentState)) {
      _logger.log('Cannot authenticate - state is $_currentState');
      return false;
    }

    try {
      _logger.log('🔐 Authenticating WebSocket with token...');
      _updateConnectionState(MAConnectionState.authenticating);

      final response = await _sendCommand('auth', args: {'token': token});

      // Check for success
      if (response.containsKey('error_code')) {
        _logger.log('❌ Authentication failed: ${response['error_code']} - ${response['details']}');
        _isAuthenticated = false;
        _updateConnectionState(MAConnectionState.connected);
        return false;
      }

      _logger.log('✅ WebSocket authenticated successfully');
      _isAuthenticated = true;
      _updateConnectionState(MAConnectionState.authenticated);
      return true;
    } catch (e) {
      _logger.log('❌ Authentication error: $e');
      _isAuthenticated = false;
      _updateConnectionState(MAConnectionState.connected);
      return false;
    }
  }

  /// Login with username/password over WebSocket and authenticate
  /// Returns the access token on success, null on failure
  Future<String?> loginWithCredentials(String username, String password) async {
    if (_currentState != MAConnectionState.connected) {
      _logger.log('Cannot login - not connected');
      return null;
    }

    try {
      _logger.log('🔐 Logging in with credentials...');
      _updateConnectionState(MAConnectionState.authenticating);

      // Step 1: Login to get access token
      final loginResponse = await _sendCommand('auth/login', args: {
        'username': username,
        'password': password,
      });

      if (loginResponse.containsKey('error_code')) {
        _logger.log('❌ Login failed: ${loginResponse['error_code']} - ${loginResponse['details']}');
        _updateConnectionState(MAConnectionState.connected);
        return null;
      }

      final result = loginResponse['result'] as Map<String, dynamic>?;
      final accessToken = result?['access_token'] as String?;

      if (accessToken == null) {
        _logger.log('❌ No access token in login response');
        _updateConnectionState(MAConnectionState.connected);
        return null;
      }

      _logger.log('✓ Got access token, authenticating session...');

      // Step 2: Authenticate the WebSocket with the token
      final authResponse = await _sendCommand('auth', args: {'token': accessToken});

      if (authResponse.containsKey('error_code')) {
        _logger.log('❌ Session auth failed: ${authResponse['error_code']}');
        _updateConnectionState(MAConnectionState.connected);
        return null;
      }

      _logger.log('✅ Login and authentication successful');
      _isAuthenticated = true;
      _updateConnectionState(MAConnectionState.authenticated);

      return accessToken;
    } catch (e) {
      _logger.log('❌ Login error: $e');
      _updateConnectionState(MAConnectionState.connected);
      return null;
    }
  }

  /// Fetch initial state after authentication
  /// This populates providers and players that are needed for operation
  /// Must be called after authentication succeeds
  /// This matches the MA frontend's fetchState() behavior
  Future<void> fetchState() async {
    if (_authRequired && !_isAuthenticated) {
      _logger.log('Cannot fetch state - not authenticated');
      return;
    }

    try {
      _logger.log('📥 Fetching initial state...');

      // Fetch provider manifests (available providers with icons)
      try {
        final manifestResponse = await _sendCommand('providers/manifests');
        final manifests = manifestResponse['result'];
        if (manifests is List) {
          _providerManifests.clear();
          for (final manifestData in manifests) {
            if (manifestData is Map<String, dynamic>) {
              final manifest = ProviderManifest.fromJson(manifestData);
              if (manifest.domain.isNotEmpty) {
                _providerManifests[manifest.domain] = manifest;
              }
            }
          }
          _logger.log('✓ Provider manifests loaded: ${_providerManifests.length} providers with ${_providerManifests.values.where((m) => m.hasSvgIcon).length} icons');
        }
      } catch (e) {
        _logger.log('⚠️ Could not load provider manifests: $e');
      }

      _logger.log('✅ Initial state fetch complete');
    } catch (e) {
      _logger.log('❌ Error fetching state: $e');
      // Don't throw - this should be non-fatal
    }
  }

  /// Get all music provider instances configured in Music Assistant
  /// Returns only music providers (spotify, tidal, filesystem, etc.) not player/metadata providers
  Future<List<ProviderInstance>> getMusicProviders() async {
    try {
      final response = await _sendCommand('providers');

      final result = response['result'];
      if (result == null) {
        _logger.log('⚠️ providers command returned no result');
        return [];
      }

      final List<dynamic> providers = result is List ? result : [];
      final musicProviders = <ProviderInstance>[];

      for (final providerData in providers) {
        if (providerData is Map<String, dynamic>) {
          final instance = ProviderInstance.fromJson(providerData);
          // Only include music providers (not player providers, metadata providers, etc.)
          if (instance.isMusicProvider) {
            musicProviders.add(instance);
          }
        }
      }

      _logger.log('🎵 Found ${musicProviders.length} music providers: ${musicProviders.map((p) => p.name).join(", ")}');
      return musicProviders;
    } catch (e) {
      _logger.log('❌ Error getting music providers: $e');
      return [];
    }
  }

  /// Get provider manifest by domain
  ProviderManifest? getProviderManifest(String domain) {
    return _providerManifests[domain];
  }

  /// Get SVG icon for a provider domain
  /// Returns null if no icon is available
  String? getProviderIconSvg(String domain, {bool isDark = false}) {
    final manifest = _providerManifests[domain];
    return manifest?.getSvgIcon(isDark: isDark);
  }

  /// Get current authenticated user's profile
  /// Returns user info including display_name, username, groups, etc.
  Future<Map<String, dynamic>?> getCurrentUserInfo() async {
    if (_authRequired && !_isAuthenticated) {
      _logger.log('Cannot get user info - not authenticated');
      return null;
    }

    try {
      final response = await _sendCommand('auth/me');
      _logger.log('🔍 auth/me raw response keys: ${response.keys.toList()}');

      // Handle both wrapped (result) and unwrapped responses
      Map<String, dynamic>? userInfo;
      if (response.containsKey('result')) {
        userInfo = response['result'] as Map<String, dynamic>?;
      } else if (response.containsKey('username') || response.containsKey('user_id')) {
        // Response is the user object directly
        userInfo = response;
      }

      if (userInfo != null) {
        _logger.log('✓ Got user info: username=${userInfo['username']}, display_name=${userInfo['display_name']}');
      } else {
        _logger.log('⚠️ auth/me returned no user info. Response: $response');
      }

      return userInfo;
    } catch (e) {
      _logger.log('Error getting current user info: $e');
      return null;
    }
  }

  /// Create a long-lived token for persistent authentication
  /// Must be authenticated first
  Future<String?> createLongLivedToken({String name = 'Ensemble Mobile App'}) async {
    if (!_isAuthenticated) {
      _logger.log('Cannot create token - not authenticated');
      return null;
    }

    try {
      _logger.log('Creating long-lived token...');

      final response = await _sendCommand('auth/create_token', args: {
        'name': name,
      });

      if (response.containsKey('error_code')) {
        _logger.log('⚠️ Could not create long-lived token: ${response['error_code']}');
        return null;
      }

      final result = response['result'] as Map<String, dynamic>?;
      final token = result?['token'] as String?;

      if (token != null) {
        _logger.log('✅ Created long-lived token');
      }

      return token;
    } catch (e) {
      _logger.log('⚠️ Token creation error: $e');
      return null;
    }
  }

  // ==================== Connection State ====================

  void _updateConnectionState(MAConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);
  }

  /// Start heartbeat timer to keep WebSocket connection alive
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(Timings.heartbeatInterval, (_) {
      _sendHeartbeat();
    });
  }

  /// Stop heartbeat timer
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Send a ping message to keep the connection alive
  Future<void> _sendHeartbeat() async {
    if (_currentState != MAConnectionState.connected &&
        _currentState != MAConnectionState.authenticated) {
      return;
    }

    try {
      // Send a lightweight command to check connection is alive
      // Using 'info' as it's a valid MA command
      await _sendCommand('info').timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _logger.log('Heartbeat timeout - connection may be stale');
          return <String, dynamic>{};
        },
      );
    } catch (e) {
      _logger.log('Heartbeat failed: $e');
      // Connection may be dead, trigger reconnect
      _updateConnectionState(MAConnectionState.error);
      _reconnect();
    }
  }

  Future<void> _reconnect() async {
    // Don't reconnect if disposed
    if (_isDisposed) {
      _logger.log('Reconnect: API disposed, skipping');
      return;
    }

    // Don't reconnect if already connected or connecting
    if (_currentState == MAConnectionState.connected ||
        _currentState == MAConnectionState.authenticated ||
        _currentState == MAConnectionState.connecting) {
      _logger.log('Reconnect: Already connected/connecting, skipping');
      return;
    }

    // Don't reconnect if another connection is in progress
    if (_connectionInProgress != null && !_connectionInProgress!.isCompleted) {
      _logger.log('Reconnect: Connection already in progress, skipping');
      return;
    }

    // Cancel all pending requests before reconnecting to prevent memory leaks
    _cancelPendingRequests('Connection lost, reconnecting');

    await Future.delayed(Timings.reconnectDelay);

    // Check again after delay
    if (_isDisposed ||
        _currentState == MAConnectionState.connected ||
        _currentState == MAConnectionState.authenticated) {
      return;
    }

    try {
      await connect();
    } catch (e) {
      _logger.log('Reconnection failed: $e');
    }
  }

  Future<void> disconnect() async {
    _stopHeartbeat();
    _updateConnectionState(MAConnectionState.disconnected);
    await _channel?.sink.close();
    _channel = null;
    // Complete all pending requests with an error before clearing
    _cancelPendingRequests('Connection disconnected');
  }

  /// Cancel all pending requests with an error message
  void _cancelPendingRequests(String reason) {
    for (final entry in _pendingRequests.entries) {
      if (!entry.value.completer.isCompleted) {
        entry.value.completer.completeError(Exception(reason));
      }
    }
    _pendingRequests.clear();
  }

  void dispose() {
    _isDisposed = true;
    _stopHeartbeat();
    // Complete any pending connection to prevent hanging futures
    if (_connectionInProgress != null && !_connectionInProgress!.isCompleted) {
      _connectionInProgress!.completeError(Exception('API disposed'));
    }
    _connectionInProgress = null;
    disconnect();
    _connectionStateController.close();
    for (final stream in _eventStreams.values) {
      stream.close();
    }
    _eventStreams.clear();
  }
}
