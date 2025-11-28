import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'settings_service.dart';
import 'debug_logger.dart';

class LocalPlayerService {
  final _player = AudioPlayer();
  final _logger = DebugLogger();
  bool _isInitialized = false;

  // Expose player state streams
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  
  // Current state getters
  bool get isPlaying => _player.playing;
  double get volume => _player.volume;
  PlayerState get playerState => _player.playerState;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      
      // Default to 100% volume
      await _player.setVolume(1.0);
      
      // Log playback errors
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _logger.log('LocalPlayerService: Playback completed');
        }
      });
      
      _player.playbackEventStream.listen((event) {}, onError: (Object e, StackTrace stackTrace) {
        _logger.log('LocalPlayerService: Playback error: $e');
      });
      
      // Handle audio interruptions (e.g. phone calls)
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              _player.pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              _player.play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      _isInitialized = true;
      _logger.log('LocalPlayerService initialized');
    } catch (e) {
      _logger.log('Error initializing LocalPlayerService: $e');
    }
  }

  /// Play a stream URL with authentication headers
  Future<void> playUrl(String url) async {
    try {
      _logger.log('LocalPlayerService: Loading URL: $url');
      
      // Get auth token for Authelia
      final authToken = await SettingsService.getAuthToken();
      final Map<String, String> headers = {};
      
      if (authToken != null && authToken.isNotEmpty && authToken != 'authenticated') {
        // Critical: Pass the auth cookie to the audio player
        // This ensures playback works even if the server is behind Authelia
        headers['Cookie'] = 'authelia_session=$authToken';
        _logger.log('LocalPlayerService: Added auth cookie to request');
      }

      // Create audio source with headers
      final source = AudioSource.uri(
        Uri.parse(url),
        headers: headers.isNotEmpty ? headers : null,
        tag: 'Music Assistant Stream',
      );

      await _player.setAudioSource(source);
      await _player.play();
    } catch (e) {
      _logger.log('LocalPlayerService: Error playing URL: $e');
      rethrow;
    }
  }

  Future<void> play() async {
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  void dispose() {
    _player.dispose();
  }
}
