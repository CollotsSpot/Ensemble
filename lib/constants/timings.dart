/// Timing constants for polling intervals, cache durations, and delays
class Timings {
  Timings._();

  /// WebSocket heartbeat/ping interval to keep connection alive
  static const Duration heartbeatInterval = Duration(seconds: 30);

  /// Player state polling interval (for selected player updates)
  static const Duration playerPollingInterval = Duration(seconds: 5);

  /// Notification position update interval (for updating playback position in notification)
  static const Duration notificationPositionUpdate = Duration(seconds: 1);

  /// Local player state report interval
  /// Note: Sendspin protocol only requires state on changes, not periodic reports.
  /// This is mainly for local UI position tracking. Set to 5s to reduce server traffic.
  static const Duration localPlayerReportInterval = Duration(seconds: 5);

  /// Player list cache duration before refresh
  static const Duration playersCacheDuration = Duration(minutes: 5);

  /// Home screen row cache duration (recently played, discover sections)
  static const Duration homeRowCacheDuration = Duration(minutes: 10);

  /// WebSocket reconnection delay
  static const Duration reconnectDelay = Duration(seconds: 3);

  /// Command timeout for API requests
  static const Duration commandTimeout = Duration(seconds: 30);

  /// Connection timeout for initial WebSocket handshake
  static const Duration connectionTimeout = Duration(seconds: 10);

  /// Search debounce delay
  static const Duration searchDebounce = Duration(milliseconds: 500);

  /// Navigation debounce to prevent double-tap navigation
  static const Duration navigationDebounce = Duration(milliseconds: 500);

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

/// Image/artwork size constants
class ImageSizes {
  ImageSizes._();

  /// Default image size for artwork (256x256)
  static const int defaultSize = 256;

  /// High resolution image size for player/overlay (512x512)
  static const int highRes = 512;

  /// Maximum image size for large displays
  static const int max = 1024;
}

/// Volume control constants
class VolumeConstants {
  VolumeConstants._();

  /// Minimum volume level
  static const int min = 0;

  /// Maximum volume level
  static const int max = 100;

  /// Volume range for validation (0-100)
  static const int range = 100;
}

/// Player state constants
class PlayerStates {
  PlayerStates._();

  /// Player is playing media
  static const String playing = 'playing';

  /// Player is paused
  static const String paused = 'paused';

  /// Player is idle/nothing loaded
  static const String idle = 'idle';

  /// Player is off/disconnected
  static const String off = 'off';
}

/// Repeat mode constants
class RepeatModes {
  RepeatModes._();

  /// Repeat is off
  static const String off = 'off';

  /// Repeat all tracks
  static const String all = 'all';

  /// Repeat single track
  static const String one = 'one';
}
