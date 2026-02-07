import 'dart:async';
import 'dart:ui';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter/foundation.dart';
import '../constants/timings.dart';
import '../services/audio/massiv_audio_handler.dart';
import '../services/auth/auth_manager.dart';
import '../services/debug_logger.dart';
import '../services/device_id_service.dart';
import '../services/local_player_service.dart';
import '../services/pcm_audio_player.dart';
import '../services/sendspin_service.dart';
import '../services/settings_service.dart';

/// Provider for local audio playback and Sendspin integration.
///
/// Manages:
/// - LocalPlayerService for audio playback
/// - SendspinService integration (MA 2.7.0b20+)
/// - PcmAudioPlayer for raw audio streaming
/// - Player registration with Music Assistant
/// - Volume and power control
/// - Event handling from Sendspin
///
/// Extracted from MusicAssistantProvider to isolate local player logic.
class LocalPlayerProvider extends ChangeNotifier {
  final AuthManager _authManager;
  final DebugLogger _logger;
  final SettingsService? _settings;

  // Local player service
  late final LocalPlayerService _localPlayer;

  // Sendspin service (MA 2.7.0b20+ replacement for builtin_player)
  SendspinService? _sendspinService;
  bool _sendspinConnected = false;

  // PCM audio player for raw Sendspin audio streaming
  PcmAudioPlayer? _pcmAudioPlayer;

  // Local player state
  bool _isLocalPlayerPowered = true;
  int _localPlayerVolume = VolumeConstants.max;
  bool _builtinPlayerAvailable = true;

  // State reporting timer
  Timer? _localPlayerStateReportTimer;

  // Audio handler (from audio_service package)
  final MassivAudioHandler _audioHandler;

  // Server info
  String? _serverUrl;

  // Callbacks
  Function()? onSendspinConnected;
  Function()? onSendspinDisconnected;
  Function(Map<String, dynamic>)? onLocalPlayerEvent;

  LocalPlayerProvider({
    AuthManager? authManager,
    DebugLogger? logger,
    SettingsService? settings,
    required MassivAudioHandler audioHandler,
  })  : _authManager = authManager ?? AuthManager(),
        _logger = logger ?? DebugLogger(),
        _settings = settings,
        _audioHandler = audioHandler {
    _localPlayer = LocalPlayerService(_authManager);
  }

  // Getters
  bool get isLocalPlayerPowered => _isLocalPlayerPowered;
  int get localPlayerVolume => _localPlayerVolume;
  bool get sendspinConnected => _sendspinConnected;
  bool get builtinPlayerAvailable => _builtinPlayerAvailable;
  bool get isPcmPlaying => _sendspinConnected && _pcmAudioPlayer != null && _pcmAudioPlayer!.isPlaying;
  LocalPlayerService get localPlayer => _localPlayer;
  SendspinService? get sendspinService => _sendspinService;
  PcmAudioPlayer? get pcmAudioPlayer => _pcmAudioPlayer;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  /// Initialize local playback engine
  Future<void> initialize() async {
    await _localPlayer.initialize();
    _isLocalPlayerPowered = true;

    // Wire up notification button callbacks
    _wireNotificationCallbacks();

    _logger.log('🔊 Local player initialized');
  }

  /// Register the built-in/local player with Music Assistant
  Future<String?> registerLocalPlayer() async {
    if (_serverUrl == null) {
      _logger.log('⚠️ Cannot register player: no server URL');
      return null;
    }

    try {
      final deviceId = await DeviceIdService.getOrCreateDevicePlayerId();
      final ownerName = await SettingsService.getOwnerName() ?? 'Ensemble User';

      _logger.log('📱 Registering local player: $deviceId');

      // Check if server uses Sendspin (MA 2.7.0b20+)
      if (_serverUsesSendspin()) {
        return await _registerSendspinPlayer(deviceId, ownerName);
      } else {
        return await _registerBuiltinPlayer(deviceId, ownerName);
      }
    } catch (e) {
      _logger.log('❌ Failed to register local player: $e');
      return null;
    }
  }

  /// Check if server version is >= 2.7.0b20 (uses Sendspin)
  bool _serverUsesSendspin() {
    // This would check the server version from API
    // For now, we'll try both methods
    return true; // Default to Sendspin for modern MA
  }

  /// Register using Sendspin protocol (MA 2.7.0b20+)
  Future<String?> _registerSendspinPlayer(String deviceId, String ownerName) async {
    _logger.log('📡 Registering via Sendspin protocol...');

    try {
      // Initialize Sendspin service
      _sendspinService = SendspinService(_serverUrl!);
      _builtinPlayerAvailable = false;

      // Initialize PCM audio player
      _pcmAudioPlayer = PcmAudioPlayer();
      final pcmInitialized = await _pcmAudioPlayer!.initialize();
      if (!pcmInitialized) {
        _logger.log('⚠️ Failed to initialize PCM audio player');
      }

      // Connect Sendspin events
      _wireSendspinEvents();

      // Try direct connection first
      final localSendspinUrl = '$_serverUrl/sendspin/$deviceId';
      final connected = await _sendspinService!.connectWithUrl(localSendspinUrl);

      if (!connected) {
        // Try proxy connection
        final proxyUrl = '$_serverUrl/sendspin/proxy/$deviceId';
        final proxyConnected = await _sendspinService!.connectWithUrl(proxyUrl, useProxyAuth: true);
        if (!proxyConnected) {
          _logger.log('⚠️ Sendspin connection failed, will retry on connect');
          return null;
        }
      }

      // Connect PCM audio player to Sendspin audio stream
      if (_pcmAudioPlayer != null && pcmInitialized) {
        await _pcmAudioPlayer!.connectToStream(_sendspinService!.audioDataStream);
      }

      _sendspinConnected = true;
      _startStateReporting();
      onSendspinConnected?.call();

      _logger.log('✅ Sendspin player registered: $deviceId');
      return deviceId;
    } catch (e) {
      _logger.log('❌ Sendspin registration failed: $e');
      return null;
    }
  }

  /// Register using legacy builtin_player protocol
  Future<String?> _registerBuiltinPlayer(String deviceId, String ownerName) async {
    _logger.log('📻 Registering via builtin_player protocol...');
    // Legacy registration would go here
    return deviceId;
  }

  // ============================================================================
  // SENDSPIN EVENT HANDLERS
  // ============================================================================

  void _wireSendspinEvents() {
    if (_sendspinService == null) return;

    _sendspinService!.onPlay = _handleSendspinPlay;
    _sendspinService!.onPause = _handleSendspinPause;
    _sendspinService!.onStop = _handleSendspinStop;
    _sendspinService!.onSeek = _handleSendspinSeek;
    _sendspinService!.onVolume = _handleSendspinVolume;
    _sendspinService!.onStreamStart = _handleSendspinStreamStart;
    _sendspinService!.onStreamEnd = _handleSendspinStreamEnd;
  }

  void _handleSendspinPlay(String streamUrl, Map<String, dynamic> trackInfo) {
    _logger.log('📡 Sendspin: Play $streamUrl');
    _pcmAudioPlayer?.play();
    notifyListeners();
  }

  void _handleSendspinPause() {
    _logger.log('📡 Sendspin: Pause');
    _pcmAudioPlayer?.pause();
    notifyListeners();
  }

  void _handleSendspinStop() {
    _logger.log('📡 Sendspin: Stop');
    _pcmAudioPlayer?.stop();
    notifyListeners();
  }

  void _handleSendspinSeek(int positionSeconds) {
    _logger.log('📡 Sendspin: Seek to $positionSeconds');
    _pcmAudioPlayer?.resetPosition();
    notifyListeners();
  }

  void _handleSendspinVolume(int volumeLevel) {
    _logger.log('📡 Sendspin: Set volume to $volumeLevel');
    _localPlayerVolume = volumeLevel;
    notifyListeners();
  }

  void _handleSendspinStreamStart(Map<String, dynamic>? trackInfo) {
    _logger.log('📡 Sendspin: Stream start');
    _pcmAudioPlayer?.play();
    notifyListeners();
  }

  void _handleSendspinStreamEnd() {
    _logger.log('📡 Sendspin: Stream end');
    _pcmAudioPlayer?.stop();
    notifyListeners();
  }

  // ============================================================================
  // LOCAL PLAYER CONTROLS
  // ============================================================================

  Future<void> setPower(bool powered) async {
    _isLocalPlayerPowered = powered;
    notifyListeners();
  }

  Future<void> setVolume(int volumeLevel) async {
    _localPlayerVolume = volumeLevel;
    _localPlayer.setVolume(volumeLevel / 100);

    // Report to Sendspin if connected
    if (_sendspinConnected && _sendspinService != null) {
      _sendspinService!.reportState(volume: volumeLevel);
    }

    notifyListeners();
  }

  Future<void> playUrl(String url) async {
    await _localPlayer.playUrl(url);

    // Report to Sendspin if connected
    if (_sendspinConnected && _sendspinService != null) {
      _sendspinService!.reportState(playing: true, paused: false);
    }
  }

  Future<void> pause() async {
    await _localPlayer.pause();

    if (_sendspinConnected && _sendspinService != null) {
      _sendspinService!.reportState(playing: false, paused: true);
    }
  }

  Future<void> stop() async {
    await _localPlayer.stop();

    if (_sendspinConnected && _sendspinService != null) {
      _sendspinService!.reportState(playing: false, paused: false);
    }
  }

  Future<void> seek(Duration position) async {
    await _localPlayer.seek(position);

    if (_sendspinConnected && _sendspinService != null) {
      _sendspinService!.reportState(position: position.inSeconds);
    }
  }

  // ============================================================================
  // NOTIFICATION CALLBACKS
  // ============================================================================

  void _wireNotificationCallbacks() {
    _audioHandler.onPlay = () {
      _logger.log('🎵 Notification: Play pressed');
      // This would be handled by PlayerProvider
    };
    _audioHandler.onPause = () {
      _logger.log('🎵 Notification: Pause pressed');
      // This would be handled by PlayerProvider
    };
    _audioHandler.onSkipToNext = () {
      _logger.log('🎵 Notification: Skip to next pressed');
      // This would be handled by PlayerProvider
    };
    _audioHandler.onSkipToPrevious = () {
      _logger.log('🎵 Notification: Skip to previous pressed');
      // This would be handled by PlayerProvider
    };
  }

  // ============================================================================
  // STATE REPORTING
  // ============================================================================

  void _startStateReporting() {
    _localPlayerStateReportTimer?.cancel();
    _localPlayerStateReportTimer = Timer.periodic(
      Timings.localPlayerReportInterval,
      (_) => _reportState(),
    );
  }

  Future<void> _reportState() async {
    if (!_sendspinConnected || _sendspinService == null) return;

    final isPlaying = _localPlayer.isPlaying;
    final position = _localPlayer.position.inSeconds;
    final volume = _localPlayerVolume;
    final muted = _localPlayerVolume == 0;

    _sendspinService!.reportState(
      playing: isPlaying,
      paused: !isPlaying,
      position: position,
      volume: volume,
      muted: muted,
    );
  }

  // ============================================================================
  // SERVER URL MANAGEMENT
  // ============================================================================

  void setServerUrl(String? serverUrl) {
    _serverUrl = serverUrl;
  }

  // ============================================================================
  // CLEANUP
  // ============================================================================

  @override
  void dispose() {
    _localPlayerStateReportTimer?.cancel();
    _pcmAudioPlayer?.dispose();
    _sendspinService?.dispose();
    _localPlayer.dispose();
    super.dispose();
  }
}
