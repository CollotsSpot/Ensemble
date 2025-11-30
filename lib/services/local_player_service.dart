import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'debug_logger.dart';
import 'auth/auth_manager.dart';
import '../main.dart' show audioHandler;

/// Metadata for the currently playing track
class TrackMetadata {
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final Duration? duration;

  TrackMetadata({
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    this.duration,
  });

  /// Convert to MediaItem for audio_service
  MediaItem toMediaItem(String id) {
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album ?? '',
      duration: duration,
      artUri: artworkUrl != null ? Uri.tryParse(artworkUrl!) : null,
    );
  }
}

/// Service that wraps the global MassivAudioHandler for local playback.
/// This maintains the same interface as before for compatibility with
/// MusicAssistantProvider.
class LocalPlayerService {
  final AuthManager authManager;
  final _logger = DebugLogger();
  bool _isInitialized = false;

  // Current track metadata for notifications
  TrackMetadata? _currentMetadata;

  LocalPlayerService(this.authManager);

  // Expose player state streams from the global handler
  Stream<PlayerState> get playerStateStream {
    return audioHandler.playerStateStream;
  }

  Stream<Duration> get positionStream {
    return audioHandler.positionStream;
  }

  Stream<Duration?> get durationStream {
    return audioHandler.durationStream;
  }

  // Current state getters
  bool get isPlaying {
    return audioHandler.isPlaying;
  }

  double get volume {
    return audioHandler.volume;
  }

  PlayerState get playerState {
    return audioHandler.playerState;
  }

  Duration get position {
    return audioHandler.position;
  }

  Duration get duration {
    return audioHandler.duration;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    _logger.log('LocalPlayerService: Initializing with audio_service...');
    // The audioHandler is already initialized in main.dart
    // Just mark ourselves as initialized
    _isInitialized = true;
    _logger.log('LocalPlayerService: Initialized (using global audioHandler)');
  }

  /// Set metadata for the current track (for notification display)
  void setCurrentTrackMetadata(TrackMetadata metadata) {
    _currentMetadata = metadata;
  }

  /// Play a stream URL with authentication headers
  Future<void> playUrl(String url) async {
    // Ensure player is initialized before playing
    if (!_isInitialized) {
      _logger.log('LocalPlayerService: Not initialized, initializing now...');
      await initialize();
    }

    try {
      _logger.log('LocalPlayerService: Loading URL: $url');

      // Get auth headers from AuthManager
      final headers = authManager.getStreamingHeaders();

      if (headers.isNotEmpty) {
        _logger.log('LocalPlayerService: Added auth headers to request: ${headers.keys.join(', ')}');
      } else {
        _logger.log('LocalPlayerService: No authentication needed for streaming');
      }

      // Create MediaItem from current metadata
      final mediaItem = _currentMetadata?.toMediaItem(url) ?? MediaItem(
        id: url,
        title: 'Unknown Track',
        artist: 'Unknown Artist',
      );

      _logger.log('LocalPlayerService: Playing with audio_service');
      _logger.log('LocalPlayerService: Metadata: ${mediaItem.title} by ${mediaItem.artist}');

      await audioHandler.playUrl(
        url,
        mediaItem,
        headers: headers.isNotEmpty ? headers : null,
      );

      _logger.log('LocalPlayerService: Playback started with notification');
    } catch (e, stackTrace) {
      _logger.log('LocalPlayerService: Error playing URL: $e');
      _logger.log('LocalPlayerService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Update the notification with new track info (without reloading audio)
  void updateNotification({
    required String id,
    required String title,
    String? artist,
    String? album,
    String? artworkUrl,
    Duration? duration,
  }) {
    _currentMetadata = TrackMetadata(
      title: title,
      artist: artist ?? 'Unknown Artist',
      album: album,
      artworkUrl: artworkUrl,
      duration: duration,
    );

    _logger.log('LocalPlayerService: Metadata updated for notification');
  }

  /// Update the notification while audio is already playing.
  /// With audio_service, we can update the MediaItem directly without
  /// re-setting the audio source.
  Future<void> updateNotificationWhilePlaying(TrackMetadata metadata) async {
    _logger.log('LocalPlayerService: Updating notification mid-playback: ${metadata.title} by ${metadata.artist}');

    final currentItem = audioHandler.currentMediaItem;
    final id = currentItem?.id ?? 'unknown';

    final newMediaItem = metadata.toMediaItem(id);
    audioHandler.updateMediaItem(newMediaItem);
    _currentMetadata = metadata;

    _logger.log('LocalPlayerService: Notification updated successfully');
  }

  Future<void> play() async {
    await audioHandler.play();
  }

  Future<void> pause() async {
    await audioHandler.pause();
  }

  Future<void> stop() async {
    await audioHandler.stop();
  }

  Future<void> seek(Duration position) async {
    await audioHandler.seek(position);
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await audioHandler.setVolume(volume.clamp(0.0, 1.0));
  }

  void dispose() {
    // The global audioHandler is managed by audio_service
    // Don't dispose it here
  }
}
