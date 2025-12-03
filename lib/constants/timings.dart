/// Timing constants for polling intervals, cache durations, and delays
class Timings {
  Timings._();

  /// Player state polling interval (for selected player updates)
  static const Duration playerPollingInterval = Duration(seconds: 5);

  /// Local player state report interval (for seek bar smoothness)
  static const Duration localPlayerReportInterval = Duration(seconds: 1);

  /// Player list cache duration before refresh
  static const Duration playersCacheDuration = Duration(minutes: 5);

  /// WebSocket reconnection delay
  static const Duration reconnectDelay = Duration(seconds: 3);

  /// Command timeout for API requests
  static const Duration commandTimeout = Duration(seconds: 30);

  /// Connection timeout for initial WebSocket handshake
  static const Duration connectionTimeout = Duration(seconds: 10);

  /// Search debounce delay
  static const Duration searchDebounce = Duration(milliseconds: 500);

  /// Delay after track change before updating state
  static const Duration trackChangeDelay = Duration(milliseconds: 500);
}

/// Library and pagination constants
class LibraryConstants {
  LibraryConstants._();

  /// Default page size for library items
  static const int defaultPageSize = 100;

  /// Maximum items to load for "all" library requests
  static const int maxLibraryItems = 5000;

  /// Number of items per batch for recent albums
  static const int recentAlbumsBatchSize = 5;

  /// Default limit for recent/random items
  static const int defaultRecentLimit = 10;
}
