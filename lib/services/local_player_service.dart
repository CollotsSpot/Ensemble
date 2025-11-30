import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'debug_logger.dart';
import 'auth/auth_manager.dart';
import 'audio_handler.dart';
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
}

class LocalPlayerService {
  final AuthManager authManager;
  final _logger = DebugLogger();
  bool _isInitialized = false;

  // Current track metadata for notifications
  TrackMetadata? _currentMetadata;

  LocalPlayerService(this.authManager);

  // Expose player state streams from the audio handler
  Stream<PlayerState> get playerStateStream => audioHandler.playerStateStream;
  Stream<Duration> get positionStream => audioHandler.positionStream;
  Stream<Duration?> get durationStream => audioHandler.durationStream;

  // Current state getters
  bool get isPlaying => audioHandler.isPlaying;
  double get volume => audioHandler.volume;
  PlayerState get playerState => audioHandler.playerState;
  Duration get position => audioHandler.position;
  Duration get duration => audioHandler.duration;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Set auth headers on the audio handler
      final headers = authManager.getStreamingHeaders();
      if (headers.isNotEmpty) {
        audioHandler.setAuthHeaders(headers);
      }

      _isInitialized = true;
      _logger.log('LocalPlayerService initialized with AudioHandler');
    } catch (e) {
      _logger.log('Error initializing LocalPlayerService: $e');
    }
  }

  /// Set metadata for the current track (for notification display)
  void setCurrentTrackMetadata(TrackMetadata metadata) {
    _currentMetadata = metadata;
  }

  /// Play a stream URL with authentication headers
  Future<void> playUrl(String url) async {
    try {
      _logger.log('LocalPlayerService: Loading URL: $url');

      // Get auth headers from AuthManager
      final headers = authManager.getStreamingHeaders();

      if (headers.isNotEmpty) {
        _logger.log('LocalPlayerService: Added auth headers to request: ${headers.keys.join(', ')}');
      } else {
        _logger.log('LocalPlayerService: No authentication needed for streaming');
      }

      // Play via audio handler with metadata for notification
      await audioHandler.playUrl(
        url,
        title: _currentMetadata?.title ?? 'Unknown Track',
        artist: _currentMetadata?.artist ?? 'Unknown Artist',
        album: _currentMetadata?.album,
        artworkUrl: _currentMetadata?.artworkUrl,
        duration: _currentMetadata?.duration,
        headers: headers.isNotEmpty ? headers : null,
      );
    } catch (e) {
      _logger.log('LocalPlayerService: Error playing URL: $e');
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
    audioHandler.updateCurrentMediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      artworkUrl: artworkUrl,
      duration: duration,
    );
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
    await audioHandler.setVolume(volume);
  }

  void dispose() {
    // Audio handler is managed globally, don't dispose here
  }
}
