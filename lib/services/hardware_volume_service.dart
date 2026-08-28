import 'dart:async';
import 'package:flutter/services.dart';
import 'debug_logger.dart';

/// Service to intercept hardware volume button presses
/// and route them to the selected Music Assistant player.
///
/// For MA players: intercept buttons and send volume commands via API
/// For builtin player: let native volume work (don't intercept)
///
/// Also provides a volume observer for lockscreen volume changes.
/// When the app is in the background/lockscreen, dispatchKeyEvent doesn't fire,
/// so the observer watches system STREAM_MUSIC volume changes and sends
/// absolute volume values to Flutter for routing to the MA player.
class HardwareVolumeService {
  static final HardwareVolumeService _instance = HardwareVolumeService._internal();
  factory HardwareVolumeService() => _instance;
  HardwareVolumeService._internal();

  static const _channel = MethodChannel('com.collotsspot.ensemble/volume_buttons');
  final _logger = DebugLogger();

  final _volumeUpController = StreamController<void>.broadcast();
  final _volumeDownController = StreamController<void>.broadcast();
  final _absoluteVolumeController = StreamController<({int volume, int direction, int delta})>.broadcast();

  Stream<void> get onVolumeUp => _volumeUpController.stream;
  Stream<void> get onVolumeDown => _volumeDownController.stream;

  /// Stream of volume changes from lockscreen hardware buttons.
  /// Each event contains `volume` (0-100 mapped system volume),
  /// `direction` (+1 for vol-up, -1 for vol-down), and `delta` (per-step
  /// size mapped to 0-100 scale) from the native layer.
  Stream<({int volume, int direction, int delta})> get onAbsoluteVolumeChange => _absoluteVolumeController.stream;

  bool _isListening = false;
  bool get isListening => _isListening;

  bool _isIntercepting = false;
  bool get isIntercepting => _isIntercepting;

  bool _isObservingVolume = false;
  bool get isObservingVolume => _isObservingVolume;

  /// Initialize the service and start listening for volume button events
  Future<void> init() async {
    if (_isListening) return;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'volumeUp':
          _volumeUpController.add(null);
          break;
        case 'volumeDown':
          _volumeDownController.add(null);
          break;
        case 'absoluteVolumeChange':
          // Volume changed from lockscreen/background via ContentObserver
          // Native sends a map with 'volume' (0-100), 'direction' (+1/-1),
          // and 'delta' (per-step size mapped to 0-100 scale).
          final args = call.arguments as Map;
          final volume = (args['volume'] as int?) ?? 0;
          final direction = (args['direction'] as int?) ?? 0;
          final delta = (args['delta'] as int?) ?? 0;
          _absoluteVolumeController.add((volume: volume, direction: direction, delta: delta));
          break;
      }
    });

    try {
      await _channel.invokeMethod('startListening');
      _isListening = true;
      _isIntercepting = true;
    } catch (e) {
      _logger.error('Failed to start volume button listening', context: 'VolumeService', error: e);
    }
  }

  /// Enable or disable volume button interception.
  /// When disabled, hardware volume buttons control device volume normally.
  /// When enabled, volume button events are sent to Flutter for MA player control.
  Future<void> setIntercepting(bool intercept) async {
    if (!_isListening || _isIntercepting == intercept) return;

    try {
      if (intercept) {
        await _channel.invokeMethod('startListening');
        _isIntercepting = true;
      } else {
        await _channel.invokeMethod('stopListening');
        _isIntercepting = false;
      }
    } catch (e) {
      _logger.error('Failed to set volume interception', context: 'VolumeService', error: e);
    }
  }

  /// Start the volume observer for lockscreen/background volume changes.
  /// When active, system STREAM_MUSIC volume changes are detected and sent
  /// to Flutter via [onAbsoluteVolumeChange]. Optionally sets the system
  /// volume to [initialVolume] (0-100) to match the MA player's current volume.
  Future<void> startVolumeObserver({int? initialVolume}) async {
    if (_isObservingVolume) return;

    try {
      await _channel.invokeMethod('startVolumeObserver', {
        if (initialVolume != null) 'initialVolume': initialVolume,
      });
      _isObservingVolume = true;
      _logger.info('Volume observer started', context: 'VolumeService');
    } catch (e) {
      _logger.error('Failed to start volume observer', context: 'VolumeService', error: e);
    }
  }

  /// Stop the volume observer.
  Future<void> stopVolumeObserver() async {
    if (!_isObservingVolume) return;

    try {
      await _channel.invokeMethod('stopVolumeObserver');
      _isObservingVolume = false;
      _logger.info('Volume observer stopped', context: 'VolumeService');
    } catch (e) {
      _logger.error('Failed to stop volume observer', context: 'VolumeService', error: e);
    }
  }

  /// Notify the native layer whether MA is actively playing.
  /// The volume observer uses this flag to suppress mirroring when MA is
  /// paused, idle, disconnected, or not the active audio source.
  Future<void> setMAPlayingState(bool isPlaying) async {
    try {
      await _channel.invokeMethod('setMAPlayingState', {'isPlaying': isPlaying});
      _logger.info('MA playing state set to $isPlaying', context: 'VolumeService');
    } catch (e) {
      _logger.error('Failed to set MA playing state', context: 'VolumeService', error: e);
    }
  }

  /// Sync the system volume to match the MA player volume (0-100).
  /// Used to keep the system volume HUD in sync with the MA player.
  Future<void> syncSystemVolume(int maVolume) async {
    try {
      await _channel.invokeMethod('syncSystemVolume', {'volume': maVolume});
    } catch (e) {
      _logger.error('Failed to sync system volume', context: 'VolumeService', error: e);
    }
  }

  /// Stop listening for volume button events
  Future<void> dispose() async {
    if (_isObservingVolume) {
      await stopVolumeObserver();
    }

    if (!_isListening) return;

    try {
      await _channel.invokeMethod('stopListening');
      _isListening = false;
      _isIntercepting = false;
      _logger.info('Hardware volume button listening stopped', context: 'VolumeService');
    } catch (e) {
      _logger.error('Failed to stop volume button listening', context: 'VolumeService', error: e);
    }

    // Close StreamControllers to prevent memory leaks
    await _volumeUpController.close();
    await _volumeDownController.close();
    await _absoluteVolumeController.close();
  }
}
