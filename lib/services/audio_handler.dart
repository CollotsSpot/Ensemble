import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'debug_logger.dart';

/// AudioHandler implementation that enables background playback and media notifications.
/// This wraps just_audio's AudioPlayer with audio_service for system integration.
class MassivAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final DebugLogger _logger = DebugLogger();

  // Store headers for authenticated streaming
  Map<String, String>? _currentHeaders;

  // Callbacks for notification button actions
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  MassivAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    // Configure audio session for music playback
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Broadcast player state changes to the system
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Handle audio interruptions (phone calls, etc.)
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(0.5);
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            pause();
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(1.0);
            break;
          case AudioInterruptionType.pause:
            play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // Handle becoming noisy (headphones unplugged)
    session.becomingNoisyEventStream.listen((_) {
      pause();
    });

    // Log errors
    _player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace stackTrace) {
        _logger.log('MassivAudioHandler: Playback error: $e');
      },
    );

    _logger.log('MassivAudioHandler initialized');
  }

  /// Transform player events to PlaybackState for the system
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  // ============================================================================
  // Expose streams for UI binding
  // ============================================================================

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  bool get isPlaying => _player.playing;
  double get volume => _player.volume;
  PlayerState get playerState => _player.playerState;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;

  // ============================================================================
  // Audio Service required overrides
  // ============================================================================

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    // Clear the media item when stopped
    mediaItem.add(null);
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    _logger.log('MassivAudioHandler: skipToNext requested');
    if (onSkipToNext != null) {
      await onSkipToNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    _logger.log('MassivAudioHandler: skipToPrevious requested');
    if (onSkipToPrevious != null) {
      await onSkipToPrevious!();
    }
  }

  // ============================================================================
  // Custom methods for Massiv
  // ============================================================================

  /// Set auth headers for streaming
  void setAuthHeaders(Map<String, String> headers) {
    _currentHeaders = headers;
  }

  /// Play a URL with optional metadata for the notification
  Future<void> playUrl(
    String url, {
    String? title,
    String? artist,
    String? album,
    String? artworkUrl,
    Duration? duration,
    Map<String, String>? headers,
  }) async {
    try {
      _logger.log('MassivAudioHandler: Loading URL: $url');

      // Use provided headers or stored headers
      final effectiveHeaders = headers ?? _currentHeaders;

      if (effectiveHeaders != null && effectiveHeaders.isNotEmpty) {
        _logger.log('MassivAudioHandler: Using auth headers: ${effectiveHeaders.keys.join(', ')}');
      }

      // Update the media item for the notification
      final item = MediaItem(
        id: url,
        title: title ?? 'Unknown Track',
        artist: artist ?? 'Unknown Artist',
        album: album ?? '',
        duration: duration,
        artUri: artworkUrl != null ? Uri.parse(artworkUrl) : null,
      );
      mediaItem.add(item);

      // Create audio source with headers
      final source = AudioSource.uri(
        Uri.parse(url),
        headers: effectiveHeaders,
        tag: item,
      );

      await _player.setAudioSource(source);
      await _player.play();
    } catch (e) {
      _logger.log('MassivAudioHandler: Error playing URL: $e');
      rethrow;
    }
  }

  /// Update the currently displayed media item (for when track changes from server)
  void updateCurrentMediaItem({
    required String id,
    required String title,
    String? artist,
    String? album,
    String? artworkUrl,
    Duration? duration,
  }) {
    final item = MediaItem(
      id: id,
      title: title,
      artist: artist ?? 'Unknown Artist',
      album: album ?? '',
      duration: duration,
      artUri: artworkUrl != null ? Uri.parse(artworkUrl) : null,
    );
    mediaItem.add(item);
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Clean up resources
  Future<void> dispose() async {
    await _player.dispose();
  }
}

/// Initialize and get the audio handler singleton
Future<MassivAudioHandler> initAudioHandler() async {
  return await AudioService.init(
    builder: () => MassivAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'io.github.collotsspot.massiv.audio',
      androidNotificationChannelName: 'Massiv Audio',
      androidNotificationChannelDescription: 'Music playback controls',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_notification',
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );
}
