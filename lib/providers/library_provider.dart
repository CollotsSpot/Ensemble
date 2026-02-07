import 'package:flutter/foundation.dart';
import '../constants/timings.dart';
import '../models/media_item.dart';
import '../services/cache_service.dart';
import '../services/debug_logger.dart';
import '../services/library_status_service.dart';
import '../services/music_assistant_api.dart';
import '../services/provider_filter_service.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';

/// Provider for library data management.
///
/// Manages:
/// - Artists, albums, tracks lists
/// - Radio stations and podcasts
/// - Library loading and refresh
/// - Provider filtering
/// - Background sync
///
/// Extracted from MusicAssistantProvider to isolate library logic.
class LibraryProvider extends ChangeNotifier {
  final MusicAssistantAPI? _api;
  final DebugLogger _logger;
  final CacheService _cacheService;
  final SettingsService? _settings;
  final ProviderFilterService _providerFilterService;

  // Library data
  List<dynamic> _artists = [];
  List<dynamic> _albums = [];
  List<dynamic> _tracks = [];
  List<dynamic> _radioStations = [];
  List<dynamic> _podcasts = [];

  // Getters
  List<dynamic> get artists => _artists;
  List<dynamic> get albums => _albums;
  List<dynamic> get tracks => _tracks;
  List<dynamic> get radioStations => _radioStations;
  List<dynamic> get podcasts => _podcasts;

  // Expose typed lists for convenience
  List<Artist> get artistList => _artists.cast<Artist>();
  List<Album> get albumList => _albums.cast<Album>();
  List<Track> get trackList => _tracks.cast<Track>();

  // Callback for when library status changes
  Function()? onLibraryChanged;

  LibraryProvider({
    required MusicAssistantAPI? api,
    required DebugLogger logger,
    required CacheService cacheService,
    SettingsService? settings,
    required ProviderFilterService providerFilterService,
  })  : _api = api,
        _logger = logger,
        _cacheService = cacheService,
        _settings = settings,
        _providerFilterService = providerFilterService;

  /// Load library data from API with caching
  Future<void> loadLibrary() async {
    if (_api == null) return;

    try {
      _logger.log('📚 Loading library from cache (instant)...');

      // Load from database cache first (instant)
      final syncService = SyncService.instance;
      if (syncService.hasCache) {
        _albums = syncService.cachedAlbums;
        _artists = syncService.cachedArtists;
        _logger.log('📦 Loaded ${_albums.length} albums, ${_artists.length} artists from cache');
        _syncLibraryStatusToService();
        notifyListeners();
      }

      // Fetch tracks from API (not cached - too many items)
      try {
        _tracks = await _api!.getTracks(
          limit: LibraryConstants.maxLibraryItems,
          providerInstanceIds: _providerIdsForApiCalls(),
        );
        _logger.log('📥 Fetched ${_tracks.length} tracks from MA');
      } catch (e) {
        _logger.log('⚠️ Failed to fetch tracks: $e');
      }

      notifyListeners();

      // Trigger background sync (non-blocking)
      _syncLibraryInBackground();
    } catch (e) {
      _logger.log('❌ Error loading library: $e');
    }
  }

  /// Load artists from library
  Future<void> loadArtists({int? limit, int? offset, String? search, String? orderBy}) async {
    if (_api == null) return;

    try {
      final artists = await _api!.getArtists(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
        albumArtistsOnly: false,
        orderBy: orderBy,
      );

      // Update SyncService cache
      SyncService.instance.updateCachedArtists(artists);

      _artists = artists;
      _syncLibraryStatusToService();
      notifyListeners();
    } catch (e) {
      _logger.log('⚠️ Failed to load artists: $e');
    }
  }

  /// Load albums from library
  Future<void> loadAlbums({int? limit, int? offset, String? search, String? artistId, String? orderBy}) async {
    if (_api == null) return;

    try {
      final albums = await _api!.getAlbums(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
        artistId: artistId,
        orderBy: orderBy,
      );

      // Update SyncService cache
      SyncService.instance.updateCachedAlbums(albums);

      _albums = albums;
      _syncLibraryStatusToService();
      notifyListeners();
    } catch (e) {
      _logger.log('⚠️ Failed to load albums: $e');
    }
  }

  /// Load radio stations
  Future<void> loadRadioStations({String? orderBy}) async {
    if (_api == null) return;

    try {
      _radioStations = await _api!.getRadioStations(limit: 100, orderBy: orderBy);
      notifyListeners();
    } catch (e) {
      _logger.log('⚠️ Failed to load radio stations: $e');
    }
  }

  /// Load podcasts
  Future<void> loadPodcasts({String? orderBy}) async {
    if (_api == null) return;

    try {
      _podcasts = await _api!.getPodcasts(limit: 100, orderBy: orderBy);
      _logger.log('🎙️ Loaded ${_podcasts.length} podcasts');
      notifyListeners();
    } catch (e) {
      _logger.log('⚠️ Failed to load podcasts: $e');
    }
  }

  /// Get playlists with provider filtering
  Future<List<Playlist>> getPlaylists({int? limit, bool? favoriteOnly, String? orderBy}) async {
    if (_api == null) return [];
    try {
      final playlists = await _api!.getPlaylists(limit: limit, favoriteOnly: favoriteOnly, orderBy: orderBy);
      return _providerFilterService.filterByProvider(playlists);
    } catch (e) {
      _logger.log('❌ Failed to fetch playlists: $e');
      return [];
    }
  }

  /// Get audiobooks with provider filtering
  Future<List<Audiobook>> getAudiobooks({int? limit, bool? favoriteOnly}) async {
    if (_api == null) return [];
    try {
      final audiobooks = await _api!.getAudiobooks(limit: limit, favoriteOnly: favoriteOnly ?? false);
      return _providerFilterService.filterByProvider(audiobooks);
    } catch (e) {
      _logger.log('❌ Failed to fetch audiobooks: $e');
      return [];
    }
  }

  /// Sync library data in background without blocking UI
  void _syncLibraryInBackground() {
    if (_api == null) return;

    final syncService = SyncService.instance;

    // Listen for sync completion to update our lists
    void onSyncComplete() {
      if (syncService.status == SyncStatus.completed) {
        _albums = syncService.cachedAlbums;
        _artists = syncService.cachedArtists;
        _logger.log('🔄 Updated library from background sync: ${_albums.length} albums, ${_artists.length} artists');
        _syncLibraryStatusToService();
        notifyListeners();
        onLibraryChanged?.call();
      }
      syncService.removeListener(onSyncComplete);
    }

    syncService.addListener(onSyncComplete);
    syncService.syncFromApi(_api!, providerInstanceIds: _providerIdsForApiCalls());
  }

  /// Sync library status to centralized service for reactive UI updates
  void _syncLibraryStatusToService() {
    final service = LibraryStatusService.instance;

    service.syncFromLibrary(
      mediaType: 'album',
      items: _albums,
      getInLibrary: (a) => (a as Album).inLibrary,
      getFavorite: (a) => (a as Album).favorite ?? false,
      getProvider: (a) => (a as Album).provider,
      getItemId: (a) => (a as Album).itemId,
    );

    service.syncFromLibrary(
      mediaType: 'artist',
      items: _artists,
      getInLibrary: (a) => (a as Artist).inLibrary,
      getFavorite: (a) => (a as Artist).favorite ?? false,
      getProvider: (a) => (a as Artist).provider,
      getItemId: (a) => (a as Artist).itemId,
    );

    service.syncFromLibrary(
      mediaType: 'track',
      items: _tracks,
      getInLibrary: (t) => (t as Track).inLibrary,
      getFavorite: (t) => (t as Track).favorite ?? false,
      getProvider: (t) => (t as Track).provider,
      getItemId: (t) => (t as Track).itemId,
    );
  }

  /// Get provider instance IDs for API calls (respects user filter)
  List<String> _providerIdsForApiCalls() {
    // For now, always return empty list to use all available providers
    // Provider filtering can be re-enabled later with async approach
    return [];
  }

  /// Update the API reference
  void setApi(MusicAssistantAPI? api) {
    if (_api != api) {
      // Note: We don't dispose the old API here as it's managed by ConnectionProvider
      // This is just updating the reference
    }
  }

  /// Load library from cache for instant display
  Future<void> loadFromCache() async {
    try {
      final syncService = SyncService.instance;

      if (!syncService.hasCache) {
        await syncService.loadFromCache();
      }

      if (syncService.hasCache) {
        _albums = syncService.cachedAlbums;
        _artists = syncService.cachedArtists;
        _logger.log('📦 Pre-loaded library: ${_albums.length} albums, ${_artists.length} artists');
        _syncLibraryStatusToService();
        notifyListeners();
      }
    } catch (e) {
      _logger.log('⚠️ Error loading library from cache: $e');
    }
  }
}
