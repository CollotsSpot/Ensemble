import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import '../models/media_item.dart';
import 'debug_logger.dart';

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

  MusicAssistantAPI(this.serverUrl);

  Future<void> connect() async {
    if (_currentState == MAConnectionState.connected ||
        _currentState == MAConnectionState.connecting) {
      return;
    }

    try {
      _updateConnectionState(MAConnectionState.connecting);

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

      // Add port if not present
      final uri = Uri.parse(wsUrl);
      if (uri.hasPort) {
        // Port is already specified, keep it
        _logger.log('Using specified port: ${uri.port}');
      } else {
        // No port specified, use defaults based on protocol
        if (useSecure) {
          // For WSS (secure WebSocket), default to standard HTTPS port 443
          wsUrl = '${uri.scheme}://${uri.host}:443${uri.path}';
          _logger.log('No port specified, defaulting to 443 for secure connection');
        } else {
          // For WS (unsecure WebSocket), default to Music Assistant default 8095
          wsUrl = '${uri.scheme}://${uri.host}:8095${uri.path}';
          _logger.log('No port specified, defaulting to 8095 for unsecure connection');
        }
      }

      // Add /ws path for WebSocket endpoint
      if (!wsUrl.endsWith('/ws')) {
        wsUrl = '$wsUrl/ws';
      }

      _logger.log('Attempting ${useSecure ? "secure (WSS)" : "unsecure (WS)"} connection');
      _logger.log('Final WebSocket URL: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

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

  // Get stream URL for a track
  String getStreamUrl(String provider, String itemId) {
    var baseUrl = serverUrl;
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'http://$baseUrl';
    }
    if (!baseUrl.contains(':8095')) {
      final uri = Uri.parse(baseUrl);
      baseUrl = '${uri.scheme}://${uri.host}:8095';
    }
    return '$baseUrl/api/stream/$provider/$itemId';
  }

  // Get image URL
  String? getImageUrl(MediaItem item, {int size = 256}) {
    final imageUrl = item.metadata?['image'];
    if (imageUrl == null) return null;

    var baseUrl = serverUrl;
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'http://$baseUrl';
    }
    if (!baseUrl.contains(':8095')) {
      final uri = Uri.parse(baseUrl);
      baseUrl = '${uri.scheme}://${uri.host}:8095';
    }

    return '$baseUrl/api/image/$size/${Uri.encodeComponent(imageUrl)}';
  }

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
