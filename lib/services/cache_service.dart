import 'dart:convert';
import '../models/media_item.dart';
import '../models/recommendation_folder.dart';
import '../models/player.dart';
import '../services/debug_logger.dart';
import '../services/database_service.dart';
import '../constants/timings.dart';

/// Centralized cache service for all app data caching
/// This is a non-notifying service - it just stores and retrieves cached data
class CacheService {
  final DebugLogger _logger = DebugLogger();
  bool _homeRowsLoaded = false;

  // Cache size limits to prevent unbounded memory growth
  static const int _maxDetailCacheSize = 50; // Max albums/playlists/artists cached
  static const int _maxSearchCacheSize = 20; // Max search queries cached
  static const int _maxPlayerTrackCacheSize = 30; // Max player track associations

  // Home screen row caching
  List<Album>? _cachedRecentAlbums;
  List<Artist>? _cachedDiscoverArtists;
  List<Album>? _cachedDiscoverAlbums;
  List<RecommendationFolder>? _cachedExternalMixes;
  List<Audiobook>? _cachedInProgressAudiobooks;
  List<Audiobook>? _cachedDiscoverAudiobooks;
  List<AudiobookSeries>? _cachedDiscoverSeries;
  DateTime? _recentAlbumsLastFetched;
  DateTime? _discoverArtistsLastFetched;
  DateTime? _discoverAlbumsLastFetched;
  DateTime? _externalMixesLastFetched;
  DateTime? _inProgressAudiobooksLastFetched;
  DateTime? _discoverAudiobooksLastFetched;
  DateTime? _discoverSeriesLastFetched;

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

  // Player list caching
  List<Player>? _cachedPlayers;
  Player? _cachedSelectedPlayer;
  DateTime? _playersLastFetched;

  // Player track cache (for smooth swipe transitions)
  final Map<String, Track?> _playerTrackCache = {};
  final Map<String, DateTime> _playerTrackCacheTime = {};

  // ============================================================================
  // HOME SCREEN ROW CACHING
  // ============================================================================

  /// Check if recent albums cache is valid
  bool isRecentAlbumsCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _cachedRecentAlbums != null &&
        _recentAlbumsLastFetched != null &&
        now.difference(_recentAlbumsLastFetched!) < Timings.homeRowCacheDuration;
  }

  /// Get cached recent albums
  List<Album>? getCachedRecentAlbums() => _cachedRecentAlbums;

  /// Set cached recent albums
  void setCachedRecentAlbums(List<Album> albums) {
    _cachedRecentAlbums = albums;
    _recentAlbumsLastFetched = DateTime.now();
    _logger.log('✅ Cached ${albums.length} recent albums');
    // Persist to database for instant load on next launch
    _persistHomeRowToDatabase('recent_albums', albums.map((a) => a.toJson()).toList());
  }

  /// Check if discover artists cache is valid
  bool isDiscoverArtistsCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _cachedDiscoverArtists != null &&
        _discoverArtistsLastFetched != null &&
        now.difference(_discoverArtistsLastFetched!) < Timings.homeRowCacheDuration;
  }

  /// Get cached discover artists
  List<Artist>? getCachedDiscoverArtists() => _cachedDiscoverArtists;

  /// Set cached discover artists
  void setCachedDiscoverArtists(List<Artist> artists) {
    _cachedDiscoverArtists = artists;
    _discoverArtistsLastFetched = DateTime.now();
    _logger.log('✅ Cached ${artists.length} discover artists');
    // Persist to database for instant load on next launch
    _persistHomeRowToDatabase('discover_artists', artists.map((a) => a.toJson()).toList());
  }

  /// Check if discover albums cache is valid
  bool isDiscoverAlbumsCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _cachedDiscoverAlbums != null &&
        _discoverAlbumsLastFetched != null &&
        now.difference(_discoverAlbumsLastFetched!) < Timings.homeRowCacheDuration;
  }

  /// Get cached discover albums
  List<Album>? getCachedDiscoverAlbums() => _cachedDiscoverAlbums;

  /// Set cached discover albums
  void setCachedDiscoverAlbums(List<Album> albums) {
    _cachedDiscoverAlbums = albums;
    _discoverAlbumsLastFetched = DateTime.now();
    _logger.log('✅ Cached ${albums.length} discover albums');
    // Persist to database for instant load on next launch
    _persistHomeRowToDatabase('discover_albums', albums.map((a) => a.toJson()).toList());
  }

  /// Check if external mixes cache is valid
  bool isExternalMixesCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _cachedExternalMixes != null &&
        _externalMixesLastFetched != null &&
        now.difference(_externalMixesLastFetched!) < Timings.homeRowCacheDuration;
  }

  /// Get cached external mixes
  List<RecommendationFolder>? getCachedExternalMixes() => _cachedExternalMixes;

  /// Set cached external mixes
  void setCachedExternalMixes(List<RecommendationFolder> mixes) {
    _cachedExternalMixes = mixes;
    _externalMixesLastFetched = DateTime.now();
    _logger.log('✅ Cached ${mixes.length} external mix shelves');
    // Persist to database for instant load on next launch
    _persistHomeRowToDatabase('external_mixes', mixes.map((m) => m.toJson()).toList());
  }

  /// Check if in-progress audiobooks cache is valid
  bool isInProgressAudiobooksCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _cachedInProgressAudiobooks != null &&
        _inProgressAudiobooksLastFetched != null &&
        now.difference(_inProgressAudiobooksLastFetched!) < Timings.homeRowCacheDuration;
  }

  /// Get cached in-progress audiobooks
  List<Audiobook>? getCachedInProgressAudiobooks() => _cachedInProgressAudiobooks;

  /// Set cached in-progress audiobooks
  void setCachedInProgressAudiobooks(List<Audiobook> audiobooks) {
    _cachedInProgressAudiobooks = audiobooks;
    _inProgressAudiobooksLastFetched = DateTime.now();
    _logger.log('✅ Cached ${audiobooks.length} in-progress audiobooks');
  }

  /// Check if discover audiobooks cache is valid
  bool isDiscoverAudiobooksCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _cachedDiscoverAudiobooks != null &&
        _discoverAudiobooksLastFetched != null &&
        now.difference(_discoverAudiobooksLastFetched!) < Timings.homeRowCacheDuration;
  }

  /// Get cached discover audiobooks
  List<Audiobook>? getCachedDiscoverAudiobooks() => _cachedDiscoverAudiobooks;

  /// Set cached discover audiobooks
  void setCachedDiscoverAudiobooks(List<Audiobook> audiobooks) {
    _cachedDiscoverAudiobooks = audiobooks;
    _discoverAudiobooksLastFetched = DateTime.now();
    _logger.log('✅ Cached ${audiobooks.length} discover audiobooks');
  }

  /// Check if discover series cache is valid
  bool isDiscoverSeriesCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _cachedDiscoverSeries != null &&
        _discoverSeriesLastFetched != null &&
        now.difference(_discoverSeriesLastFetched!) < Timings.homeRowCacheDuration;
  }

  /// Get cached discover series
  List<AudiobookSeries>? getCachedDiscoverSeries() => _cachedDiscoverSeries;

  /// Set cached discover series
  void setCachedDiscoverSeries(List<AudiobookSeries> series) {
    _cachedDiscoverSeries = series;
    _discoverSeriesLastFetched = DateTime.now();
    _logger.log('✅ Cached ${series.length} discover series');
  }

  /// Invalidate audiobook caches
  void invalidateAudiobookCaches() {
    _cachedInProgressAudiobooks = null;
    _inProgressAudiobooksLastFetched = null;
    _cachedDiscoverAudiobooks = null;
    _discoverAudiobooksLastFetched = null;
    _cachedDiscoverSeries = null;
    _discoverSeriesLastFetched = null;
    _logger.log('🗑️ Audiobook caches invalidated');
  }

  /// Invalidate home screen cache (call on pull-to-refresh)
  void invalidateHomeCache() {
    _recentAlbumsLastFetched = null;
    _discoverArtistsLastFetched = null;
    _discoverAlbumsLastFetched = null;
    _externalMixesLastFetched = null;
    _inProgressAudiobooksLastFetched = null;
    _discoverAudiobooksLastFetched = null;
    _discoverSeriesLastFetched = null;
    _logger.log('🗑️ Home screen cache invalidated');
  }

  /// Invalidate home album caches (call when albums are added/removed from library)
  void invalidateHomeAlbumCaches() {
    _cachedRecentAlbums = null;
    _recentAlbumsLastFetched = null;
    _cachedDiscoverAlbums = null;
    _discoverAlbumsLastFetched = null;
    _logger.log('🗑️ Home album caches invalidated');
  }

  /// Invalidate home artist caches (call when artists are added/removed from library)
  void invalidateHomeArtistCaches() {
    _cachedDiscoverArtists = null;
    _discoverArtistsLastFetched = null;
    _logger.log('🗑️ Home artist caches invalidated');
  }

  /// Clear discover caches (call when provider filter changes)
  /// This ensures discover rows are refetched with the new provider filter
  void clearDiscoverCaches() {
    _cachedDiscoverArtists = null;
    _discoverArtistsLastFetched = null;
    _cachedDiscoverAlbums = null;
    _discoverAlbumsLastFetched = null;
    _cachedExternalMixes = null;
    _externalMixesLastFetched = null;
    _cachedRecentAlbums = null;
    _recentAlbumsLastFetched = null;
    _searchCache.clear();
    _searchCacheTime.clear();
    _logger.log('🗑️ Discover caches cleared for provider filter change');
  }

  // ============================================================================
  // DETAIL SCREEN CACHING
  // ============================================================================

  /// Check if album tracks cache is valid
  bool isAlbumTracksCacheValid(String cacheKey, {bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    final cacheTime = _albumTracksCacheTime[cacheKey];
    return _albumTracksCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < const Duration(minutes: 5);
  }

  /// Get cached album tracks
  List<Track>? getCachedAlbumTracks(String cacheKey) => _albumTracksCache[cacheKey];

  /// Set cached album tracks
  void setCachedAlbumTracks(String cacheKey, List<Track> tracks) {
    _albumTracksCache[cacheKey] = tracks;
    _albumTracksCacheTime[cacheKey] = DateTime.now();
    _evictOldestEntries(_albumTracksCache, _albumTracksCacheTime, _maxDetailCacheSize);
    _logger.log('✅ Cached ${tracks.length} tracks for album $cacheKey');
  }

  /// Invalidate album tracks cache for a specific album
  void invalidateAlbumTracksCache(String albumId) {
    _albumTracksCache.remove(albumId);
    _albumTracksCacheTime.remove(albumId);
  }

  /// Invalidate all album tracks caches (call when tracks are added/removed from library)
  void invalidateAllAlbumTracksCaches() {
    _albumTracksCache.clear();
    _albumTracksCacheTime.clear();
    _logger.log('🗑️ All album tracks caches invalidated');
  }

  /// Check if playlist tracks cache is valid
  bool isPlaylistTracksCacheValid(String cacheKey, {bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    final cacheTime = _playlistTracksCacheTime[cacheKey];
    return _playlistTracksCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < const Duration(minutes: 5);
  }

  /// Get cached playlist tracks
  List<Track>? getCachedPlaylistTracks(String cacheKey) => _playlistTracksCache[cacheKey];

  /// Set cached playlist tracks
  void setCachedPlaylistTracks(String cacheKey, List<Track> tracks) {
    _playlistTracksCache[cacheKey] = tracks;
    _playlistTracksCacheTime[cacheKey] = DateTime.now();
    _evictOldestEntries(_playlistTracksCache, _playlistTracksCacheTime, _maxDetailCacheSize);
    _logger.log('✅ Cached ${tracks.length} tracks for playlist $cacheKey');
  }

  /// Invalidate playlist tracks cache for a specific playlist
  void invalidatePlaylistTracksCache(String playlistId) {
    _playlistTracksCache.remove(playlistId);
    _playlistTracksCacheTime.remove(playlistId);
  }

  /// Invalidate all playlist tracks caches (call when tracks are added/removed from library)
  void invalidateAllPlaylistTracksCaches() {
    _playlistTracksCache.clear();
    _playlistTracksCacheTime.clear();
    _logger.log('🗑️ All playlist tracks caches invalidated');
  }

  /// Check if artist albums cache is valid
  bool isArtistAlbumsCacheValid(String cacheKey, {bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    final cacheTime = _artistAlbumsCacheTime[cacheKey];
    return _artistAlbumsCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < Timings.homeRowCacheDuration;
  }

  /// Get cached artist albums
  List<Album>? getCachedArtistAlbums(String cacheKey) => _artistAlbumsCache[cacheKey];

  /// Set cached artist albums
  void setCachedArtistAlbums(String cacheKey, List<Album> albums) {
    _artistAlbumsCache[cacheKey] = albums;
    _artistAlbumsCacheTime[cacheKey] = DateTime.now();
    _evictOldestEntries(_artistAlbumsCache, _artistAlbumsCacheTime, _maxDetailCacheSize);
    _logger.log('✅ Cached ${albums.length} albums for artist $cacheKey');
  }

  /// Invalidate all artist albums caches (call when albums are added/removed from library)
  void invalidateArtistAlbumsCache() {
    _artistAlbumsCache.clear();
    _artistAlbumsCacheTime.clear();
    _logger.log('🗑️ Artist albums cache invalidated');
  }

  // ============================================================================
  // SEARCH CACHING
  // ============================================================================

  /// Check if search cache is valid
  bool isSearchCacheValid(String cacheKey, {bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    final cacheTime = _searchCacheTime[cacheKey];
    return _searchCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < Timings.homeRowCacheDuration;
  }

  /// Get cached search results
  Map<String, List<MediaItem>>? getCachedSearchResults(String cacheKey) => _searchCache[cacheKey];

  /// Set cached search results
  void setCachedSearchResults(String cacheKey, Map<String, List<MediaItem>> results) {
    _searchCache[cacheKey] = results;
    _searchCacheTime[cacheKey] = DateTime.now();
    _evictOldestEntries(_searchCache, _searchCacheTime, _maxSearchCacheSize);
    _logger.log('✅ Cached search results for "$cacheKey"');
  }

  /// Invalidate all search cache (call when library items change)
  void invalidateSearchCache() {
    _searchCache.clear();
    _searchCacheTime.clear();
    _logger.log('🗑️ Search cache invalidated');
  }

  // ============================================================================
  // PLAYER CACHING
  // ============================================================================

  /// Check if players cache is valid
  bool isPlayersCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _playersLastFetched != null &&
        now.difference(_playersLastFetched!) < Timings.playersCacheDuration;
  }

  /// Update players cache timestamp
  void updatePlayersLastFetched() {
    _playersLastFetched = DateTime.now();
  }

  /// Get cached players list
  List<Player>? getCachedPlayers() => _cachedPlayers;

  /// Set cached players list
  void setCachedPlayers(List<Player> players) {
    _cachedPlayers = players;
    _playersLastFetched = DateTime.now();
  }

  /// Get cached selected player
  Player? getCachedSelectedPlayer() => _cachedSelectedPlayer;

  /// Set cached selected player
  void setCachedSelectedPlayer(Player? player) {
    _cachedSelectedPlayer = player;
  }

  /// Check if we have cached players (for instant UI display on app resume)
  bool get hasCachedPlayers => _cachedPlayers != null && _cachedPlayers!.isNotEmpty;

  /// Get cached track for a player (used for smooth swipe transitions)
  Track? getCachedTrackForPlayer(String playerId) => _playerTrackCache[playerId];

  /// Get all player IDs that have cached tracks
  Iterable<String> getAllCachedPlayerIds() => _playerTrackCache.keys;

  /// Set cached track for a player
  void setCachedTrackForPlayer(String playerId, Track? track) {
    _playerTrackCache[playerId] = track;
    _playerTrackCacheTime[playerId] = DateTime.now();
    _evictOldestEntries(_playerTrackCache, _playerTrackCacheTime, _maxPlayerTrackCacheSize);
  }

  /// Clear cached track for a player (e.g., when external source is active)
  void clearCachedTrackForPlayer(String playerId) {
    _playerTrackCache.remove(playerId);
    _playerTrackCacheTime.remove(playerId);
  }

  // ============================================================================
  // CLEAR ALL
  // ============================================================================

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
    _playerTrackCache.clear();
    _playerTrackCacheTime.clear();
    _logger.log('🗑️ All detail caches cleared');
  }

  /// Clear all caches
  void clearAll() {
    invalidateHomeCache();
    clearAllDetailCaches();
    _cachedPlayers = null;
    _cachedSelectedPlayer = null;
    _playersLastFetched = null;
  }

  // ============================================================================
  // DATABASE PERSISTENCE FOR HOME ROWS
  // ============================================================================

  /// Load home row data from database for instant display on startup
  Future<void> loadHomeRowsFromDatabase() async {
    if (_homeRowsLoaded) return;
    _homeRowsLoaded = true;

    try {
      if (!DatabaseService.instance.isInitialized) return;

      // Load recent albums
      final recentData = await DatabaseService.instance.getHomeRowCache('recent_albums');
      if (recentData != null) {
        try {
          final items = (jsonDecode(recentData.itemsJson) as List)
              .map((json) => Album.fromJson(json as Map<String, dynamic>))
              .toList();
          _cachedRecentAlbums = items;
          _recentAlbumsLastFetched = recentData.lastUpdated;
          _logger.log('📦 Loaded ${items.length} recent albums from database');
        } catch (e) {
          _logger.log('⚠️ Failed to parse recent albums: $e');
        }
      }

      // Load discover artists
      final artistsData = await DatabaseService.instance.getHomeRowCache('discover_artists');
      if (artistsData != null) {
        try {
          final items = (jsonDecode(artistsData.itemsJson) as List)
              .map((json) => Artist.fromJson(json as Map<String, dynamic>))
              .toList();
          _cachedDiscoverArtists = items;
          _discoverArtistsLastFetched = artistsData.lastUpdated;
          _logger.log('📦 Loaded ${items.length} discover artists from database');
        } catch (e) {
          _logger.log('⚠️ Failed to parse discover artists: $e');
        }
      }

      // Load discover albums
      final albumsData = await DatabaseService.instance.getHomeRowCache('discover_albums');
      if (albumsData != null) {
        try {
          final items = (jsonDecode(albumsData.itemsJson) as List)
              .map((json) => Album.fromJson(json as Map<String, dynamic>))
              .toList();
          _cachedDiscoverAlbums = items;
          _discoverAlbumsLastFetched = albumsData.lastUpdated;
          _logger.log('📦 Loaded ${items.length} discover albums from database');
        } catch (e) {
          _logger.log('⚠️ Failed to parse discover albums: $e');
        }
      }

      // Load external mixes
      final mixesData = await DatabaseService.instance.getHomeRowCache('external_mixes');
      if (mixesData != null) {
        try {
          final items = (jsonDecode(mixesData.itemsJson) as List)
              .map((json) => RecommendationFolder.fromJson(json as Map<String, dynamic>))
              .toList();
          _cachedExternalMixes = items;
          _externalMixesLastFetched = mixesData.lastUpdated;
          _logger.log('📦 Loaded ${items.length} external mix shelves from database');
        } catch (e) {
          _logger.log('⚠️ Failed to parse external mixes: $e');
        }
      }
    } catch (e) {
      _logger.log('⚠️ Error loading home rows from database: $e');
    }
  }

  /// Persist home row data to database (fire-and-forget)
  void _persistHomeRowToDatabase(String rowType, List<Map<String, dynamic>> items) {
    () async {
      try {
        if (!DatabaseService.instance.isInitialized) return;
        await DatabaseService.instance.saveHomeRowCache(rowType, jsonEncode(items));
        _logger.log('💾 Persisted $rowType to database');
      } catch (e) {
        _logger.log('⚠️ Failed to persist $rowType: $e');
      }
    }();
  }

  // ============================================================================
  // LRU CACHE EVICTION
  // ============================================================================

  /// Evict oldest entries from cache maps to enforce size limit (LRU eviction)
  /// Uses the timestamp map to determine which entries are oldest
  void _evictOldestEntries<K, V>(
    Map<K, V> cache,
    Map<K, DateTime> cacheTime,
    int maxSize,
  ) {
    if (cache.length <= maxSize) return;

    // Sort keys by timestamp (oldest first)
    final sortedKeys = cacheTime.keys.toList()
      ..sort((a, b) => (cacheTime[a] ?? DateTime.now())
          .compareTo(cacheTime[b] ?? DateTime.now()));

    // Remove oldest entries until we're at maxSize
    final keysToRemove = sortedKeys.take(cache.length - maxSize);
    for (final key in keysToRemove) {
      cache.remove(key);
      cacheTime.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      _logger.log('🗑️ LRU evicted ${keysToRemove.length} cache entries');
    }
  }
}
