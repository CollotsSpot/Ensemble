import 'dart:async';
import 'package:audio_session/audio_session.dart';
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
}

class LocalPlayerService {
  final AuthManager authManager;
  final _logger = DebugLogger();
  bool _isInitialized = false;

  // Fallback player when audioHandler is not available
  AudioPlayer? _fallbackPlayer;

  // Current track metadata for notifications
  TrackMetadata? _currentMetadata;

  LocalPlayerService(this.authManager);

  /// Check if we're using the audio handler (with background support) or fallback
  bool get _useAudioHandler => audioHandler != null;

  // Expose player state streams
  Stream<PlayerState> get playerStateStream {
    if (_useAudioHandler) {
      return audioHandler!.playerStateStream;
    }
    return _fallbackPlayer?.playerStateStream ?? const Stream.empty();
  }

  Stream<Duration> get positionStream {
    if (_useAudioHandler) {
      return audioHandler!.positionStream;
    }
    return _fallbackPlayer?.positionStream ?? const Stream.empty();
  }

  Stream<Duration?> get durationStream {
    if (_useAudioHandler) {
      return audioHandler!.durationStream;
    }
    return _fallbackPlayer?.durationStream ?? const Stream.empty();
  }

  // Current state getters
  bool get isPlaying {
    if (_useAudioHandler) {
      return audioHandler!.isPlaying;
    }
    return _fallbackPlayer?.playing ?? false;
  }

  double get volume {
    if (_useAudioHandler) {
      return audioHandler!.volume;
    }
    return _fallbackPlayer?.volume ?? 1.0;
  }

  PlayerState get playerState {
    if (_useAudioHandler) {
      return audioHandler!.playerState;
    }
    return _fallbackPlayer?.playerState ?? PlayerState(false, ProcessingState.idle);
  }

  Duration get position {
    if (_useAudioHandler) {
      return audioHandler!.position;
    }
    return _fallbackPlayer?.position ?? Duration.zero;
  }

  Duration get duration {
    if (_useAudioHandler) {
      return audioHandler!.duration;
    }
    return _fallbackPlayer?.duration ?? Duration.zero;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _logger.log('LocalPlayerService: Initializing... audioHandler=${audioHandler != null}');

      // Always create fallback player as backup
      _fallbackPlayer = AudioPlayer();
      await _fallbackPlayer!.setVolume(1.0);
      _logger.log('LocalPlayerService: Fallback player created');

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // Handle audio interruptions
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              if (_useAudioHandler) {
                audioHandler!.setVolume(0.5);
              } else {
                _fallbackPlayer?.setVolume(0.5);
              }
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_useAudioHandler) {
                audioHandler!.pause();
              } else {
                _fallbackPlayer?.pause();
              }
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              if (_useAudioHandler) {
                audioHandler!.setVolume(1.0);
              } else {
                _fallbackPlayer?.setVolume(1.0);
              }
              break;
            case AudioInterruptionType.pause:
              if (_useAudioHandler) {
                audioHandler!.play();
              } else {
                _fallbackPlayer?.play();
              }
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      if (_useAudioHandler) {
        // Set auth headers on the audio handler
        final headers = authManager.getStreamingHeaders();
        if (headers.isNotEmpty) {
          audioHandler!.setAuthHeaders(headers);
        }
        _logger.log('LocalPlayerService initialized with AudioHandler (background playback enabled)');
      } else {
        _logger.log('LocalPlayerService initialized with fallback player only (no background playback)');
      }

      _isInitialized = true;
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
      _logger.log('LocalPlayerService: _useAudioHandler=$_useAudioHandler, _fallbackPlayer=${_fallbackPlayer != null}');

      // Get auth headers from AuthManager
      final headers = authManager.getStreamingHeaders();

      if (headers.isNotEmpty) {
        _logger.log('LocalPlayerService: Added auth headers to request: ${headers.keys.join(', ')}');
      } else {
        _logger.log('LocalPlayerService: No authentication needed for streaming');
      }

      if (_useAudioHandler) {
        _logger.log('LocalPlayerService: Using AudioHandler to play');
        // Play via audio handler with metadata for notification
        await audioHandler!.playUrl(
          url,
          title: _currentMetadata?.title ?? 'Unknown Track',
          artist: _currentMetadata?.artist ?? 'Unknown Artist',
          album: _currentMetadata?.album,
          artworkUrl: _currentMetadata?.artworkUrl,
          duration: _currentMetadata?.duration,
          headers: headers.isNotEmpty ? headers : null,
        );
        _logger.log('LocalPlayerService: AudioHandler.playUrl completed');
      } else if (_fallbackPlayer != null) {
        _logger.log('LocalPlayerService: Using fallback player');
        // Fallback: play directly
        final source = AudioSource.uri(
          Uri.parse(url),
          headers: headers.isNotEmpty ? headers : null,
        );
        await _fallbackPlayer!.setAudioSource(source);
        await _fallbackPlayer!.play();
        _logger.log('LocalPlayerService: Fallback player started');
      } else {
        _logger.log('LocalPlayerService: ERROR - No player available!');
      }
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
    if (_useAudioHandler) {
      audioHandler!.updateCurrentMediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl,
        duration: duration,
      );
    }
    // No-op for fallback player (no notification support)
  }

  Future<void> play() async {
    if (_useAudioHandler) {
      await audioHandler!.play();
    } else {
      await _fallbackPlayer?.play();
    }
  }

  Future<void> pause() async {
    if (_useAudioHandler) {
      await audioHandler!.pause();
    } else {
      await _fallbackPlayer?.pause();
    }
  }

  Future<void> stop() async {
    if (_useAudioHandler) {
      await audioHandler!.stop();
    } else {
      await _fallbackPlayer?.stop();
    }
  }

  Future<void> seek(Duration position) async {
    if (_useAudioHandler) {
      await audioHandler!.seek(position);
    } else {
      await _fallbackPlayer?.seek(position);
    }
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    if (_useAudioHandler) {
      await audioHandler!.setVolume(volume);
    } else {
      await _fallbackPlayer?.setVolume(volume.clamp(0.0, 1.0));
    }
  }

  void dispose() {
    _fallbackPlayer?.dispose();
  }
}
