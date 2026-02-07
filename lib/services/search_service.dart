import '../models/media_item.dart';
import '../services/cache_service.dart';
import '../services/debug_logger.dart';
import '../services/music_assistant_api.dart';

/// Service for handling search operations with caching.
///
/// Extracted from MusicAssistantProvider to isolate search logic.
class SearchService {
  final MusicAssistantAPI? _api;
  final CacheService _cacheService;
  final DebugLogger _logger;

  SearchService({
    required MusicAssistantAPI? api,
    required CacheService cacheService,
    required DebugLogger logger,
  })  : _api = api,
        _cacheService = cacheService,
        _logger = logger;

  /// Search with caching support.
  ///
  /// Returns cached results if available and not expired.
  /// Otherwise fetches from API and caches the results.
  Future<Map<String, List<MediaItem>>> searchWithCache(
    String query, {
    bool forceRefresh = false,
    bool libraryOnly = false,
  }) async {
    final baseKey = query.toLowerCase().trim();
    if (baseKey.isEmpty) {
      return _emptySearchResults();
    }

    // Include libraryOnly in cache key to separate results
    final cacheKey = libraryOnly ? '$baseKey:library' : baseKey;

    if (_cacheService.isSearchCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached search results for "$query" (libraryOnly: $libraryOnly)');
      return _cacheService.getCachedSearchResults(cacheKey)!;
    }

    if (_api == null) {
      return _cacheService.getCachedSearchResults(cacheKey) ?? _emptySearchResults();
    }

    try {
      _logger.log('🔄 Searching for "$query" (libraryOnly: $libraryOnly)...');
      final results = await _api!.search(query, libraryOnly: libraryOnly);

      final cachedResults = <String, List<MediaItem>>{
        'artists': results['artists'] ?? [],
        'albums': results['albums'] ?? [],
        'tracks': results['tracks'] ?? [],
        'playlists': results['playlists'] ?? [],
        'audiobooks': results['audiobooks'] ?? [],
      };

      _cacheService.setCachedSearchResults(cacheKey, cachedResults);
      _logger.log('✅ Cached search results for "$query"');
      return cachedResults;
    } catch (e) {
      _logger.log('❌ Search failed: $e');
      return _cacheService.getCachedSearchResults(cacheKey) ?? _emptySearchResults();
    }
  }

  /// Clear all search and detail caches.
  void clearAllDetailCaches() {
    _cacheService.clearAllDetailCaches();
  }

  /// Check if search cache is valid for a query.
  bool isSearchCacheValid(String query, {bool forceRefresh = false}) {
    final baseKey = query.toLowerCase().trim();
    return _cacheService.isSearchCacheValid(baseKey, forceRefresh: forceRefresh);
  }

  /// Get cached search results for a query.
  Map<String, List<MediaItem>>? getCachedSearchResults(String query, {bool libraryOnly = false}) {
    final baseKey = query.toLowerCase().trim();
    final cacheKey = libraryOnly ? '$baseKey:library' : baseKey;
    return _cacheService.getCachedSearchResults(cacheKey);
  }

  Map<String, List<MediaItem>> _emptySearchResults() {
    return {
      'artists': [],
      'albums': [],
      'tracks': [],
      'playlists': [],
      'audiobooks': [],
    };
  }
}
