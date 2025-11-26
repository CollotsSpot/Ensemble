import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:uuid/uuid.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import 'debug_logger.dart';
import 'settings_service.dart';
import 'retry_helper.dart';

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

      // Get or generate a persistent client ID to prevent ghost players
      var clientId = await SettingsService.getBuiltinPlayerId();
      if (clientId == null) {
        clientId = _uuid.v4();
        await SettingsService.setBuiltinPlayerId(clientId);
        _logger.log('Generated and saved new client ID: $clientId');
      } else {
        _logger.log('Using existing client ID: $clientId');
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
          // For WS (unsecure WebSocket), add Music Assistant default port 8095
          finalUri = Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: 8095,
            path: '/ws',
            queryParameters: {'client_id': clientId},
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
            queryParameters: {'client_id': clientId},
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
    bool albumArtistsOnly = true,
  }) async {
    try {
      _logger.log('Fetching artists with limit=$limit, offset=$offset, search=$search, albumArtistsOnly=$albumArtistsOnly');
      final response = await _sendCommand(
        'music/artists/library_items',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite': favoriteOnly,
          'album_artists_only': albumArtistsOnly,
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

  Future<List<Artist>> getRandomArtists({int limit = 10, bool albumArtistsOnly = true}) async {
    try {
      _logger.log('Fetching random artists (limit=$limit, albumArtistsOnly=$albumArtistsOnly)');
      final response = await _sendCommand(
        'music/artists/library_items',
        args: {
          'limit': limit,
          'order_by': 'random',
          'album_artists_only': albumArtistsOnly,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      _logger.log('Got ${items.length} random artists');
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
  }) async {
    try {
      _logger.log('Fetching albums with limit=$limit, offset=$offset, artistId=$artistId');
      final args = <String, dynamic>{
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (search != null) 'search': search,
        if (favoriteOnly != null) 'favorite': favoriteOnly,
        if (artistId != null) 'artist_id': artistId,
      };
      _logger.log('Albums API args: $args');

      final response = await _sendCommand(
        'music/albums/library_items',
        args: args,
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

  /// Get recently played albums
  /// Gets recently played tracks, then extracts unique albums from them
  Future<List<Album>> getRecentAlbums({int limit = 10}) async {
    try {
      _logger.log('Fetching recently played albums (limit=$limit)');

      // Get recently played tracks - this API works and returns data
      final response = await _sendCommand(
        'music/recently_played_items',
        args: {
          'limit': limit * 5, // Get more tracks to ensure enough unique albums
          'media_types': ['track'],
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null || items.isEmpty) {
        _logger.log('⚠️ No recently played tracks returned');
        return [];
      }

      _logger.log('📀 Got ${items.length} recently played tracks');

      // Debug: Log first track to see structure
      if (items.isNotEmpty) {
        final firstTrack = items[0] as Map<String, dynamic>;
        _logger.log('🔍 DEBUG: First track keys: ${firstTrack.keys.toList()}');
        _logger.log('🔍 DEBUG: Track name: ${firstTrack['name']}');

        // Check different possible album field names
        if (firstTrack.containsKey('album')) {
          _logger.log('🔍 DEBUG: Has "album" field, type: ${firstTrack['album'].runtimeType}');
          if (firstTrack['album'] is Map) {
            _logger.log('🔍 DEBUG: Album keys: ${(firstTrack['album'] as Map).keys.toList()}');
          }
        }
        if (firstTrack.containsKey('album_id')) {
          _logger.log('🔍 DEBUG: Has "album_id": ${firstTrack['album_id']}');
        }
        if (firstTrack.containsKey('albums')) {
          _logger.log('🔍 DEBUG: Has "albums" field');
        }
      }

      // Try to extract albums from tracks
      final seenAlbumIds = <String>{};
      final albums = <Album>[];

      for (final item in items) {
        try {
          final trackMap = item as Map<String, dynamic>;

          // Try different ways to get album data
          Map<String, dynamic>? albumData;

          // Method 1: Direct 'album' object
          if (trackMap['album'] is Map<String, dynamic>) {
            albumData = trackMap['album'] as Map<String, dynamic>;
          }
          // Method 2: album_id reference - need to fetch album
          else if (trackMap['album_id'] != null) {
            _logger.log('⚠️ Track has album_id but no album object - need to implement album fetch');
            continue;
          }

          if (albumData != null) {
            final albumId = albumData['item_id']?.toString() ?? albumData['uri']?.toString();
            if (albumId != null && !seenAlbumIds.contains(albumId)) {
              seenAlbumIds.add(albumId);
              albums.add(Album.fromJson(albumData));

              if (albums.length >= limit) break;
            }
          }
        } catch (e) {
          _logger.log('   ⚠️ Error processing track: $e');
        }
      }

      _logger.log('✅ Extracted ${albums.length} unique albums from ${items.length} tracks');

      if (albums.isNotEmpty) {
        _logger.log('   First album: ${albums[0].name} by ${albums[0].artistsString}');
      } else {
        _logger.log('   ⚠️ No albums could be extracted - check debug logs above');
      }

      return albums;
    } catch (e) {
      _logger.log('❌ Error getting recent albums: $e');
      return [];
    }
  }

  /// Get random albums
  Future<List<Album>> getRandomAlbums({int limit = 10}) async {
    try {
      _logger.log('Fetching random albums (limit=$limit)');
      final response = await _sendCommand(
        'music/albums/library_items',
        args: {
          'limit': limit,
          'order_by': 'random',
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      _logger.log('Got ${items.length} random albums');
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
      _logger.log('Fetching library statistics');

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
    return await RetryHelper.retryNetwork(
      operation: () async {
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
            return <Track>[];
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
  }) async {
    try {
      _logger.log('Fetching playlists with limit=$limit, offset=$offset');
      final response = await _sendCommand(
        'music/playlists/library_items',
        args: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
          if (search != null) 'search': search,
          if (favoriteOnly != null) 'favorite': favoriteOnly,
        },
      );

      final items = response['result'] as List<dynamic>?;
      if (items == null) return [];

      _logger.log('Got ${items.length} playlists');
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
          'provider': provider,
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
          _logger.log('Fetching playlist tracks for provider=$provider, itemId=$itemId');
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

          _logger.log('Got ${items.length} playlist tracks');
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
  /// Toggle favorite status for any media item
  Future<bool> toggleFavorite(String mediaType, String itemId, String provider) async {
    try {
      _logger.log('Toggling favorite for $mediaType: $itemId');
      final response = await _sendCommand(
        'music/favorites/toggle',
        args: {
          'media_type': mediaType,
          'item_id': itemId,
          'provider': provider,
        },
      );

      final isFavorite = response['result'] as bool? ?? false;
      _logger.log('Favorite toggled: $isFavorite');
      return isFavorite;
    } catch (e) {
      _logger.log('Error toggling favorite: $e');
      return false;
    }
  }

  /// Mark item as favorite
  Future<void> addToFavorites(String mediaType, String itemId, String provider) async {
    try {
      _logger.log('Adding to favorites: $mediaType/$itemId');
      await _sendCommand(
        'music/favorites/add',
        args: {
          'media_type': mediaType,
          'item_id': itemId,
          'provider': provider,
        },
      );
      _logger.log('Added to favorites');
    } catch (e) {
      _logger.log('Error adding to favorites: $e');
      rethrow;
    }
  }

  /// Remove item from favorites
  Future<void> removeFromFavorites(String mediaType, String itemId, String provider) async {
    try {
      _logger.log('Removing from favorites: $mediaType/$itemId');
      await _sendCommand(
        'music/favorites/remove',
        args: {
          'media_type': mediaType,
          'item_id': itemId,
          'provider': provider,
        },
      );
      _logger.log('Removed from favorites');
    } catch (e) {
      _logger.log('Error removing from favorites: $e');
      rethrow;
    }
  }

  // Search
  /// Search across all providers (Spotify, etc.) and library
  /// Set libraryOnly to true to search only local library
  Future<Map<String, List<MediaItem>>> search(String query, {bool libraryOnly = false}) async {
    return await RetryHelper.retryNetwork(
      operation: () async {
        try {
          _logger.log('Searching for: $query (libraryOnly: $libraryOnly)');

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
            _logger.log('No search results returned');
            return <String, List<MediaItem>>{'artists': [], 'albums': [], 'tracks': []};
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

          _logger.log('Search results: ${artists.length} artists, ${albums.length} albums, ${tracks.length} tracks');

          return <String, List<MediaItem>>{
            'artists': artists,
            'albums': albums,
            'tracks': tracks,
          };
        } catch (e) {
          _logger.log('Error searching: $e');
          return <String, List<MediaItem>>{'artists': [], 'albums': [], 'tracks': []};
        }
      },
    ).catchError((e) {
      _logger.log('Error searching after retries: $e');
      return <String, List<MediaItem>>{'artists': [], 'albums': [], 'tracks': []};
    });
  }

  // ============================================================================
  // PLAYER AND QUEUE MANAGEMENT (Queue-based streaming for full track playback)
  // ============================================================================

  /// Get all available players
  Future<List<Player>> getPlayers() async {
    return await RetryHelper.retryNetwork(
      operation: () async {
        _logger.log('Fetching available players...');
        final response = await _sendCommand('players/all');

        final items = response['result'] as List<dynamic>?;
        if (items == null) return <Player>[];

        // Debug: Log raw player data for the first playing player
        for (var item in items) {
          if (item['state'] == 'playing') {
            _logger.log('🔍 RAW PLAYER DATA: ${item.toString()}');
            break;
          }
        }

        final players = items
            .map((item) => Player.fromJson(item as Map<String, dynamic>))
            .toList();

        _logger.log('Got ${players.length} players');
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
          _logger.log('Fetching queue for player: $playerId');

          // Try to get full queue object first
          // First, get the queue metadata which includes current_index, shuffle, repeat, etc
          int? currentIndex;
          bool? shuffleEnabled;
          String? repeatMode;

          try {
            _logger.log('🎯 Calling player_queues/get with queue_id: $playerId');
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

              final currentItemData = queueResult['current_item'] as Map<String, dynamic>?;
              final currentItemName = currentItemData?['name'] as String?;
              final totalItems = queueResult['items'] as int?;

              _logger.log('✅ Queue metadata from player_queues/get:');
              _logger.log('   - queue_id: ${queueResult['queue_id']}');
              _logger.log('   - Total items in queue: $totalItems');
              _logger.log('   - Current index: $currentIndex');
              _logger.log('   - Current item: $currentItemName');
              _logger.log('   - Shuffle: $shuffleEnabled, Repeat: $repeatMode');
            }
          } catch (e) {
            _logger.log('⚠️ player_queues/get not available: $e');
          }

          // Now get the queue items
          _logger.log('🎯 Calling player_queues/items with queue_id: $playerId');
          final response = await _sendCommand(
            'player_queues/items',
            args: {'queue_id': playerId},
          );

          final result = response['result'];
          if (result == null) {
            _logger.log('❌ player_queues/items returned null result');
            return null;
          }

          _logger.log('📦 player_queues/items returned ${result is List ? result.length : '?'} items');

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

          _logger.log('🎵 Parsed queue: ${items.length} items, currentIndex: $currentIndex');

          // Log items around the current index
          if (currentIndex != null && currentIndex >= 0 && currentIndex < items.length) {
            _logger.log('📋 Queue items around current index ($currentIndex):');
            final start = (currentIndex - 2).clamp(0, items.length - 1);
            final end = (currentIndex + 3).clamp(0, items.length);
            for (var i = start; i < end; i++) {
              final marker = i == currentIndex ? '>>> ' : '    ';
              _logger.log('$marker[$i] ${items[i].track.name} - ${items[i].track.artistsString}');
            }
            _logger.log('✅ Current track at index $currentIndex: ${items[currentIndex].track.name}');
          } else if (currentIndex != null) {
            _logger.log('⚠️ Current index $currentIndex is out of range (0-${items.length - 1})');
            _logger.log('📋 First 5 items in returned queue:');
            for (var i = 0; i < items.length && i < 5; i++) {
              _logger.log('  [$i] ${items[i].track.name} - ${items[i].track.artistsString}');
            }
            currentIndex = null;
          } else {
            _logger.log('⚠️ No currentIndex provided');
            _logger.log('📋 First 5 items in returned queue:');
            for (var i = 0; i < items.length && i < 5; i++) {
              _logger.log('  [$i] ${items[i].track.name} - ${items[i].track.artistsString}');
            }
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
      _logger.log('Playing track via queue: $uri on player $playerId (option: $option)');

      await _sendCommand(
        'player_queues/play_media',
        args: {
          'queue_id': playerId,
          'media': [uri], // Array of URI strings, not objects
          'option': option, // 'replace' clears queue, 'play' adds to queue
        },
      );

      _logger.log('✓ Track queued successfully');
    } catch (e) {
      _logger.log('Error playing track: $e');
      rethrow;
    }
  }

  /// Play multiple tracks via queue
  /// If clearQueue is true, replaces the queue (default behavior)
  /// If startIndex is provided, only tracks from that index onwards will be queued
  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex, bool clearQueue = true}) async {
    return await RetryHelper.retryCritical(
      operation: () async {
        // If startIndex is provided, slice the tracks list to start from that index
        // This is a workaround since Music Assistant ignores the start_item parameter
        final tracksToPlay = startIndex != null && startIndex > 0
            ? tracks.sublist(startIndex)
            : tracks;

        // Build array of URI strings (not objects!)
        final mediaUris = tracksToPlay.map((track) => _buildTrackUri(track)).toList();

        final option = clearQueue ? 'replace' : 'play';
        _logger.log('Playing ${tracksToPlay.length} tracks via queue on player $playerId (option: $option, startIndex: $startIndex, sliced: ${startIndex != null && startIndex > 0})');

        final args = {
          'queue_id': playerId,
          'media': mediaUris, // Array of URI strings
          'option': option, // 'replace' clears queue, 'play' adds to queue
        };

        _logger.log('📤 Sending play_media command with args: $args');

        await _sendCommand(
          'player_queues/play_media',
          args: args,
        );

        _logger.log('✓ ${tracksToPlay.length} tracks queued successfully');
      },
    );
  }

  /// Play radio based on a track (generates similar tracks)
  Future<void> playRadio(String playerId, Track track) async {
    return await RetryHelper.retryCritical(
      operation: () async {
        // Try using library URI if available, otherwise use provider URI
        final libraryUri = track.uri;
        final trackUri = libraryUri ?? _buildTrackUri(track);
        _logger.log('Playing radio based on track: $trackUri (library URI: $libraryUri) on player $playerId');

        final args = {
          'queue_id': playerId,
          'media': [trackUri],
          'option': 'replace',
          'radio_mode': true, // Enable radio mode for similar tracks
        };

        _logger.log('📤 Sending play_media command (RADIO MODE) with args: $args');
        _logger.log('   Track details: provider=${track.provider}, itemId=${track.itemId}');
        _logger.log('   Available providers: ${track.providerMappings?.map((m) => '${m.providerDomain}:${m.available}').join(', ')}');

        await _sendCommand(
          'player_queues/play_media',
          args: args,
        );

        _logger.log('✓ Radio mode command sent successfully');
      },
    );
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
  Future<void> setPower(String playerId, bool powered) async {
    await _sendCommand(
      'players/cmd/power',
      args: {
        'player_id': playerId,
        'powered': powered,
      },
    );
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
      _logger.log('Setting volume to $volumeLevel for player $playerId');
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
      _logger.log('${muted ? "Muting" : "Unmuting"} player $playerId');
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

  /// Toggle shuffle mode for queue
  Future<void> toggleShuffle(String queueId) async {
    try {
      _logger.log('Toggling shuffle for queue $queueId');
      await _sendCommand(
        'player_queues/shuffle',
        args: {'queue_id': queueId},
      );
    } catch (e) {
      _logger.log('Error toggling shuffle: $e');
      rethrow;
    }
  }

  /// Set repeat mode for queue: 'off', 'one', 'all'
  Future<void> setRepeatMode(String queueId, String mode) async {
    try {
      _logger.log('Setting repeat mode to $mode for queue $queueId');
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
      _logger.log('Seeking to $position seconds for queue $queueId');
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

  Future<void> _sendQueueCommand(String queueId, String command) async {
    try {
      _logger.log('🎮 Sending queue command: $command to queue $queueId');
      final response = await _sendCommand(
        'player_queues/$command',
        args: {'queue_id': queueId},
      );
      _logger.log('✅ Queue command $command completed successfully');
      _logger.log('   Response: ${response.toString()}');
    } catch (e) {
      _logger.log('❌ Error sending queue command $command: $e');
      _logger.log('   Stack trace: ${StackTrace.current}');
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
    // Images are in metadata.images as an array
    final images = item.metadata?['images'] as List<dynamic>?;
    if (images == null || images.isEmpty) {
      _logger.log('⚠️ No images found for ${item.name}');
      return null;
    }

    _logger.log('🖼️ Found ${images.length} images for ${item.name}');

    // Try to find a non-remotely accessible image first (prefer local/opensubsonic)
    Map<String, dynamic>? selectedImage;
    for (var img in images) {
      final imgMap = img as Map<String, dynamic>;
      final provider = imgMap['provider'] as String?;

      // Prefer opensubsonic images over spotify/remote
      if (provider != null && provider.startsWith('opensubsonic')) {
        selectedImage = imgMap;
        _logger.log('✅ Selected opensubsonic image: ${imgMap['path']}');
        break;
      }
    }

    // If no opensubsonic image, use first image
    if (selectedImage == null) {
      selectedImage = images.first as Map<String, dynamic>;
      _logger.log('ℹ️ Using first image: ${selectedImage['path']} (provider: ${selectedImage['provider']})');
    }

    final imagePath = selectedImage['path'] as String?;
    if (imagePath == null) return null;

    // If path is already a full URL, use it directly
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      _logger.log('🔗 Using direct URL: $imagePath');
      return imagePath;
    }

    // Otherwise, use the imageproxy endpoint
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
