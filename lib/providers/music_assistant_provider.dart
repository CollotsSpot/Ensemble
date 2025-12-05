import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../constants/timings.dart' show Timings, LibraryConstants;
import '../models/media_item.dart';
import '../models/player.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';
import '../services/local_player_service.dart';
import '../services/auth/auth_manager.dart';
import '../services/device_id_service.dart';
import '../main.dart' show audioHandler;

class MusicAssistantProvider with ChangeNotifier {
  MusicAssistantAPI? _api;
  final AuthManager _authManager = AuthManager();
  final DebugLogger _logger = DebugLogger();
  late final LocalPlayerService _localPlayer;
  
  MAConnectionState _connectionState = MAConnectionState.disconnected;
  String? _serverUrl;

  List<Artist> _artists = [];
  List<Album> _albums = [];
  List<Track> _tracks = [];
  bool _isLoading = false;
  String? _error;

  // Player selection
  Player? _selectedPlayer;
  List<Player> _availablePlayers = [];
  Track? _currentTrack; // Current track playing on selected player
  Timer? _playerStateTimer;
  
  // Local Playback - always enabled
  bool _isLocalPlayerPowered = true; // Track local player power state
  StreamSubscription? _localPlayerEventSubscription;
  StreamSubscription? _playerUpdatedEventSubscription;
  Timer? _localPlayerStateReportTimer;

  // Pending metadata from player_updated events (for notification display)
  TrackMetadata? _pendingTrackMetadata;
  // Metadata that is currently shown in the notification (to detect when update needed)
  TrackMetadata? _currentNotificationMetadata;

  // Player list caching
  DateTime? _playersLastFetched;

  // Home screen row caching
  List<Album>? _cachedRecentAlbums;
  List<Artist>? _cachedDiscoverArtists;
  List<Album>? _cachedDiscoverAlbums;
  DateTime? _recentAlbumsLastFetched;
  DateTime? _discoverArtistsLastFetched;
  DateTime? _discoverAlbumsLastFetched;

  // Detail screen caching
  final Map<String, List<Track>> _albumTracksCache = {};
  final Map<String, DateTime> _albumTracksCacheTime = {};
  final Map<String, List<Track>> _playlistTracksCache = {};
  final Map<String, DateTime> _playlistTracksCacheTime = {};
  final Map<String, List<Album>> _artistAlbumsCache = {};
  final Map<String, DateTime> _artistAlbumsCacheTime = {};

  // Search results caching
  final Map<String, Map<String, List<MediaItem>>> _searchCache = {};
  final Map<String, DateTime> _searchCacheTime = {};

  // Registration guard to prevent concurrent registration attempts
  // This implements the pattern from research: prevent ghost creation during rapid reconnects
  Completer<void>? _registrationInProgress;

  MAConnectionState get connectionState => _connectionState;
  String? get serverUrl => _serverUrl;
  List<Artist> get artists => _artists;
  List<Album> get albums => _albums;
  List<Track> get tracks => _tracks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _connectionState == MAConnectionState.connected ||
                          _connectionState == MAConnectionState.authenticated;

  // Search state persistence
  String _lastSearchQuery = '';
  Map<String, List<MediaItem>> _lastSearchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
  };

  String get lastSearchQuery => _lastSearchQuery;
  Map<String, List<MediaItem>> get lastSearchResults => _lastSearchResults;

  void saveSearchState(String query, Map<String, List<MediaItem>> results) {
    _lastSearchQuery = query;
    _lastSearchResults = results;
    // No notifyListeners() needed here as SearchScreen manages its own UI updates
    // and just reads this on init
  }

  void clearSearchState() {
    _lastSearchQuery = '';
    _lastSearchResults = {
      'artists': [],
      'albums': [],
      'tracks': [],
    };
  }

  // ============================================================================
  // HOME SCREEN ROW CACHING
  // ============================================================================

  /// Get recently played albums with caching
  /// Returns cached data if still valid, otherwise fetches fresh
  Future<List<Album>> getRecentAlbumsWithCache({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final cacheValid = !forceRefresh &&
        _cachedRecentAlbums != null &&
        _recentAlbumsLastFetched != null &&
        now.difference(_recentAlbumsLastFetched!) < Timings.homeRowCacheDuration;

    if (cacheValid) {
      _logger.log('📦 Using cached recent albums (${_cachedRecentAlbums!.length} items)');
      return _cachedRecentAlbums!;
    }

    if (_api == null) return _cachedRecentAlbums ?? [];

    try {
      _logger.log('🔄 Fetching fresh recent albums...');
      final albums = await _api!.getRecentAlbums(limit: LibraryConstants.defaultRecentLimit);
      _cachedRecentAlbums = albums;
      _recentAlbumsLastFetched = DateTime.now();
      _logger.log('✅ Cached ${albums.length} recent albums');
      return albums;
    } catch (e) {
      _logger.log('❌ Failed to fetch recent albums: $e');
      return _cachedRecentAlbums ?? [];
    }
  }

  /// Get discover artists (random) with caching
  Future<List<Artist>> getDiscoverArtistsWithCache({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final cacheValid = !forceRefresh &&
        _cachedDiscoverArtists != null &&
        _discoverArtistsLastFetched != null &&
        now.difference(_discoverArtistsLastFetched!) < Timings.homeRowCacheDuration;

    if (cacheValid) {
      _logger.log('📦 Using cached discover artists (${_cachedDiscoverArtists!.length} items)');
      return _cachedDiscoverArtists!;
    }

    if (_api == null) return _cachedDiscoverArtists ?? [];

    try {
      _logger.log('🔄 Fetching fresh discover artists...');
      final artists = await _api!.getRandomArtists(limit: LibraryConstants.defaultRecentLimit);
      _cachedDiscoverArtists = artists;
      _discoverArtistsLastFetched = DateTime.now();
      _logger.log('✅ Cached ${artists.length} discover artists');
      return artists;
    } catch (e) {
      _logger.log('❌ Failed to fetch discover artists: $e');
      return _cachedDiscoverArtists ?? [];
    }
  }

  /// Get discover albums (random) with caching
  Future<List<Album>> getDiscoverAlbumsWithCache({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final cacheValid = !forceRefresh &&
        _cachedDiscoverAlbums != null &&
        _discoverAlbumsLastFetched != null &&
        now.difference(_discoverAlbumsLastFetched!) < Timings.homeRowCacheDuration;

    if (cacheValid) {
      _logger.log('📦 Using cached discover albums (${_cachedDiscoverAlbums!.length} items)');
      return _cachedDiscoverAlbums!;
    }

    if (_api == null) return _cachedDiscoverAlbums ?? [];

    try {
      _logger.log('🔄 Fetching fresh discover albums...');
      final albums = await _api!.getRandomAlbums(limit: LibraryConstants.defaultRecentLimit);
      _cachedDiscoverAlbums = albums;
      _discoverAlbumsLastFetched = DateTime.now();
      _logger.log('✅ Cached ${albums.length} discover albums');
      return albums;
    } catch (e) {
      _logger.log('❌ Failed to fetch discover albums: $e');
      return _cachedDiscoverAlbums ?? [];
    }
  }

  /// Invalidate home screen cache (call on pull-to-refresh)
  void invalidateHomeCache() {
    _recentAlbumsLastFetched = null;
    _discoverArtistsLastFetched = null;
    _discoverAlbumsLastFetched = null;
    _logger.log('🗑️ Home screen cache invalidated');
  }

  // ============================================================================
  // END HOME SCREEN ROW CACHING
  // ============================================================================

  // ============================================================================
  // DETAIL SCREEN CACHING
  // ============================================================================

  /// Get album tracks with caching (5 min TTL)
  Future<List<Track>> getAlbumTracksWithCache(String provider, String itemId, {bool forceRefresh = false}) async {
    final cacheKey = '${provider}_$itemId';
    final now = DateTime.now();
    final cacheTime = _albumTracksCacheTime[cacheKey];
    final cacheValid = !forceRefresh &&
        _albumTracksCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < const Duration(minutes: 5);

    if (cacheValid) {
      _logger.log('📦 Using cached album tracks for $cacheKey (${_albumTracksCache[cacheKey]!.length} tracks)');
      return _albumTracksCache[cacheKey]!;
    }

    if (_api == null) return _albumTracksCache[cacheKey] ?? [];

    try {
      _logger.log('🔄 Fetching fresh album tracks for $cacheKey...');
      final tracks = await _api!.getAlbumTracks(provider, itemId);
      _albumTracksCache[cacheKey] = tracks;
      _albumTracksCacheTime[cacheKey] = DateTime.now();
      _logger.log('✅ Cached ${tracks.length} tracks for album $cacheKey');
      return tracks;
    } catch (e) {
      _logger.log('❌ Failed to fetch album tracks: $e');
      return _albumTracksCache[cacheKey] ?? [];
    }
  }

  /// Get playlist tracks with caching (5 min TTL)
  Future<List<Track>> getPlaylistTracksWithCache(String provider, String itemId, {bool forceRefresh = false}) async {
    final cacheKey = '${provider}_$itemId';
    final now = DateTime.now();
    final cacheTime = _playlistTracksCacheTime[cacheKey];
    final cacheValid = !forceRefresh &&
        _playlistTracksCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < const Duration(minutes: 5);

    if (cacheValid) {
      _logger.log('📦 Using cached playlist tracks for $cacheKey (${_playlistTracksCache[cacheKey]!.length} tracks)');
      return _playlistTracksCache[cacheKey]!;
    }

    if (_api == null) return _playlistTracksCache[cacheKey] ?? [];

    try {
      _logger.log('🔄 Fetching fresh playlist tracks for $cacheKey...');
      final tracks = await _api!.getPlaylistTracks(provider, itemId);
      _playlistTracksCache[cacheKey] = tracks;
      _playlistTracksCacheTime[cacheKey] = DateTime.now();
      _logger.log('✅ Cached ${tracks.length} tracks for playlist $cacheKey');
      return tracks;
    } catch (e) {
      _logger.log('❌ Failed to fetch playlist tracks: $e');
      return _playlistTracksCache[cacheKey] ?? [];
    }
  }

  /// Get artist albums with caching (10 min TTL)
  Future<List<Album>> getArtistAlbumsWithCache(String artistName, {bool forceRefresh = false}) async {
    final cacheKey = artistName.toLowerCase();
    final now = DateTime.now();
    final cacheTime = _artistAlbumsCacheTime[cacheKey];
    final cacheValid = !forceRefresh &&
        _artistAlbumsCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < Timings.homeRowCacheDuration;

    if (cacheValid) {
      _logger.log('📦 Using cached artist albums for "$artistName" (${_artistAlbumsCache[cacheKey]!.length} albums)');
      return _artistAlbumsCache[cacheKey]!;
    }

    if (_api == null) return _artistAlbumsCache[cacheKey] ?? [];

    try {
      _logger.log('🔄 Fetching albums for artist "$artistName"...');

      // Get library albums
      final libraryAlbums = await _api!.getAlbums();
      final artistAlbums = libraryAlbums.where((album) {
        final albumArtists = album.artists;
        if (albumArtists == null || albumArtists.isEmpty) return false;
        return albumArtists.any((a) =>
          a.name.toLowerCase() == artistName.toLowerCase());
      }).toList();

      // Also search provider for more albums
      final searchResults = await _api!.search(artistName);
      final searchAlbums = searchResults['albums'] as List<MediaItem>? ?? [];
      final providerAlbums = searchAlbums.whereType<Album>().where((album) {
        final albumArtists = album.artists;
        if (albumArtists == null || albumArtists.isEmpty) return false;
        return albumArtists.any((a) =>
          a.name.toLowerCase() == artistName.toLowerCase());
      }).toList();

      // Merge and deduplicate
      final allAlbums = <Album>[];
      final seenNames = <String>{};

      for (final album in [...artistAlbums, ...providerAlbums]) {
        final key = album.name.toLowerCase();
        if (!seenNames.contains(key)) {
          seenNames.add(key);
          allAlbums.add(album);
        }
      }

      _artistAlbumsCache[cacheKey] = allAlbums;
      _artistAlbumsCacheTime[cacheKey] = DateTime.now();
      _logger.log('✅ Cached ${allAlbums.length} albums for artist "$artistName"');
      return allAlbums;
    } catch (e) {
      _logger.log('❌ Failed to fetch artist albums: $e');
      return _artistAlbumsCache[cacheKey] ?? [];
    }
  }

  /// Invalidate album tracks cache (call after playing/modifying)
  void invalidateAlbumTracksCache(String albumId) {
    _albumTracksCache.remove(albumId);
    _albumTracksCacheTime.remove(albumId);
  }

  /// Invalidate playlist tracks cache
  void invalidatePlaylistTracksCache(String playlistId) {
    _playlistTracksCache.remove(playlistId);
    _playlistTracksCacheTime.remove(playlistId);
  }

  // ============================================================================
  // SEARCH CACHING
  // ============================================================================

  /// Search with caching (10 min TTL per query)
  Future<Map<String, List<MediaItem>>> searchWithCache(String query, {bool forceRefresh = false}) async {
    final cacheKey = query.toLowerCase().trim();
    if (cacheKey.isEmpty) return {'artists': [], 'albums': [], 'tracks': []};

    final now = DateTime.now();
    final cacheTime = _searchCacheTime[cacheKey];
    final cacheValid = !forceRefresh &&
        _searchCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < Timings.homeRowCacheDuration;

    if (cacheValid) {
      _logger.log('📦 Using cached search results for "$query"');
      return _searchCache[cacheKey]!;
    }

    if (_api == null) return _searchCache[cacheKey] ?? {'artists': [], 'albums': [], 'tracks': []};

    try {
      _logger.log('🔄 Searching for "$query"...');
      final results = await _api!.search(query);

      final cachedResults = <String, List<MediaItem>>{
        'artists': results['artists'] ?? [],
        'albums': results['albums'] ?? [],
        'tracks': results['tracks'] ?? [],
      };

      _searchCache[cacheKey] = cachedResults;
      _searchCacheTime[cacheKey] = DateTime.now();
      _logger.log('✅ Cached search results for "$query"');
      return cachedResults;
    } catch (e) {
      _logger.log('❌ Search failed: $e');
      return _searchCache[cacheKey] ?? {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  /// Clear all detail caches (call on disconnect/reconnect)
  void clearAllDetailCaches() {
    _albumTracksCache.clear();
    _albumTracksCacheTime.clear();
    _playlistTracksCache.clear();
    _playlistTracksCacheTime.clear();
    _artistAlbumsCache.clear();
    _artistAlbumsCacheTime.clear();
    _searchCache.clear();
    _searchCacheTime.clear();
    _logger.log('🗑️ All detail caches cleared');
  }

  // ============================================================================
  // END DETAIL SCREEN CACHING
  // ============================================================================

  // Player selection getters
  Player? get selectedPlayer => _selectedPlayer;
  List<Player> get availablePlayers => _availablePlayers;
  Track? get currentTrack => _currentTrack;

  // Debug: Get ALL players including filtered ones
  Future<List<Player>> getAllPlayersUnfiltered() async {
    return await getPlayers();
  }

  // Get current device's player ID
  Future<String?> getCurrentPlayerId() async {
    return await SettingsService.getBuiltinPlayerId();
  }

  // API access
  MusicAssistantAPI? get api => _api;

  // Auth manager access for login screen
  AuthManager get authManager => _authManager;

  MusicAssistantProvider() {
    _localPlayer = LocalPlayerService(_authManager);
    _initialize();
  }

  Future<void> _initialize() async {
    _serverUrl = await SettingsService.getServerUrl();
    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      // Restore saved auth credentials before connecting
      await _restoreAuthCredentials();
      await connectToServer(_serverUrl!);
      await _initializeLocalPlayback();
    }
  }

  /// Restore auth credentials from persistent storage
  /// This is critical for reconnection after app process is killed
  Future<void> _restoreAuthCredentials() async {
    final savedCredentials = await SettingsService.getAuthCredentials();
    if (savedCredentials != null) {
      _logger.log('🔐 Restoring saved auth credentials...');
      _authManager.deserializeCredentials(savedCredentials);
      _logger.log('🔐 Auth credentials restored: ${_authManager.currentStrategy?.name ?? "none"}');
    } else {
      _logger.log('🔐 No saved auth credentials found');
    }
  }

  /// Handle Music Assistant native authentication after WebSocket connection
  /// This is called when the server reports auth is required (schema 28+)
  /// Returns true if authentication succeeded, false otherwise
  Future<bool> _handleMaAuthentication() async {
    if (_api == null) return false;

    try {
      // First, try stored MA token
      final storedToken = await SettingsService.getMaAuthToken();
      if (storedToken != null) {
        _logger.log('🔐 Trying stored MA token...');
        final success = await _api!.authenticateWithToken(storedToken);
        if (success) {
          _logger.log('✅ MA authentication with stored token successful');
          // Fetch user profile and set owner name from display_name
          await _fetchAndSetUserProfileName();
          return true;
        }
        _logger.log('⚠️ Stored MA token invalid, clearing...');
        await SettingsService.clearMaAuthToken();
      }

      // No valid token - try stored credentials
      final username = await SettingsService.getUsername();
      final password = await SettingsService.getPassword();

      if (username != null && password != null && username.isNotEmpty && password.isNotEmpty) {
        _logger.log('🔐 Trying stored credentials...');
        final accessToken = await _api!.loginWithCredentials(username, password);

        if (accessToken != null) {
          _logger.log('✅ MA login with stored credentials successful');

          // Try to create and save a long-lived token for future use
          final longLivedToken = await _api!.createLongLivedToken();
          if (longLivedToken != null) {
            await SettingsService.setMaAuthToken(longLivedToken);
            _logger.log('✅ Saved new long-lived MA token');
          } else {
            // Fall back to access token
            await SettingsService.setMaAuthToken(accessToken);
          }

          // Fetch user profile and set owner name from display_name
          await _fetchAndSetUserProfileName();

          return true;
        }
      }

      _logger.log('❌ MA authentication failed - no valid token or credentials');
      return false;
    } catch (e) {
      _logger.log('❌ MA authentication error: $e');
      return false;
    }
  }

  /// Fetch user profile from MA and set owner name from display_name
  /// This allows using the MA profile name as the player name
  /// For MA auth, this ALWAYS sets the owner name from the profile
  Future<void> _fetchAndSetUserProfileName() async {
    if (_api == null) return;

    try {
      final userInfo = await _api!.getCurrentUserInfo();
      if (userInfo == null) {
        _logger.log('⚠️ Could not fetch user profile');
        return;
      }

      final displayName = userInfo['display_name'] as String?;
      final username = userInfo['username'] as String?;

      _logger.log('🔍 Profile data: display_name="$displayName", username="$username"');

      // Prefer display_name, fall back to username
      final profileName = (displayName != null && displayName.isNotEmpty)
          ? displayName
          : username;

      if (profileName != null && profileName.isNotEmpty) {
        // For MA auth, always use the profile name (overwrite any existing)
        // This ensures the player name stays in sync with MA profile
        await SettingsService.setOwnerName(profileName);
        _logger.log('✅ Set owner name from MA profile: $profileName');
      } else {
        _logger.log('⚠️ No valid name in profile (display_name and username both empty)');
      }
    } catch (e) {
      _logger.log('⚠️ Could not fetch user profile (non-fatal): $e');
    }
  }

  /// Initialize after connection/authentication is complete
  /// This consolidates all post-auth initialization steps including the critical
  /// fetchState() call that populates providers and players
  Future<void> _initializeAfterConnection() async {
    if (_api == null) return;

    try {
      _logger.log('🚀 Initializing after connection...');

      // STEP 1: Fetch initial state (providers and players)
      // This is CRITICAL for player discovery with auth enabled
      // It matches the MA frontend's fetchState() behavior
      await _api!.fetchState();

      // STEP 2: Fetch user profile to get display_name for player name
      // This MUST happen BEFORE player registration so the name is correct
      if (_api!.authRequired) {
        await _fetchAndSetUserProfileName();
      }

      // STEP 3: Try to adopt an existing ghost player (fresh install only)
      // This must happen BEFORE DeviceIdService generates a new ID
      await _tryAdoptGhostPlayer();

      // STEP 4: Register local player
      // DeviceIdService will use adopted ID if available, or generate new
      await _registerLocalPlayer();

      // NOTE: Ghost player cleanup removed - the MA APIs don't work reliably
      // and actually caused corrupt player entries. See PLAYER_LIFECYCLE_GUIDE.md

      // STEP 5: Load available players and auto-select local player
      await _loadAndSelectPlayers();

      // STEP 7: Auto-load library when connected
      loadLibrary();

      _logger.log('✅ Post-connection initialization complete');
    } catch (e) {
      _logger.log('❌ Error during post-connection initialization: $e');
      _error = 'Failed to initialize after connection';
      notifyListeners();
    }
  }

  Future<void> _initializeLocalPlayback() async {
    await _localPlayer.initialize();
    _isLocalPlayerPowered = true; // Default to powered on when enabling local playback

    // Wire up skip button callbacks from notification to Music Assistant server
    audioHandler.onSkipToNext = () {
      _logger.log('🎵 Notification: Skip to next pressed');
      nextTrackSelectedPlayer();
    };
    audioHandler.onSkipToPrevious = () {
      _logger.log('🎵 Notification: Skip to previous pressed');
      previousTrackSelectedPlayer();
    };

    if (isConnected) {
      await _registerLocalPlayer();
    }
  }

  /// Try to adopt an existing ghost player instead of creating a new one
  /// This prevents ghost player accumulation when the app is reinstalled
  /// Returns true if a ghost was adopted, false otherwise
  ///
  /// IMPORTANT: This should be called BEFORE DeviceIdService generates a new ID
  Future<bool> _tryAdoptGhostPlayer() async {
    if (_api == null) return false;

    try {
      // Only attempt adoption on fresh installs
      final isFresh = await DeviceIdService.isFreshInstallation();
      if (!isFresh) {
        _logger.log('👻 Not a fresh install, skipping ghost adoption');
        return false;
      }

      // Get owner name - needed to find matching ghost players
      final ownerName = await SettingsService.getOwnerName();
      if (ownerName == null || ownerName.isEmpty) {
        _logger.log('👻 No owner name set, cannot adopt ghost player');
        return false;
      }

      // Look for an adoptable ghost player matching the owner name
      _logger.log('👻 Fresh install detected, searching for adoptable ghost for "$ownerName"...');
      final adoptableId = await _api!.findAdoptableGhostPlayer(ownerName);
      if (adoptableId == null) {
        _logger.log('👻 No matching ghost player found - will generate new ID');
        return false;
      }

      // Found a ghost player - adopt its ID BEFORE DeviceIdService generates one
      _logger.log('👻 Found adoptable ghost: $adoptableId');
      await DeviceIdService.adoptPlayerId(adoptableId);

      _logger.log('✅ Successfully adopted ghost player, preventing new ghost creation');
      return true;
    } catch (e) {
      _logger.log('⚠️ Ghost adoption failed (non-fatal): $e');
      return false;
    }
  }

  // NOTE: purgeUnavailablePlayers and getUnavailablePlayersCount removed.
  // The MA APIs for player removal don't work reliably and caused corrupt entries.
  // Ghost cleanup must be done manually - see PLAYER_LIFECYCLE_GUIDE.md

  Future<void> _registerLocalPlayer() async {
    if (_api == null) return;

    // Guard against concurrent registration attempts
    // This prevents ghost creation during rapid connect/disconnect cycles
    if (_registrationInProgress != null) {
      _logger.log('⏳ Registration already in progress, waiting...');
      return _registrationInProgress!.future;
    }

    _registrationInProgress = Completer<void>();

    try {
      // Get or generate player ID
      // DeviceIdService handles the lazy generation pattern
      final playerId = await DeviceIdService.getOrCreateDevicePlayerId();
      _logger.log('🆔 Using player ID: $playerId');

      // Ensure SettingsService cache is in sync
      await SettingsService.setBuiltinPlayerId(playerId);

      final name = await SettingsService.getLocalPlayerName();

      // CRITICAL: Check if player already exists before re-registering
      // This implements the pattern from research: "check for existing player on reconnect"
      final existingPlayers = await _api!.getPlayers();
      final existingPlayer = existingPlayers.where((p) => p.playerId == playerId).firstOrNull;

      if (existingPlayer != null && existingPlayer.available) {
        // Player already exists and is available - just resume state updates
        _logger.log('✅ Player already registered and available: $playerId');
        _logger.log('   No re-registration needed, resuming state updates');
        _startReportingLocalPlayerState();
        _registrationInProgress?.complete();
        _registrationInProgress = null;
        return;
      } else if (existingPlayer != null && !existingPlayer.available) {
        // Player exists but is unavailable (stale) - re-register to revive it
        _logger.log('⚠️ Player exists but unavailable (stale), re-registering: $playerId');
      } else {
        // Player doesn't exist - normal registration
        _logger.log('🆔 Player not found in MA, registering as new');
      }

      // Register with MA server
      _logger.log('🎵 Registering player with MA: id=$playerId, name=$name');
      await _api!.registerBuiltinPlayer(playerId, name);

      _logger.log('✅ Player registration complete');
      _startReportingLocalPlayerState();

      _registrationInProgress?.complete();
      _registrationInProgress = null;
    } catch (e) {
      _logger.log('❌ CRITICAL: Player registration failed: $e');
      _registrationInProgress?.completeError(e);
      _registrationInProgress = null;
      // This is a critical error - without registration, the app won't work
      rethrow;
    }
  }
  
  void _startReportingLocalPlayerState() {
    _localPlayerStateReportTimer?.cancel();
    // Report state at configured interval (for smooth seek bar)
    _localPlayerStateReportTimer = Timer.periodic(Timings.localPlayerReportInterval, (_) async {
      try {
        await _reportLocalPlayerState();
      } catch (e) {
        _logger.log('Error reporting local player state (will retry): $e');
      }
    });
  }
  
  Future<void> _reportLocalPlayerState() async {
    if (_api == null) return;

    final playerId = await SettingsService.getBuiltinPlayerId();
    if (playerId == null) return;

    // Get current player state
    final isPlaying = _localPlayer.isPlaying;
    final position = _localPlayer.position.inSeconds;
    final volume = (_localPlayer.volume * 100).round();

    // Calculate paused state: not playing but has a position (i.e., paused, not stopped)
    final isPaused = !isPlaying && position > 0;

    // Send state as proper dataclass object (not string)
    // Fixed: Server expects BuiltinPlayerState with boolean fields
    await _api!.updateBuiltinPlayerState(
      playerId,
      powered: _isLocalPlayerPowered,
      playing: isPlaying,
      paused: isPaused,
      position: position,
      volume: volume,
      muted: _localPlayer.volume == 0.0,
    );
  }

  Future<void> connectToServer(String serverUrl) async {
    try {
      _error = null;
      _serverUrl = serverUrl;
      await SettingsService.setServerUrl(serverUrl);

      // Disconnect existing connection
      await _api?.disconnect();

      _api = MusicAssistantAPI(serverUrl, _authManager);

      // Listen to connection state changes
      _api!.connectionState.listen(
        (state) async {
          _connectionState = state;
          notifyListeners();

          if (state == MAConnectionState.connected) {
            _logger.log('🔗 WebSocket connected to MA server');

            // STEP 0: Handle MA native authentication if required
            if (_api!.authRequired && !_api!.isAuthenticated) {
              _logger.log('🔐 MA auth required, attempting authentication...');
              final authenticated = await _handleMaAuthentication();
              if (!authenticated) {
                _logger.log('❌ MA authentication failed - stopping connection flow');
                _error = 'Authentication required. Please log in again.';
                notifyListeners();
                return;
              }
              // If auth was required and succeeded, the authenticated state handler
              // will run the post-auth initialization
              return;
            }

            // No auth required - proceed with initialization immediately
            await _initializeAfterConnection();
          } else if (state == MAConnectionState.authenticated) {
            _logger.log('✅ MA authentication successful');
            // Auth succeeded - now run post-auth initialization
            await _initializeAfterConnection();
          } else if (state == MAConnectionState.disconnected) {
            _availablePlayers = [];
            _selectedPlayer = null;
          }
        },
        onError: (error) {
          _logger.log('Connection state stream error: $error');
          _connectionState = MAConnectionState.error;
          notifyListeners();
        },
      );
      
      // Listen to built-in player events
      _localPlayerEventSubscription?.cancel();
      _localPlayerEventSubscription = _api!.builtinPlayerEvents.listen(
        _handleLocalPlayerEvent,
        onError: (error) {
          _logger.log('Builtin player event stream error: $error');
        },
      );

      // Listen to player_updated events to capture track metadata for notifications
      _playerUpdatedEventSubscription?.cancel();
      _playerUpdatedEventSubscription = _api!.playerUpdatedEvents.listen(
        _handlePlayerUpdatedEvent,
        onError: (error) {
          _logger.log('Player updated event stream error: $error');
        },
      );

      await _api!.connect();
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Connect to server');
      _error = errorInfo.userMessage;
      _connectionState = MAConnectionState.error;
      _logger.log('Connection error: ${errorInfo.technicalMessage}');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _handleLocalPlayerEvent(Map<String, dynamic> event) async {
    _logger.log('📥 Local player event received: ${event['type'] ?? event['command']}');

    try {
      // CRITICAL: Only process events for THIS device's player
      // This prevents cross-device playback (e.g., wife's phone playing when you play on yours)
      final eventPlayerId = event['player_id'] as String?;
      final myPlayerId = await SettingsService.getBuiltinPlayerId();

      if (eventPlayerId != null && myPlayerId != null && eventPlayerId != myPlayerId) {
        _logger.log('🚫 Ignoring event for different player: $eventPlayerId (my player: $myPlayerId)');
        return;
      }

      // Server sends 'type', but older versions or some events might use 'command'
      final command = (event['type'] as String?) ?? (event['command'] as String?);

      switch (command) {
        case 'play_media':
          // Server sends 'media_url', relative path
          final urlPath = event['media_url'] as String? ?? event['url'] as String?;

          _logger.log('🎵 play_media: urlPath=$urlPath, _serverUrl=$_serverUrl');

          if (urlPath != null && _serverUrl != null) {
            // Construct full URL
            String fullUrl;
            if (urlPath.startsWith('http')) {
              fullUrl = urlPath;
              _logger.log('🎵 Using absolute URL from server: $fullUrl');
            } else {
              // Add protocol if not present
              var baseUrl = _serverUrl!;
              if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
                baseUrl = 'https://$baseUrl';
                _logger.log('🎵 Added https:// protocol to baseUrl: $baseUrl');
              }

              // Ensure no double slashes
              baseUrl = baseUrl.endsWith('/')
                  ? baseUrl.substring(0, baseUrl.length - 1)
                  : baseUrl;
              final path = urlPath.startsWith('/') ? urlPath : '/$urlPath';
              fullUrl = '$baseUrl$path';
              _logger.log('🎵 Constructed URL: baseUrl=$baseUrl + path=$path = $fullUrl');
            }

            // Use pending metadata from player_updated event if available
            // (player_updated events arrive before play_media and contain full track info)
            TrackMetadata metadata;
            if (_pendingTrackMetadata != null) {
              metadata = _pendingTrackMetadata!;
              _logger.log('🎵 Using metadata from player_updated: ${metadata.title} by ${metadata.artist}');
            } else {
              // Fallback: try to extract from play_media event (usually empty)
              final trackName = event['track_name'] as String? ??
                                event['name'] as String? ??
                                'Unknown Track';
              final artistName = event['artist_name'] as String? ??
                                 event['artist'] as String? ??
                                 'Unknown Artist';
              final albumName = event['album_name'] as String? ??
                                event['album'] as String?;
              var artworkUrl = event['image_url'] as String? ??
                                 event['artwork_url'] as String?;
              final durationSecs = event['duration'] as int?;

              // Convert HTTP to HTTPS for artwork
              if (artworkUrl != null && artworkUrl.startsWith('http://')) {
                artworkUrl = artworkUrl.replaceFirst('http://', 'https://');
              }

              metadata = TrackMetadata(
                title: trackName,
                artist: artistName,
                album: albumName,
                artworkUrl: artworkUrl,
                duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
              );
              _logger.log('🎵 Using fallback metadata: ${metadata.title} by ${metadata.artist}');
            }

            // Set metadata on the local player for notification
            _localPlayer.setCurrentTrackMetadata(metadata);
            // Track what metadata we're using for the notification
            _currentNotificationMetadata = metadata;

            await _localPlayer.playUrl(fullUrl);
          } else {
            _logger.log('❌ Cannot play media: urlPath=$urlPath, _serverUrl=$_serverUrl');
          }
          break;

        case 'stop':
          await _localPlayer.stop();
          break;

        case 'pause':
          await _localPlayer.pause();
          break;

        case 'play':
          await _localPlayer.play();
          break;

        case 'seek':
          final position = event['position'] as int?;
          if (position != null) {
            await _localPlayer.seek(Duration(seconds: position));
          }
          break;

        case 'volume_set':
          final volume = event['volume_level'] as int?;
          if (volume != null) {
            await _localPlayer.setVolume(volume / 100.0);
          }
          break;

        case 'power_on':
        case 'power_off':
        case 'power':
          _logger.log('🔋 POWER COMMAND RECEIVED: $command');
          
          bool? newPowerState;
          if (command == 'power_on') {
            newPowerState = true;
          } else if (command == 'power_off') {
            newPowerState = false;
          } else {
            // Legacy 'power' command with 'powered' bool
            newPowerState = event['powered'] as bool?;
          }

          if (newPowerState != null) {
            _isLocalPlayerPowered = newPowerState;
            _logger.log('🔋 Local player power set to: $_isLocalPlayerPowered');
            if (!_isLocalPlayerPowered) {
              // When powered off, stop playback
              _logger.log('🔋 Stopping playback because powered off');
              await _localPlayer.stop();
            }
          }
          break;
      }
      
      // Report state immediately after command
      await _reportLocalPlayerState();
      
    } catch (e) {
      _logger.log('Error handling local player event: $e');
    }
  }

  /// Handle player_updated events to capture track metadata for notifications
  Future<void> _handlePlayerUpdatedEvent(Map<String, dynamic> event) async {
    try {
      // Get our builtin player ID
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId == null) return;

      // Check if this update is for our player
      final playerId = event['player_id'] as String?;
      if (playerId != builtinPlayerId) return;

      // Extract current_media metadata
      final currentMedia = event['current_media'] as Map<String, dynamic>?;
      if (currentMedia == null) {
        // Don't clear pending metadata when current_media is null
        // This happens during stop/transition and we want to keep the last known metadata
        // until new metadata arrives
        return;
      }

      final title = currentMedia['title'] as String? ?? 'Unknown Track';
      final artist = currentMedia['artist'] as String? ?? 'Unknown Artist';
      final album = currentMedia['album'] as String?;
      var imageUrl = currentMedia['image_url'] as String?;
      final durationSecs = currentMedia['duration'] as int?;

      // Rewrite image URL to use main server URL
      // The server returns URLs like http://ma.serverscloud.org:8097/imageproxy?...
      // but port 8097 isn't exposed externally - we need to route through main port
      if (imageUrl != null && _serverUrl != null) {
        try {
          final imgUri = Uri.parse(imageUrl);
          // Extract query parameters (provider, size, fmt, path)
          final queryString = imgUri.query;

          // Build new URL using our server URL
          var baseUrl = _serverUrl!;
          if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
            baseUrl = 'https://$baseUrl';
          }
          // Remove trailing slash if present
          if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.substring(0, baseUrl.length - 1);
          }

          imageUrl = '$baseUrl/imageproxy?$queryString';
          _logger.log('📋 Rewrote image URL to use main server: $imageUrl');
        } catch (e) {
          _logger.log('📋 Failed to rewrite image URL: $e');
          // Fall back to just HTTP->HTTPS conversion
          if (imageUrl != null && imageUrl.startsWith('http://')) {
            imageUrl = imageUrl.replaceFirst('http://', 'https://');
          }
        }
      }

      final newMetadata = TrackMetadata(
        title: title,
        artist: artist,
        album: album,
        artworkUrl: imageUrl,
        duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
      );

      // Only update pending metadata if this is real track info (not flow_stream placeholder)
      final mediaType = currentMedia['media_type'] as String?;
      if (mediaType == 'flow_stream') {
        _logger.log('📋 Ignoring flow_stream metadata (placeholder)');
        return;
      }

      _pendingTrackMetadata = newMetadata;
      _logger.log('📋 Captured track metadata from player_updated: $title by $artist (image: ${imageUrl ?? "none"})');

      // Check if the notification has wrong/stale metadata that needs updating
      // This handles the race condition where play_media uses old pending metadata
      final notificationNeedsUpdate = _currentNotificationMetadata != null &&
          (_currentNotificationMetadata!.title != title ||
           _currentNotificationMetadata!.artist != artist);

      if (_localPlayer.isPlaying && notificationNeedsUpdate) {
        _logger.log('📋 Notification has stale metadata (${_currentNotificationMetadata!.title}) - updating to: $title by $artist');
        await _localPlayer.updateNotificationWhilePlaying(newMetadata);
        _currentNotificationMetadata = newMetadata;
      }
    } catch (e) {
      _logger.log('Error handling player_updated event: $e');
    }
  }

  Future<void> disconnect() async {
    _playerStateTimer?.cancel();
    _playerStateTimer = null;
    _localPlayerStateReportTimer?.cancel();
    _localPlayerEventSubscription?.cancel();
    _playerUpdatedEventSubscription?.cancel();
    await _api?.disconnect();
    _connectionState = MAConnectionState.disconnected;
    _artists = [];
    _albums = [];
    _tracks = [];
    _currentTrack = null;
    notifyListeners();
  }

  Future<void> loadLibrary() async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Load artists, albums, and tracks in parallel
      // Use configured max limit to fetch "all" items
      final results = await Future.wait([
        _api!.getArtists(limit: LibraryConstants.maxLibraryItems),
        _api!.getAlbums(limit: LibraryConstants.maxLibraryItems),
        _api!.getTracks(limit: LibraryConstants.maxLibraryItems),
      ]);

      _artists = results[0] as List<Artist>;
      _albums = results[1] as List<Album>;
      _tracks = results[2] as List<Track>;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load library');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadArtists({int? limit, int? offset, String? search}) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _artists = await _api!.getArtists(
        limit: limit ?? LibraryConstants.maxLibraryItems, // Default to high limit if not specified
        offset: offset,
        search: search,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load artists');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAlbums({
    int? limit,
    int? offset,
    String? search,
    String? artistId,
  }) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _albums = await _api!.getAlbums(
        limit: limit ?? LibraryConstants.maxLibraryItems, // Default to high limit
        offset: offset,
        search: search,
        artistId: artistId,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load albums');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Track>> getAlbumTracks(String provider, String itemId) async {
    if (!isConnected) return [];

    try {
      return await _api!.getAlbumTracks(provider, itemId);
    } catch (e) {
      ErrorHandler.logError('Get album tracks', e);
      return [];
    }
  }

  Future<Map<String, List<MediaItem>>> search(String query, {bool libraryOnly = false}) async {
    if (!isConnected) {
      return {'artists': [], 'albums': [], 'tracks': []};
    }

    try {
      return await _api!.search(query, libraryOnly: libraryOnly);
    } catch (e) {
      ErrorHandler.logError('Search', e);
      return {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  String getStreamUrl(String provider, String itemId, {String? uri, List<ProviderMapping>? providerMappings}) {
    return _api?.getStreamUrl(provider, itemId, uri: uri, providerMappings: providerMappings) ?? '';
  }

  String? getImageUrl(MediaItem item, {int size = 256}) {
    return _api?.getImageUrl(item, size: size);
  }

  // ============================================================================
  // PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  Future<List<Player>> getPlayers() async {
    return await _api?.getPlayers() ?? [];
  }

  Future<PlayerQueue?> getQueue(String playerId) async {
    return await _api?.getQueue(playerId);
  }

  Future<void> playTrack(String playerId, Track track, {bool clearQueue = true}) async {
    try {
      await _api?.playTrack(playerId, track, clearQueue: clearQueue);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play track');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play track', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex, bool clearQueue = true}) async {
    try {
      await _api?.playTracks(playerId, tracks, startIndex: startIndex, clearQueue: clearQueue);

      // Optimistically set current track so mini player appears immediately
      final trackIndex = startIndex ?? 0;
      if (tracks.isNotEmpty && trackIndex < tracks.length) {
        _currentTrack = tracks[trackIndex];
        notifyListeners();
      }
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play tracks');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play tracks', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playRadio(String playerId, Track track) async {
    try {
      await _api?.playRadio(playerId, track);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play radio');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play radio', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<String?> getCurrentStreamUrl(String playerId) async {
    return await _api?.getCurrentStreamUrl(playerId);
  }

  Future<void> pausePlayer(String playerId) async {
    try {
      await _api?.pausePlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Pause player', e);
      rethrow;
    }
  }

  Future<void> resumePlayer(String playerId) async {
    try {
      await _api?.resumePlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Resume player', e);
      rethrow;
    }
  }

  Future<void> nextTrack(String playerId) async {
    try {
      await _api?.nextTrack(playerId);
    } catch (e) {
      ErrorHandler.logError('Next track', e);
      rethrow;
    }
  }

  Future<void> previousTrack(String playerId) async {
    try {
      await _api?.previousTrack(playerId);
    } catch (e) {
      ErrorHandler.logError('Previous track', e);
      rethrow;
    }
  }

  Future<void> stopPlayer(String playerId) async {
    try {
      await _api?.stopPlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Stop player', e);
      rethrow;
    }
  }

  Future<void> togglePower(String playerId) async {
    try {
      _logger.log('🔋 togglePower called for playerId: $playerId');

      // Check if this is the local builtin player
      final localPlayerId = await SettingsService.getBuiltinPlayerId();
      final isLocalPlayer = localPlayerId != null && playerId == localPlayerId;

      _logger.log('🔋 Is local builtin player: $isLocalPlayer (local ID: $localPlayerId)');

      if (isLocalPlayer) {
        // For builtin player, manage power state locally
        _logger.log('🔋 Handling power toggle LOCALLY for builtin player');

        // Toggle the local power state
        _isLocalPlayerPowered = !_isLocalPlayerPowered;
        _logger.log('🔋 Local player power set to: $_isLocalPlayerPowered');

        // If powering off, stop playback
        if (!_isLocalPlayerPowered) {
          _logger.log('🔋 Stopping playback because powered off');
          await _localPlayer.stop();
        }

        // Report the new state to the server immediately
        await _reportLocalPlayerState();

        // Refresh player list to update UI
        await refreshPlayers();
      } else {
        // For regular MA players, send power command to server
        _logger.log('🔋 Sending power command to server for regular player');

        final player = _availablePlayers.firstWhere(
          (p) => p.playerId == playerId,
          orElse: () => _selectedPlayer != null && _selectedPlayer!.playerId == playerId
              ? _selectedPlayer!
              : throw Exception("Player not found"),
        );

        _logger.log('🔋 Current power state: ${player.powered}, will set to: ${!player.powered}');

        // Toggle the state
        await _api?.setPower(playerId, !player.powered);

        _logger.log('🔋 setPower command sent successfully');

        // Immediately refresh players to update UI
        await refreshPlayers();
      }
    } catch (e) {
      _logger.log('🔋 ERROR in togglePower: $e');
      ErrorHandler.logError('Toggle power', e);
      // Don't rethrow to avoid crashing UI, just log
    }
  }

  Future<void> setVolume(String playerId, int volumeLevel) async {
    try {
      await _api?.setVolume(playerId, volumeLevel);
      // Don't refresh immediately - let automatic polling pick up the change
      // This prevents the slider from snapping back before the server updates
    } catch (e) {
      ErrorHandler.logError('Set volume', e);
      rethrow;
    }
  }

  Future<void> setMute(String playerId, bool muted) async {
    try {
      await _api?.setMute(playerId, muted);
      // Refresh player state to get updated mute status
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Set mute', e);
      rethrow;
    }
  }

  Future<void> seek(String playerId, int position) async {
    try {
      await _api?.seek(playerId, position);
      // Player state will be updated on next poll
    } catch (e) {
      ErrorHandler.logError('Seek', e);
      rethrow;
    }
  }

  Future<void> toggleShuffle(String queueId) async {
    try {
      await _api?.toggleShuffle(queueId);
      // Queue state will be updated on next poll
    } catch (e) {
      ErrorHandler.logError('Toggle shuffle', e);
      rethrow;
    }
  }

  Future<void> setRepeatMode(String queueId, String mode) async {
    try {
      await _api?.setRepeatMode(queueId, mode);
      // Queue state will be updated on next poll
    } catch (e) {
      ErrorHandler.logError('Set repeat mode', e);
      rethrow;
    }
  }

  /// Cycle through repeat modes: off -> all -> one -> off
  Future<void> cycleRepeatMode(String queueId, String? currentMode) async {
    String nextMode;
    switch (currentMode) {
      case 'off':
      case null:
        nextMode = 'all';
        break;
      case 'all':
        nextMode = 'one';
        break;
      case 'one':
        nextMode = 'off';
        break;
      default:
        nextMode = 'off';
    }
    await setRepeatMode(queueId, nextMode);
  }

  // ============================================================================
  // END PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  // ============================================================================
  // PLAYER SELECTION
  // ============================================================================

  /// Load available players and auto-select one
  Future<void> _loadAndSelectPlayers({bool forceRefresh = false}) async {
    try {
      // Check cache first
      final now = DateTime.now();
      if (!forceRefresh &&
          _playersLastFetched != null &&
          _availablePlayers.isNotEmpty &&
          now.difference(_playersLastFetched!) < Timings.playersCacheDuration) {
        return;
      }

      final allPlayers = await getPlayers();
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();

      // Debug: Log all players returned from API
      _logger.log('🎛️ getPlayers returned ${allPlayers.length} players:');
      for (var p in allPlayers) {
        _logger.log('   - ${p.name} (${p.playerId}) available=${p.available} powered=${p.powered}');
      }

      // Filter out unavailable players and legacy ghosts
      // Unavailable players are ghost players from old installations that clutter the list
      // Users can still see them in MA's web UI if needed

      int filteredCount = 0;

      _availablePlayers = allPlayers.where((player) {
        final nameLower = player.name.toLowerCase();

        // Filter out legacy "Music Assistant Mobile" ghosts
        if (nameLower.contains('music assistant mobile')) {
          filteredCount++;
          return false;
        }

        // Filter out unavailable players (ghost players from old installations)
        // Exception: Keep our own player even if temporarily unavailable
        if (!player.available) {
          if (builtinPlayerId != null && player.playerId == builtinPlayerId) {
            // This is our player - keep it even if unavailable
            return true;
          }
          // Other unavailable players are ghosts - hide them
          filteredCount++;
          return false;
        }

        return true;
      }).toList();

      _playersLastFetched = DateTime.now();

      _logger.log('🎛️ After filtering: ${_availablePlayers.length} players available');

      if (_availablePlayers.isNotEmpty) {
        // Smart player selection logic:
        // 1. If a player is already selected and still available, keep it (ALWAYS)
        // 2. Only auto-select a player if none is currently selected
        // 3. Prefer a playing player, then first available player

        Player? playerToSelect;

        // Keep current selection if still valid - ALWAYS prefer this
        if (_selectedPlayer != null) {
          final stillAvailable = _availablePlayers.any(
            (p) => p.playerId == _selectedPlayer!.playerId && p.available,
          );
          if (stillAvailable) {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.playerId == _selectedPlayer!.playerId,
            );
          }
        }

        // Only auto-select if NO player is currently selected
        if (playerToSelect == null) {
          // Priority 1: Local player (this device) - always prefer this
          if (builtinPlayerId != null) {
            try {
              playerToSelect = _availablePlayers.firstWhere(
                (p) => p.playerId == builtinPlayerId && p.available,
              );
              _logger.log('📱 Auto-selected local player: ${playerToSelect?.name}');
            } catch (e) {
              // Local player not found or not available
            }
          }

          // Priority 2: A currently playing player
          if (playerToSelect == null) {
            try {
              playerToSelect = _availablePlayers.firstWhere(
                (p) => p.state == 'playing' && p.available,
              );
            } catch (e) {
              // No playing player found
            }
          }

          // Priority 3: First available player
          if (playerToSelect == null) {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.available,
              orElse: () => _availablePlayers.first,
            );
          }
        }

        selectPlayer(playerToSelect);
      }

      // Don't call notifyListeners here - selectPlayer already does it
    } catch (e) {
      ErrorHandler.logError('Load and select players', e);
    }
  }

  /// Select a player for playback
  void selectPlayer(Player player, {bool skipNotify = false}) {
    _selectedPlayer = player;

    // Start polling for player state
    _startPlayerStatePolling();

    if (!skipNotify) {
      notifyListeners();
    }
  }

  /// Start polling for selected player's current state
  void _startPlayerStatePolling() {
    _playerStateTimer?.cancel();

    if (_selectedPlayer == null) return;

    // Poll at configured interval for better performance
    _playerStateTimer = Timer.periodic(Timings.playerPollingInterval, (_) async {
      try {
        await _updatePlayerState();
      } catch (e) {
        _logger.log('Error updating player state (will retry): $e');
      }
    });

    // Also update immediately
    _updatePlayerState();
  }

  /// Update the selected player's current state
  Future<void> _updatePlayerState() async {
    if (_selectedPlayer == null || _api == null) return;

    try {
      bool stateChanged = false;

      // Fetch only the selected player's state instead of all players
      final allPlayers = await getPlayers();
      final updatedPlayer = allPlayers.firstWhere(
        (p) => p.playerId == _selectedPlayer!.playerId,
        orElse: () => _selectedPlayer!,
      );

      // Check if player state actually changed
      if (updatedPlayer.state != _selectedPlayer!.state ||
          updatedPlayer.volumeLevel != _selectedPlayer!.volumeLevel ||
          updatedPlayer.volumeMuted != _selectedPlayer!.volumeMuted ||
          updatedPlayer.available != _selectedPlayer!.available) {
        _selectedPlayer = updatedPlayer;
        stateChanged = true;
      }

      // Only show tracks if player is available and not idle
      final shouldShowTrack = _selectedPlayer!.available &&
                             (_selectedPlayer!.state == 'playing' || _selectedPlayer!.state == 'paused');

      if (!shouldShowTrack) {
        // Clear track if player is unavailable or idle
        if (_currentTrack != null) {
          _currentTrack = null;
          stateChanged = true;
        }

        if (stateChanged) {
          notifyListeners();
        }
        return;
      }

      // Get the player's queue
      final queue = await getQueue(_selectedPlayer!.playerId);

      if (queue != null && queue.currentItem != null) {
        // Only update if track actually changed
        if (_currentTrack == null ||
            _currentTrack!.uri != queue.currentItem!.track.uri ||
            _currentTrack!.name != queue.currentItem!.track.name) {
          _currentTrack = queue.currentItem!.track;
          stateChanged = true;

          // Update notification with new track info (only for local player)
          final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
          if (builtinPlayerId != null && _selectedPlayer!.playerId == builtinPlayerId) {
            final track = _currentTrack!;
            final artworkUrl = _api?.getImageUrl(track, size: 512);
            _localPlayer.updateNotification(
              id: track.uri ?? track.itemId,
              title: track.name,
              artist: track.artistsString,
              album: track.album?.name,
              artworkUrl: artworkUrl,
              duration: track.duration,
            );
          }
        }
      } else {
        if (_currentTrack != null) {
          // Clear current track if queue is empty
          _currentTrack = null;
          stateChanged = true;
        }
      }

      // Only notify if something actually changed
      if (stateChanged) {
        notifyListeners();
      }
    } catch (e) {
      _logger.log('❌ Error updating player state: $e');
    }
  }

  /// Control the selected player
  Future<void> playPauseSelectedPlayer() async {
    if (_selectedPlayer == null) {
      return;
    }

    if (_selectedPlayer!.isPlaying) {
      await pausePlayer(_selectedPlayer!.playerId);
    } else {
      await resumePlayer(_selectedPlayer!.playerId);
    }

    // Refresh player state immediately
    await refreshPlayers();
  }

  Future<void> nextTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await nextTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await _updatePlayerState();
  }

  Future<void> previousTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await previousTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await _updatePlayerState();
  }

  /// Refresh the list of available players
  Future<void> refreshPlayers() async {
    final previousState = _selectedPlayer?.state;
    final previousVolume = _selectedPlayer?.volumeLevel;

    await _loadAndSelectPlayers(forceRefresh: true);

    // Update the selected player with fresh data
    bool stateChanged = false;
    if (_selectedPlayer != null && _availablePlayers.isNotEmpty) {
      try {
        final updatedPlayer = _availablePlayers.firstWhere(
          (p) => p.playerId == _selectedPlayer!.playerId,
        );

        // Check if state actually changed
        if (updatedPlayer.state != previousState ||
            updatedPlayer.volumeLevel != previousVolume) {
          stateChanged = true;
        }

        _selectedPlayer = updatedPlayer;
      } catch (e) {
        // Selected player no longer available
        stateChanged = true;
      }
    }

    // Only notify if state changed
    if (stateChanged) {
      notifyListeners();
    }
  }

  // ============================================================================
  // END PLAYER SELECTION
  // ============================================================================

  /// Check connection and reconnect if needed (called when app resumes)
  Future<void> checkAndReconnect() async {
    _logger.log('🔄 checkAndReconnect called - state: $_connectionState');

    if (_serverUrl == null) {
      _logger.log('🔄 No server URL saved, skipping reconnect');
      return;
    }

    // Check if we're disconnected or in error state
    if (_connectionState != MAConnectionState.connected) {
      _logger.log('🔄 Not connected, attempting reconnect to $_serverUrl');
      try {
        await connectToServer(_serverUrl!);
        _logger.log('🔄 Reconnection successful');
      } catch (e) {
        _logger.log('🔄 Reconnection failed: $e');
        // Reconnection failed, will try again later
      }
    } else {
      // We think we're connected - verify by refreshing players
      _logger.log('🔄 Already connected, verifying connection...');
      try {
        await refreshPlayers();
        _logger.log('🔄 Connection verified, players refreshed');
      } catch (e) {
        _logger.log('🔄 Connection verification failed, reconnecting: $e');
        // Connection might be stale, try reconnecting
        try {
          await connectToServer(_serverUrl!);
        } catch (reconnectError) {
          _logger.log('🔄 Reconnection failed: $reconnectError');
        }
      }
    }
  }

  @override
  void dispose() {
    _playerStateTimer?.cancel();
    _api?.dispose();
    super.dispose();
  }
}
