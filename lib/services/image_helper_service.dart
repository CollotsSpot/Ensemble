import '../models/media_item.dart';
import '../models/provider_manifest.dart';
import '../services/music_assistant_api.dart';
import '../services/metadata_service.dart';

/// Service for handling image/artwork URL generation and caching.
///
/// Extracted from MusicAssistantProvider to reduce complexity.
class ImageHelperService {
  final MusicAssistantAPI? _api;

  /// Podcast cover cache: podcastId -> best available cover URL
  /// This is populated with episode covers when podcast covers are low-res
  final Map<String, String> _podcastCoverCache = {};

  /// Callback to get cached track for a player
  final Track? Function(String playerId) getCachedTrackForPlayer;

  ImageHelperService({
    required MusicAssistantAPI? api,
    required this.getCachedTrackForPlayer,
  }) : _api = api;

  /// Get artwork URL for a media item from Music Assistant
  String? getImageUrl(MediaItem item, {int size = 256}) {
    return _api?.getImageUrl(item, size: size);
  }

  /// Get best available podcast cover URL
  ///
  /// Returns cached iTunes URL (800x800) if available, otherwise falls back to MA imageproxy.
  /// The cache is persisted to storage and loaded on app start for instant high-res display.
  String? getPodcastImageUrl(MediaItem podcast, {int size = 256}) {
    // Return cached iTunes URL if available (persisted across app launches)
    final cachedUrl = _podcastCoverCache[podcast.itemId];
    if (cachedUrl != null) {
      return cachedUrl;
    }
    // Fall back to MA imageproxy (will be replaced once iTunes fetch completes)
    return _api?.getImageUrl(podcast, size: size);
  }

  /// Get artist image URL with fallback to external sources (Deezer, Fanart.tv)
  ///
  /// Returns a Future since fallback requires async API calls.
  Future<String?> getArtistImageUrlWithFallback(Artist artist, {int size = 256}) async {
    // Try Music Assistant first
    final maUrl = _api?.getImageUrl(artist, size: size);
    if (maUrl != null) {
      return maUrl;
    }

    // Fall back to external sources (Deezer, Fanart.tv, etc.)
    return MetadataService.getArtistImageUrl(artist.name);
  }

  /// Get SVG icon for a provider domain
  ///
  /// Returns null if no icon is available.
  String? getProviderIconSvg(String domain, {bool isDark = false}) {
    return _api?.getProviderIconSvg(domain, isDark: isDark);
  }

  /// Get provider manifest by domain
  ProviderManifest? getProviderManifest(String domain) {
    return _api?.getProviderManifest(domain);
  }

  /// Get artwork URL for a player from cache
  String? getCachedArtworkUrl(String playerId, {int size = 512}) {
    final track = getCachedTrackForPlayer(playerId);
    if (track == null) return null;
    return getImageUrl(track, size: size);
  }

  /// Load podcast cover cache from storage for instant high-res display
  ///
  /// Should be called during initialization.
  Future<void> loadPodcastCoverCache(Map<String, String> cache) async {
    if (cache.isNotEmpty) {
      _podcastCoverCache.addAll(cache);
    }
  }

  /// Get the current podcast cover cache (for persistence)
  Map<String, String> get podcastCoverCache => Map.unmodifiable(_podcastCoverCache);

  /// Update podcast cover cache entry
  void updatePodcastCoverCache(String podcastId, String coverUrl) {
    _podcastCoverCache[podcastId] = coverUrl;
  }

  /// Clear all podcast cover cache entries
  void clearPodcastCoverCache() {
    _podcastCoverCache.clear();
  }
}
