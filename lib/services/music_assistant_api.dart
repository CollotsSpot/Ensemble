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
import 'debug_logger.dart';
import 'settings_service.dart';
import 'device_id_service.dart';
import 'retry_helper.dart';
import 'auth/auth_manager.dart';

enum MAConnectionState {
  disconnected,
  connecting,
  connected,
  error,
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

  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  final Map<String, StreamController<Map<String, dynamic>>> _eventStreams = {};

  Completer<void>? _connectionCompleter;

  // Cached custom port setting
  int? _cachedCustomPort;

  MusicAssistantAPI(this.serverUrl, this.authManager);

  // Guard to prevent multiple simultaneous connection attempts
  Completer<void>? _connectionInProgress;

  Future<void> connect() async {
    // If already connected, nothing to do
    if (_currentState == MAConnectionState.connected) {
      return;
    }

    // If connection is in progress, wait for it instead of starting another
    if (_connectionInProgress != null) {
      _logger.log('Connection already in progress, waiting...');
      return _connectionInProgress!.future;
    }

    _connectionInProgress = Completer<void>();

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
        _logger.log('🔑 Adding auth headers to WebSocket handshake: ${headers.keys.join(', ')}');
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
        Timings.connectionTimeout,
        onTimeout: () {
          throw Exception('Connection timeout - no server info received');
        },
      );

      _logger.log('Connected to Music Assistant successfully');
      _connectionInProgress?.complete();
      _connectionInProgress = null;
    } catch (e) {
      _logger.log('Connection error: $e');
      _updateConnectionState(MAConnectionState.error);
      _connectionInProgress?.completeError(e);
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

        // Get the object_id (player_id for player events)
        final objectId = data['object_id'] as String?;
        final eventData = data['data'] as Map<String, dynamic>? ?? {};

        // Debug: Log full data for player events
        if (eventType == 'player_added' || eventType == 'player_updated' || eventType == 'builtin_player') {
           _logger.log('Event data: ${jsonEncode(eventData)} (player_id: $objectId)');
        }

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

  // Library browsing methods
  Future<List<Artist>> getArtists({
    int? limit,
    int? offset,
    String? search,
    bool? favoriteOnly,
    bool albumArtistsOnly = true,
  }) async {
    try {
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

      final items = response['result'] as List<dynamic>?;
      if (items == null) {
        return [];
      }
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
      final args = <String, dynamic>{
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (search != null) 'search': search,
        if (favoriteOnly != null) 'favorite': favoriteOnly,
        if (artistId != null) 'artist_id': artistId,
      };

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


      return items
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.log('Error getting tracks: $e');
      return [];
    }
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
      if (items == null || items.isEmpty) {
        _logger.log('⚠️ No recently played tracks found');
        return [];
      }

      // Collect track URIs for batch lookup
      final trackUris = <String>[];
      for (final item in items) {
        final trackUri = (item as Map<String, dynamic>)['uri'] as String?;
        if (trackUri != null) {
          trackUris.add(trackUri);
        }
      }

      if (trackUris.isEmpty) {
        return [];
      }

      // Batch fetch track details using parallel requests (max 5 concurrent)
      final seenAlbumIds = <String>{};
      final albums = <Album>[];

      // Process in batches to avoid overwhelming the server
      const batchSize = LibraryConstants.recentAlbumsBatchSize;
      for (var i = 0; i < trackUris.length && albums.length < limit; i += batchSize) {
        final batch = trackUris.skip(i).take(batchSize).toList();

        // Fetch batch in parallel
        final futures = batch.map((uri) => _sendCommand(
          'music/item_by_uri',
          args: {'uri': uri},
        ).timeout(const Duration(seconds: 5), onTimeout: () => <String, dynamic>{'result': null}));

        final results = await Future.wait(futures, eagerError: false);

        for (final trackResponse in results) {
          if (albums.length >= limit) break;

          try {
            final fullTrack = trackResponse['result'] as Map<String, dynamic>?;
            final albumData = fullTrack?['album'] as Map<String, dynamic>?;

            if (albumData != null) {
              final albumId = albumData['item_id']?.toString() ?? albumData['uri']?.toString();
              if (albumId != null && !seenAlbumIds.contains(albumId)) {
                seenAlbumIds.add(albumId);
                albums.add(Album.fromJson(albumData));
              }
            }
          } catch (_) {
            // Skip tracks that fail to parse
            continue;
          }
        }
      }

      _logger.log('📚 Fetched ${albums.length} recent albums using ${(trackUris.length / batchSize).ceil()} batch requests');
      return albums;
    } catch (e) {
      _logger.log('❌ Error getting recent albums: $e');
      return [];
    }
  }

  /// Get random albums
  Future<List<Album>> getRandomAlbums({int limit = 10}) async {
    try {
      final response = await _sendCommand(
        'music/albums/library_items',
        args: {
          'limit': limit,
          'order_by': 'random',
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
  }) async {
    try {
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
  /// Toggle favorite status for any media item
  Future<bool> toggleFavorite(String mediaType, String itemId, String provider) async {
    try {
      final response = await _sendCommand(
        'music/favorites/toggle',
        args: {
          'media_type': mediaType,
          'item_id': itemId,
          'provider': provider,
        },
      );

      final isFavorite = response['result'] as bool? ?? false;
      return isFavorite;
    } catch (e) {
      _logger.log('Error toggling favorite: $e');
      return false;
    }
  }

  /// Mark item as favorite
  Future<void> addToFavorites(String mediaType, String itemId, String provider) async {
    try {
      await _sendCommand(
        'music/favorites/add',
        args: {
          'media_type': mediaType,
          'item_id': itemId,
          'provider': provider,
        },
      );
    } catch (e) {
      _logger.log('Error adding to favorites: $e');
      rethrow;
    }
  }

  /// Remove item from favorites
  Future<void> removeFromFavorites(String mediaType, String itemId, String provider) async {
    try {
      await _sendCommand(
        'music/favorites/remove',
        args: {
          'media_type': mediaType,
          'item_id': itemId,
          'provider': provider,
        },
      );
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

          // Deduplicate results by name
          // MA returns both library items and provider items for the same content
          // Prefer library items (provider='library') as they have all provider mappings
          return <String, List<MediaItem>>{
            'artists': _deduplicateResults(artists),
            'albums': _deduplicateResults(albums),
            'tracks': _deduplicateResults(tracks),
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
  Future<void> playRadio(String playerId, Track track) async {
    return await RetryHelper.retryCritical(
      operation: () async {
        // Try using library URI if available, otherwise use provider URI
        final libraryUri = track.uri;
        final trackUri = libraryUri ?? _buildTrackUri(track);

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
      
      // Determine the correct streaming port
      int streamPort;
      if (_cachedCustomPort != null) {
        // If custom port is set (e.g. 8095 or 443), use it.
        // Note: Music Assistant usually exposes streaming on the SAME port as the API
        // when behind a proxy or in standard docker config, OR on 8097 if accessed directly.
        // Since we are connecting via a custom port (likely the main web port),
        // we should try to use that same port for streaming if possible, 
        // or fallback to relative path if just path is needed.
        
        // However, standard MA behavior is:
        // API/WS: 8095
        // Stream: 8097 (internal) or /flow/... on 8095?
        // Actually, MA exposes /flow on the webserver port too!
        
        streamPort = _cachedCustomPort!;
      } else if (uri.hasPort) {
        streamPort = uri.port;
      } else {
        // No port specified in URL or settings
        if (useSecure) {
          streamPort = 443;
        } else {
          // If accessing via HTTP without port, assume default MA port 8095
          // But wait, earlier code hardcoded 8097. 
          // If the user is using a reverse proxy (no port in URL), we should likely stick to the default port (80/443)
          // effectively NOT adding a port.
          streamPort = useSecure ? 443 : 8095;
        }
      }

      // Reconstruct URI with the determined port
      final finalUri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: streamPort,
        path: '/flow/$playerId/$streamId.$extension',
      );

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

  /// Toggle shuffle mode for queue
  Future<void> toggleShuffle(String queueId) async {
    try {
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

  /// Register this device as a player
  /// CRITICAL: This creates a player config in MA's settings.json
  /// The server expects: player_id and player_name
  /// The server SHOULD set: provider=builtin_player, enabled=true, available=true
  Future<void> registerBuiltinPlayer(String playerId, String name) async {
    try {
      _logger.log('🎵 Registering builtin player: id=$playerId, name=$name');

      final response = await _sendCommand(
        'builtin_player/register',
        args: {
          'player_id': playerId,
          'player_name': name,  // Server expects 'player_name', not 'name'
        },
      );

      _logger.log('✅ Builtin player registered successfully');
      _logger.log('📊 Registration response: ${response['result']}');

      // CRITICAL: Explicitly save the player config to ensure all fields are persisted
      // This prevents the 999 error: "Field player_id of type str is missing in PlayerConfig"
      // The builtin_player/register creates the player but may not fully persist the config
      try {
        _logger.log('💾 Saving player config to ensure persistence...');
        await _sendCommand(
          'config/players/save',
          args: {
            'player_id': playerId,
            'values': <String, dynamic>{}, // Empty values dict - just ensure config is saved
          },
        );
        _logger.log('✅ Player config saved successfully');
      } catch (e) {
        // config/players/save may fail if player doesn't have a config yet
        // This is non-fatal, the registration may still work
        _logger.log('⚠️ Could not save player config (may already be saved): $e');
      }

      // VERIFICATION: Check that the player was actually created properly
      // Wait a moment for server to process, then verify
      await Future.delayed(const Duration(milliseconds: 500));

      final players = await getPlayers();
      final registeredPlayer = players.where((p) => p.playerId == playerId).firstOrNull;

      if (registeredPlayer == null) {
        _logger.log('⚠️ WARNING: Player was registered but not found in player list');
      } else if (!registeredPlayer.available) {
        _logger.log('⚠️ WARNING: Player registered but marked as unavailable');
      } else {
        _logger.log('✅ Verification passed: Player is available in MA');
      }
    } catch (e) {
      _logger.log('❌ Error registering built-in player: $e');
      rethrow; // Rethrow to propagate the error up
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

  /// Clean up ghost players (duplicate app player registrations)
  /// Set `allUnavailable` to true to remove ALL unavailable players (user-triggered)
  /// Set `allUnavailable` to false to only remove app-specific ghosts (auto-cleanup)
  /// Set `includeAvailable` to true to also remove available ghost players (duplicates)
  /// Returns (removedCount, failedCount)
  Future<(int, int)> cleanupGhostPlayers({
    bool allUnavailable = false,
    bool includeAvailable = true,
  }) async {
    try {
      _logger.log('🧹 Starting ghost player cleanup...');
      _logger.log('   Mode: allUnavailable=$allUnavailable, includeAvailable=$includeAvailable');

      final allPlayers = await getPlayers();
      final currentPlayerId = await SettingsService.getBuiltinPlayerId();

      // Filter players to find ghosts
      final playersToRemove = allPlayers.where((player) {
        // Never remove our current player
        if (player.playerId == currentPlayerId) return false;

        final id = player.playerId.toLowerCase();
        final isAppPlayer = id.startsWith('ensemble_') ||
                            id.startsWith('massiv_') ||
                            id.startsWith('ma_');

        if (allUnavailable) {
          // Remove all unavailable players
          return !player.available;
        } else {
          // Only remove app-specific ghosts
          if (!isAppPlayer) return false;

          // Remove unavailable app players always
          if (!player.available) return true;

          // Remove available app players only if includeAvailable is true (duplicates)
          return includeAvailable;
        }
      }).toList();

      if (playersToRemove.isEmpty) {
        _logger.log('✅ No ghost players to clean up');
        return (0, 0);
      }

      _logger.log('🗑️ Found ${playersToRemove.length} ghost player(s) to remove');

      int removedCount = 0;
      int failedCount = 0;

      for (final player in playersToRemove) {
        try {
          final playerId = player.playerId;
          _logger.log('🗑️ Removing: ${player.name} (${player.playerId})');

          // For available players, first disable them via config/players/save
          // This ensures the config is properly updated before removal
          if (player.available) {
            try {
              await _sendCommand('config/players/save', args: {
                'player_id': playerId,
                'values': {'enabled': false},
              });
              _logger.log('   ✓ Disabled player config');
            } catch (e) {
              _logger.log('   ⚠️ Could not disable config (may be corrupt): $e');
              // Continue anyway - the 3-step process may still work
            }
          }

          // Step 1: Unregister builtin player (disconnect it)
          try {
            await _sendCommand('builtin_player/unregister', args: {'player_id': playerId});
            _logger.log('   ✓ Unregistered builtin player');
          } catch (e) {
            // May already be unregistered or not a builtin player
          }

          // Step 2: Remove from player manager (runtime)
          try {
            await _sendCommand('players/remove', args: {'player_id': playerId});
            _logger.log('   ✓ Removed from player manager');
          } catch (e) {
            // May not be in manager
          }

          // Step 3: Remove persistent config
          try {
            await _sendCommand('config/players/remove', args: {'player_id': playerId});
            _logger.log('   ✅ Permanently deleted from config');
            removedCount++;
          } catch (e) {
            _logger.log('   ⚠️ Could not delete config: $e');
            // Count as partial success - runtime removal worked
            removedCount++;
          }
        } catch (e) {
          _logger.log('   ❌ Failed to remove ${player.name}: $e');
          failedCount++;
        }
      }

      _logger.log('✅ Cleanup complete - removed $removedCount, failed $failedCount');
      return (removedCount, failedCount);
    } catch (e) {
      _logger.log('❌ Error during cleanup: $e');
      return (0, 0);
    }
  }

  /// Repair corrupt player configs by re-saving them with complete data
  /// This fixes players that have incomplete configs (missing player_id, etc.)
  /// Returns (repairedCount, failedCount)
  Future<(int, int)> repairCorruptPlayers() async {
    try {
      _logger.log('🔧 Starting corrupt player repair...');

      final allPlayers = await getPlayers();
      int repairedCount = 0;
      int failedCount = 0;

      for (final player in allPlayers) {
        final id = player.playerId.toLowerCase();
        final isAppPlayer = id.startsWith('ensemble_') ||
                            id.startsWith('massiv_') ||
                            id.startsWith('ma_');

        if (!isAppPlayer) continue;

        // Try to save the config - this will fail with error 999 if corrupt
        try {
          // First try to get the current config
          await _sendCommand('config/players/get', args: {'player_id': player.playerId});
          // If no error, config is OK
          _logger.log('   ✓ ${player.name}: Config OK');
        } catch (e) {
          if (e.toString().contains('999') || e.toString().contains('missing')) {
            _logger.log('   ⚠️ ${player.name}: Corrupt config detected, attempting repair...');

            try {
              // Try to save a complete config
              await _sendCommand('config/players/save', args: {
                'player_id': player.playerId,
                'values': {
                  'enabled': player.available,
                },
              });
              _logger.log('   ✅ ${player.name}: Repaired!');
              repairedCount++;
            } catch (repairError) {
              _logger.log('   ❌ ${player.name}: Repair failed: $repairError');
              // Try to delete the corrupt entry instead
              try {
                await _sendCommand('builtin_player/unregister', args: {'player_id': player.playerId});
                await _sendCommand('players/remove', args: {'player_id': player.playerId});
                await _sendCommand('config/players/remove', args: {'player_id': player.playerId});
                _logger.log('   🗑️ ${player.name}: Deleted corrupt entry');
                repairedCount++;
              } catch (deleteError) {
                _logger.log('   ❌ ${player.name}: Could not delete: $deleteError');
                failedCount++;
              }
            }
          }
        }
      }

      _logger.log('✅ Repair complete - repaired $repairedCount, failed $failedCount');
      return (repairedCount, failedCount);
    } catch (e) {
      _logger.log('❌ Error during repair: $e');
      return (0, 0);
    }
  }

  /// Find an unavailable ghost player that matches the owner name pattern
  /// Used to "adopt" a previous installation's player ID instead of creating a new ghost
  /// Returns the player ID to adopt, or null if no match found
  Future<String?> findAdoptableGhostPlayer(String ownerName) async {
    try {
      _logger.log('🔍 Looking for adoptable ghost player for owner: $ownerName');

      final allPlayers = await getPlayers();

      // Build the expected player name pattern (e.g., "Chris' Phone" or "Chris's Phone")
      final expectedName1 = ownerName.endsWith('s')
          ? "$ownerName' Phone"
          : "$ownerName's Phone";
      final expectedName2 = "$ownerName's Phone"; // Always check this variant too

      _logger.log('🔍 Looking for players named: "$expectedName1" or "$expectedName2"');

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

          _logger.log('🔍 Found matching player: ${player.name} (${player.playerId}) '
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
        _logger.log('✅ Found adoptable player: ${matchedPlayer.name} (${matchedPlayer.playerId})');
        return matchedPlayer.playerId;
      }

      _logger.log('🔍 No adoptable ghost player found');
      return null;
    } catch (e) {
      _logger.log('❌ Error finding adoptable ghost player: $e');
      return null;
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

    // Always use imageproxy endpoint to ensure images route through our server
    // This fixes images not loading when connecting via external domain
    // (direct URLs may contain internal IPs not reachable from outside the network)

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

  void _updateConnectionState(MAConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);
  }

  Future<void> _reconnect() async {
    await Future.delayed(Timings.reconnectDelay);
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
