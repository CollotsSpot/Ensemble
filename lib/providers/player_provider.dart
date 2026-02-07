import 'dart:async';
import 'dart:ui';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter/foundation.dart';
import '../constants/timings.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import '../services/cache_service.dart';
import '../services/debug_logger.dart';
import '../services/database_service.dart';
import '../services/image_helper_service.dart';
import '../services/music_assistant_api.dart';
import '../services/position_tracker.dart';
import '../services/queue_manager_service.dart';
import '../services/settings_service.dart';
import '../services/sleep_timer_provider.dart';
import '../utils/player_sort_utility.dart';

/// Provider for player management and playback controls.
///
/// Manages:
/// - Player selection and available players list
/// - Current playback state and track
/// - Play/pause/stop/next/previous/seek controls
/// - Queue operations
/// - Position tracking
/// - Sleep timer integration
///
/// Extracted from MusicAssistantProvider to isolate player logic.
class PlayerProvider extends ChangeNotifier {
  final MusicAssistantAPI? _api;
  final DebugLogger _logger;
  final CacheService _cacheService;
  final SettingsService _settings;
  final PositionTracker _positionTracker;
  final QueueManagerService _queueManager;
  final SleepTimerProvider _sleepTimerProvider;
  final ImageHelperService _imageHelper;
  final PlayerSyncState _playerSyncState;

  // Player state
  Player? _selectedPlayer;
  List<Player> _availablePlayers = [];
  Map<String, String> _castToSendspinIdMap = {};
  bool _selectPlayerInProgress = false;

  // Current playback
  Track? _currentTrack;
  Audiobook? _currentAudiobook;
  String? _currentPodcastName;
  TrackMetadata? _pendingTrackMetadata;
  TrackMetadata? _currentNotificationMetadata;

  // Timers
  Timer? _playerStateTimer;
  Timer? _notificationPositionTimer;
  Timer? _idleServiceTimer;

  // Audio handler (from audio_service package)
  final audio_service.AudioHandler _audioHandler;

  // Callbacks for coordination
  Function()? onPlayerChanged;
  Function()? onTrackChanged;
  Function()? onAudiobookChanged;

  PlayerProvider({
    required MusicAssistantAPI? api,
    required DebugLogger logger,
    required CacheService cacheService,
    required SettingsService settings,
    required PositionTracker positionTracker,
    required QueueManagerService queueManager,
    required SleepTimerProvider sleepTimerProvider,
    required ImageHelperService imageHelper,
    required PlayerSyncState playerSyncState,
    required audio_service.AudioHandler audioHandler,
  })  : _api = api,
        _logger = logger,
        _cacheService = cacheService,
        _settings = settings,
        _positionTracker = positionTracker,
        _queueManager = queueManager,
        _sleepTimerProvider = sleepTimerProvider,
        _imageHelper = imageHelper,
        _playerSyncState = playerSyncState,
        _audioHandler = audioHandler {
    // Connect position tracker to sleep timer
    _positionTracker.onPositionUpdate = (position) {
      // Notify listeners for position updates
      notifyListeners();
    };

    // Set up sleep timer expiration callback
    _sleepTimerProvider.onExpired = () {
      pausePlayer(_selectedPlayer?.playerId ?? '');
    };
  }

  // Getters
  Player? get selectedPlayer => _selectedPlayer;
  List<Player> get availablePlayers => _availablePlayers;
  Track? get currentTrack => _currentTrack;
  Audiobook? get currentAudiobook => _currentAudiobook;
  String? get currentPodcastName => _currentPodcastName;
  bool get selectPlayerInProgress => _selectPlayerInProgress;

  bool get isPlaying => _selectedPlayer?.state == 'playing';
  bool get isPaused => _selectedPlayer?.state == 'paused';
  bool get isStopped => _selectedPlayer?.state == 'idle' ||
                       _selectedPlayer?.state == 'off' ||
                       _selectedPlayer == null;

  String? get currentArtworkUrl {
    if (_currentTrack != null) {
      return _imageHelper.getImageUrl(_currentTrack!, size: ImageSizes.highRes);
    }
    return null;
  }

  // ============================================================================
  // PLAYER LOADING AND SELECTION
  // ============================================================================

  /// Load players and auto-select the best one
  Future<void> loadAndSelectPlayers({bool forceRefresh = false, bool coldStart = false}) async {
    try {
      // Check cache validity
      if (!forceRefresh &&
          !coldStart &&
          _cacheService.isPlayersCacheValid() &&
          _availablePlayers.isNotEmpty) {
        return;
      }

      // Load Cast-to-Sendspin mappings
      await _loadCastToSendspinMappings();

      final allPlayers = await getPlayers();
      final builtinPlayerId = await _settings.getBuiltinPlayerId();

      _logger.log('🎛️ getPlayers returned ${allPlayers.length} players');

      // Filter players
      _availablePlayers = _filterPlayers(allPlayers, builtinPlayerId);

      // Handle Cast/Sendspin player switching
      await _handleSendspinPlayers();

      // Sort players
      final smartSort = await _settings.getSmartSort();
      _sortPlayersSync(smartSort, builtinPlayerId);

      // Auto-select player if none selected or on cold start
      if (_selectedPlayer == null || coldStart) {
        final playerToSelect = _selectBestPlayer(builtinPlayerId);
        if (playerToSelect != null) {
          await selectPlayer(playerToSelect);
        }
      }

      notifyListeners();
    } catch (e) {
      _logger.log('❌ Error loading players: $e');
    }
  }

  /// Get all players from API
  Future<List<Player>> getPlayers() async {
    return await _api?.getPlayers() ?? [];
  }

  /// Select a player as the active player
  Future<void> selectPlayer(Player player, {bool skipNotify = false}) async {
    if (_selectPlayerInProgress) {
      _logger.log('⚠️ selectPlayer already in progress, skipping');
      return;
    }
    _selectPlayerInProgress = true;

    try {
      _selectedPlayer = player;

      // Cache selection
      _cacheService.setCachedSelectedPlayer(player);
      await _settings.setLastSelectedPlayerId(player.playerId);

      // Set current track from cache for instant display
      _currentTrack = _cacheService.getCachedTrackForPlayer(player.playerId);

      // Initialize position tracker
      _positionTracker.onPlayerSelected(player.playerId);
      if (!player.isExternalSource) {
        _positionTracker.updateFromServer(
          playerId: player.playerId,
          position: player.elapsedTime ?? 0.0,
          isPlaying: player.state == 'playing',
          duration: _currentTrack?.duration,
          serverTimestamp: player.elapsedTimeLastUpdated,
        );
      }

      // Update audio handler notification
      await _updateNotificationForPlayer(player);

      // Start player state polling
      _startPlayerStatePolling();
      _manageNotificationPositionTimer();

      if (!skipNotify) {
        notifyListeners();
        onPlayerChanged?.call();
      }
    } finally {
      _selectPlayerInProgress = false;
    }
  }

  /// Update audio handler notification for the selected player
  Future<void> _updateNotificationForPlayer(Player player) async {
    final builtinPlayerId = await _settings.getBuiltinPlayerId();
    final isBuiltinPlayer = builtinPlayerId != null && player.playerId == builtinPlayerId;

    if (isBuiltinPlayer) {
      _audioHandler.setLocalMode();
      if (_currentTrack != null && (player.state == 'playing' || player.state == 'paused')) {
        final track = _currentTrack!;
        final artworkUrl = _imageHelper.getImageUrl(track, size: ImageSizes.highRes);
        final artistWithPlayer = track.artistsString.isNotEmpty
            ? '${track.artistsString} • ${player.name}'
            : player.name;
        final mediaItem = audio_service.MediaItem(
          id: track.uri ?? track.itemId,
          title: track.name,
          artist: artistWithPlayer,
          album: track.album?.name ?? '',
          duration: track.duration,
          artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
        );
        _audioHandler.updateLocalModeNotification(
          item: mediaItem,
          playing: player.state == 'playing',
          duration: track.duration,
        );
      } else if (player.state == 'playing' || player.state == 'paused') {
        final mediaItem = audio_service.MediaItem(
          id: 'player_${player.playerId}',
          title: player.name,
          artist: 'Loading...',
        );
        _audioHandler.updateLocalModeNotification(
          item: mediaItem,
          playing: player.state == 'playing',
        );
      } else {
        _audioHandler.clearRemotePlaybackState();
        _startIdleServiceTimer();
      }
    } else {
      // Remote player
      if (_currentTrack != null && (player.state == 'playing' || player.state == 'paused')) {
        final track = _currentTrack!;
        final artworkUrl = _imageHelper.getImageUrl(track, size: ImageSizes.highRes);
        final artistWithPlayer = track.artistsString.isNotEmpty
            ? '${track.artistsString} • ${player.name}'
            : player.name;
        final mediaItem = audio_service.MediaItem(
          id: track.uri ?? track.itemId,
          title: track.name,
          artist: artistWithPlayer,
          album: track.album?.name ?? '',
          duration: track.duration,
          artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
        );
        final position = _positionTracker.currentPosition;
        _cancelIdleServiceTimer();
        _audioHandler.setRemotePlaybackState(
          item: mediaItem,
          playing: player.state == 'playing',
          position: position,
          duration: track.duration,
        );
      } else if (player.state == 'playing' || player.state == 'paused') {
        final mediaItem = audio_service.MediaItem(
          id: 'player_${player.playerId}',
          title: player.name,
          artist: 'Loading...',
        );
        final position = _positionTracker.currentPosition;
        _cancelIdleServiceTimer();
        _audioHandler.setRemotePlaybackState(
          item: mediaItem,
          playing: player.state == 'playing',
          position: position,
          duration: Duration.zero,
        );
      } else {
        _audioHandler.clearRemotePlaybackState();
        _startIdleServiceTimer();
      }
    }
  }

  // ============================================================================
  // PLAYBACK CONTROLS
  // ============================================================================

  Future<void> playPauseSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    final playerId = _selectedPlayer!.playerId;
    if (_selectedPlayer?.state == 'playing') {
      await pausePlayer(playerId);
    } else {
      await playPlayer(playerId);
    }
  }

  Future<void> playPlayer(String playerId) async {
    try {
      await _api?.playPlayer(playerId);
    } catch (e) {
      _logger.log('❌ Failed to play: $e');
      rethrow;
    }
  }

  Future<void> pausePlayer(String playerId) async {
    try {
      await _api?.pausePlayer(playerId);
    } catch (e) {
      _logger.log('❌ Failed to pause: $e');
      rethrow;
    }
  }

  Future<void> stopPlayer(String playerId) async {
    try {
      await _api?.stopPlayer(playerId);
    } catch (e) {
      _logger.log('❌ Failed to stop: $e');
      rethrow;
    }
  }

  Future<void> nextTrack(String playerId) async {
    try {
      await _api?.nextTrack(playerId);
    } catch (e) {
      _logger.log('❌ Failed to skip to next: $e');
      rethrow;
    }
  }

  Future<void> previousTrack(String playerId) async {
    try {
      await _api?.previousTrack(playerId);
    } catch (e) {
      _logger.log('❌ Failed to go to previous: $e');
      rethrow;
    }
  }

  Future<void> seek(String playerId, int positionSeconds) async {
    try {
      await _api?.seek(playerId, positionSeconds);
    } catch (e) {
      _logger.log('❌ Failed to seek: $e');
      rethrow;
    }
  }

  Future<void> seekRelative(String playerId, int deltaSeconds) async {
    final currentPosition = _positionTracker.currentPosition.inSeconds;
    await seek(playerId, (currentPosition + deltaSeconds).clamp(0, double.infinity).toInt());
  }

  Future<void> setVolume(String playerId, int volumeLevel) async {
    try {
      await _api?.setVolume(playerId, volumeLevel);
    } catch (e) {
      _logger.log('❌ Failed to set volume: $e');
      rethrow;
    }
  }

  // ============================================================================
  // TRACK PLAYBACK
  // ============================================================================

  Future<void> playTrack(String playerId, Track track, {bool clearQueue = true}) async {
    try {
      await _api?.playTrack(playerId, track, clearQueue: clearQueue);
    } catch (e) {
      _logger.log('❌ Failed to play track: $e');
      rethrow;
    }
  }

  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex, bool clearQueue = true}) async {
    try {
      await _api?.playTracks(playerId, tracks, startIndex: startIndex, clearQueue: clearQueue);

      if (tracks.isNotEmpty && startIndex != null && startIndex < tracks.length) {
        _currentTrack = tracks[startIndex];
      } else if (tracks.isNotEmpty) {
        _currentTrack = tracks.first;
      }

      notifyListeners();
      onTrackChanged?.call();
    } catch (e) {
      _logger.log('❌ Failed to play tracks: $e');
      rethrow;
    }
  }

  // ============================================================================
  // QUEUE MANAGEMENT
  // ============================================================================

  Future<PlayerQueue?> getQueue(String playerId) async {
    return _queueManager.getQueue(playerId);
  }

  // ============================================================================
  // POLLING AND STATE UPDATES
  // ============================================================================

  void _startPlayerStatePolling() {
    _playerStateTimer?.cancel();
    _playerStateTimer = Timer.periodic(
      Timings.playerPollingInterval,
      (_) => _updatePlayerState(),
    );
  }

  Future<void> _updatePlayerState() async {
    if (_selectedPlayer == null || _api == null) return;

    try {
      final playerId = _selectedPlayer!.playerId;
      final updatedPlayer = await _api?.getPlayer(playerId);

      if (updatedPlayer == null) {
        _logger.log('⚠️ _updatePlayerState: Player not found: $playerId');
        return;
      }

      // Check if player changed during fetch
      if (_selectedPlayer?.playerId != playerId) {
        _logger.log('⚠️ _updatePlayerState: Player changed during fetch, aborting');
        return;
      }

      final previousState = _selectedPlayer!.state;
      _selectedPlayer = updatedPlayer;

      // Update position tracker
      _positionTracker.updateFromServer(
        playerId: playerId,
        position: updatedPlayer.elapsedTime ?? 0.0,
        isPlaying: updatedPlayer.state == 'playing',
        duration: _currentTrack?.duration,
        serverTimestamp: updatedPlayer.elapsedTimeLastUpdated,
      );

      // Update notification if state changed
      if (previousState != updatedPlayer.state) {
        await _updateNotificationForPlayer(updatedPlayer);
      }

      notifyListeners();
    } catch (e) {
      _logger.log('⚠️ Error updating player state: $e');
    }
  }

  void _manageNotificationPositionTimer() {
    _notificationPositionTimer?.cancel();

    // Only for remote/Sendspin players
    final builtinPlayerId = _settings.getBuiltinPlayerIdSync();
    final isRemotePlayer = _selectedPlayer != null &&
        (builtinPlayerId == null || _selectedPlayer!.playerId != builtinPlayerId);

    if (isRemotePlayer && (_selectedPlayer?.state == 'playing' || _selectedPlayer?.state == 'paused')) {
      _notificationPositionTimer = Timer.periodic(
        Timings.notificationPositionUpdate,
        (_) => _updateNotificationPosition(),
      );
    }
  }

  void _updateNotificationPosition() {
    if (_currentTrack == null || _selectedPlayer == null) return;

    final position = _positionTracker.currentPosition;
    // Update notification position
    // (This would be handled by audio_handler internally)
  }

  // ============================================================================
  // SLEEP TIMER
  // ============================================================================

  Future<void> setSleepTimer(int? minutes) async {
    _sleepTimerProvider.setTimer(minutes);
    notifyListeners();
  }

  Future<void> cancelSleepTimer() async {
    _sleepTimerProvider.setTimer(null);
    notifyListeners();
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  Future<void> _loadCastToSendspinMappings() async {
    if (_castToSendspinIdMap.isEmpty) {
      try {
        final persistedMappings = await DatabaseService.instance.getAllCastToSendspinMappings();
        _castToSendspinIdMap.addAll(persistedMappings);
        if (persistedMappings.isNotEmpty) {
          _logger.log('🔗 Loaded ${persistedMappings.length} Cast->Sendspin mappings from database');
        }
      } catch (e) {
        _logger.log('⚠️ Failed to load Cast->Sendspin mappings: $e');
      }
    }
  }

  List<Player> _filterPlayers(List<Player> allPlayers, String? builtinPlayerId) {
    return PlayerSortUtility.filterPlayers(
      allPlayers,
      builtinPlayerId: builtinPlayerId,
    );
  }

  Future<void> _handleSendspinPlayers() async {
    // Complex Sendspin/Cast player switching logic
    // This would need to be extracted fully
    // For now, we'll keep a simplified version
  }

  void _sortPlayersSync(bool smartSort, String? builtinPlayerId) {
    PlayerSortUtility.sortPlayers(
      _availablePlayers,
      smartSort: smartSort,
      builtinPlayerId: builtinPlayerId,
    );
  }

  Player? _selectBestPlayer(String? builtinPlayerId) {
    return PlayerSortUtility.selectBestPlayer(
      availablePlayers: _availablePlayers,
      lastSelectedPlayer: null, // Could load from settings
      lastActivePlayer: null,
      builtinPlayerId: builtinPlayerId,
    );
  }

  void _startIdleServiceTimer() {
    _idleServiceTimer?.cancel();
    _idleServiceTimer = Timer(const Duration(minutes: 30), () {
      // After 30 min idle, stop position tracking
      _positionTracker.clear();
    });
  }

  void _cancelIdleServiceTimer() {
    _idleServiceTimer?.cancel();
  }

  // ============================================================================
  // CLEANUP
  // ============================================================================

  @override
  void dispose() {
    _playerStateTimer?.cancel();
    _notificationPositionTimer?.cancel();
    _idleServiceTimer?.cancel();
    super.dispose();
  }
}
