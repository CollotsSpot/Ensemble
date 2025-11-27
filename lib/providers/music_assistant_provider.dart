import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';
import '../services/local_player_service.dart';

class MusicAssistantProvider with ChangeNotifier {
  MusicAssistantAPI? _api;
  final AuthService _authService = AuthService();
  final DebugLogger _logger = DebugLogger();
  final LocalPlayerService _localPlayer = LocalPlayerService();
  
  MAConnectionState _connectionState = MAConnectionState.disconnected;
  String? _serverUrl;

  List<Artist> _artists = [];
  List<Album> _albums = [];
  List<Track> _tracks = [];
  bool _isLoading = false;
  String? _error;

  // Player selection
  Player? _selectedPlayer;
  List<Player> _availablePlayers = [];
  Track? _currentTrack; // Current track playing on selected player
  Timer? _playerStateTimer;
  
  // Local Playback
  bool _isLocalPlaybackEnabled = false;
  bool _isLocalPlayerPowered = true; // Track local player power state
  StreamSubscription? _localPlayerEventSubscription;
  Timer? _localPlayerStateReportTimer;

  // Player list caching
  DateTime? _playersLastFetched;
  static const Duration _playersCacheDuration = Duration(minutes: 5);

  MAConnectionState get connectionState => _connectionState;
  String? get serverUrl => _serverUrl;
  List<Artist> get artists => _artists;
  List<Album> get albums => _albums;
  List<Track> get tracks => _tracks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _connectionState == MAConnectionState.connected;

  // Search state persistence
  String _lastSearchQuery = '';
  Map<String, List<MediaItem>> _lastSearchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
  };

  String get lastSearchQuery => _lastSearchQuery;
  Map<String, List<MediaItem>> get lastSearchResults => _lastSearchResults;

  void saveSearchState(String query, Map<String, List<MediaItem>> results) {
    _lastSearchQuery = query;
    _lastSearchResults = results;
    // No notifyListeners() needed here as SearchScreen manages its own UI updates
    // and just reads this on init
  }

  void clearSearchState() {
    _lastSearchQuery = '';
    _lastSearchResults = {
      'artists': [],
      'albums': [],
      'tracks': [],
    };
  }

  // Player selection getters
  Player? get selectedPlayer => _selectedPlayer;
  List<Player> get availablePlayers => _availablePlayers;
  Track? get currentTrack => _currentTrack;

  // Debug: Get ALL players including filtered ones
  Future<List<Player>> getAllPlayersUnfiltered() async {
    return await getPlayers();
  }

  // API access
  MusicAssistantAPI? get api => _api;

  MusicAssistantProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    _serverUrl = await SettingsService.getServerUrl();
    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      // Auto-login if credentials are saved
      final username = await SettingsService.getUsername();
      final password = await SettingsService.getPassword();

      if (username != null && password != null && username.isNotEmpty && password.isNotEmpty) {
        try {
          await _authService.login(_serverUrl!, username, password);
        } catch (e) {
          // Auto-login failed, continue anyway
        }
      }

      await connectToServer(_serverUrl!);
      
      // Initialize local playback if enabled
      _isLocalPlaybackEnabled = await SettingsService.getEnableLocalPlayback();
      if (_isLocalPlaybackEnabled) {
        await _initializeLocalPlayback();
      }
    }
  }

  Future<void> _initializeLocalPlayback() async {
    await _localPlayer.initialize();
    _isLocalPlayerPowered = true; // Default to powered on when enabling local playback
    if (isConnected) {
      await _registerLocalPlayer();
    }
  }

  Future<void> _registerLocalPlayer() async {
    if (_api == null) return;
    
    final playerId = await SettingsService.getBuiltinPlayerId();
    final name = await SettingsService.getLocalPlayerName();
    
    if (playerId != null) {
      await _api!.registerBuiltinPlayer(playerId, name);
      _startReportingLocalPlayerState();
    }
  }
  
  void _startReportingLocalPlayerState() {
    _localPlayerStateReportTimer?.cancel();
    // Report state every second (for smooth seek bar)
    _localPlayerStateReportTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _reportLocalPlayerState();
    });
  }
  
  Future<void> _reportLocalPlayerState() async {
    if (_api == null || !_isLocalPlaybackEnabled) return;

    final playerId = await SettingsService.getBuiltinPlayerId();
    if (playerId == null) return;

    final position = _localPlayer.position.inSeconds.toDouble();
    final duration = _localPlayer.duration.inSeconds.toDouble();

    // Robust state mapping logic
    final playerState = _localPlayer.playerState;
    final processingState = playerState.processingState;
    final isPlaying = playerState.playing;

    String state = 'stopped'; // Default to 'stopped' (safe value)

    if (isPlaying) {
      state = 'playing';
    } else {
      // Not playing, check processing state
      switch (processingState) {
        case ProcessingState.idle:
          state = 'stopped'; // 'idle' was rejected by server, using 'stopped'
          break;
        case ProcessingState.loading:
        case ProcessingState.buffering:
          state = 'playing'; // Report as playing while loading to avoid flicker
          break;
        case ProcessingState.ready:
          state = 'paused';
          break;
        case ProcessingState.completed:
          state = 'stopped';
          break;
      }
    }

    await _api!.updateBuiltinPlayerState(
      playerId,
      state: state,
      elapsedTime: position,
      totalTime: duration > 0 ? duration : null,
      powered: _isLocalPlayerPowered,
      available: true, // Local player is always available when enabled
    );
  }

  Future<void> connectToServer(String serverUrl) async {
    try {
      _error = null;
      _serverUrl = serverUrl;
      await SettingsService.setServerUrl(serverUrl);

      // Disconnect existing connection
      await _api?.disconnect();

      _api = MusicAssistantAPI(serverUrl);

      // Listen to connection state changes
      _api!.connectionState.listen((state) {
        _connectionState = state;
        notifyListeners();

        if (state == MAConnectionState.connected) {
          // Load available players and auto-select
          _loadAndSelectPlayers();

          // Auto-load library when connected
          loadLibrary();
          
          // Re-register local player if enabled
          if (_isLocalPlaybackEnabled) {
            _registerLocalPlayer();
          }
        } else if (state == MAConnectionState.disconnected) {
          _availablePlayers = [];
          _selectedPlayer = null;
        }
      });
      
      // Listen to built-in player events
      _localPlayerEventSubscription?.cancel();
      _localPlayerEventSubscription = _api!.builtinPlayerEvents.listen(_handleLocalPlayerEvent);

      await _api!.connect();
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Connect to server');
      _error = errorInfo.userMessage;
      _connectionState = MAConnectionState.error;
      _logger.log('Connection error: ${errorInfo.technicalMessage}');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _handleLocalPlayerEvent(Map<String, dynamic> event) async {
    if (!_isLocalPlaybackEnabled) return;

    _logger.log('📥 Local player event received: ${event['command']}');

    try {
      final command = event['command'] as String?;
      
      switch (command) {
        case 'play_media':
          final url = event['url'] as String?;
          if (url != null) {
            await _localPlayer.playUrl(url);
          }
          break;

        case 'stop':
          await _localPlayer.stop();
          break;

        case 'pause':
          await _localPlayer.pause();
          break;

        case 'play':
          await _localPlayer.play();
          break;

        case 'seek':
          final position = event['position'] as int?;
          if (position != null) {
            await _localPlayer.seek(Duration(seconds: position));
          }
          break;

        case 'volume_set':
          final volume = event['volume_level'] as int?;
          if (volume != null) {
            await _localPlayer.setVolume(volume / 100.0);
          }
          break;

        case 'power':
          _logger.log('🔋 POWER COMMAND RECEIVED!');
          final powered = event['powered'] as bool?;
          _logger.log('🔋 Power value from event: $powered');
          if (powered != null) {
            _isLocalPlayerPowered = powered;
            _logger.log('🔋 Local player power set to: $powered');
            if (!powered) {
              // When powered off, stop playback
              _logger.log('🔋 Stopping playback because powered off');
              await _localPlayer.stop();
            }
          } else {
            _logger.log('🔋 WARNING: power value is null in event');
          }
          break;
      }
      
      // Report state immediately after command
      await _reportLocalPlayerState();
      
    } catch (e) {
      _logger.log('Error handling local player event: $e');
    }
  }
  
  Future<void> enableLocalPlayback() async {
    _isLocalPlaybackEnabled = true;
    await SettingsService.setEnableLocalPlayback(true);
    await _initializeLocalPlayback();
    notifyListeners();
  }
  
  Future<void> disableLocalPlayback() async {
    _isLocalPlaybackEnabled = false;
    await SettingsService.setEnableLocalPlayback(false);
    await _localPlayer.stop();
    _localPlayerStateReportTimer?.cancel();
    // Ideally unregister from server here if API supports it
    notifyListeners();
  }

  Future<void> disconnect() async {
    _playerStateTimer?.cancel();
    _playerStateTimer = null;
    _localPlayerStateReportTimer?.cancel();
    _localPlayerEventSubscription?.cancel();
    await _api?.disconnect();
    _connectionState = MAConnectionState.disconnected;
    _artists = [];
    _albums = [];
    _tracks = [];
    _currentTrack = null;
    notifyListeners();
  }

  Future<void> loadLibrary() async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Load artists, albums, and tracks in parallel
      // Use a high limit to fetch "all" items (assuming library < 5000 items per type)
      final results = await Future.wait([
        _api!.getArtists(limit: 5000),
        _api!.getAlbums(limit: 5000),
        _api!.getTracks(limit: 5000),
      ]);

      _artists = results[0] as List<Artist>;
      _albums = results[1] as List<Album>;
      _tracks = results[2] as List<Track>;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load library');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadArtists({int? limit, int? offset, String? search}) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _artists = await _api!.getArtists(
        limit: limit ?? 5000, // Default to high limit if not specified
        offset: offset,
        search: search,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load artists');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAlbums({
    int? limit,
    int? offset,
    String? search,
    String? artistId,
  }) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _albums = await _api!.getAlbums(
        limit: limit ?? 5000, // Default to high limit
        offset: offset,
        search: search,
        artistId: artistId,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load albums');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Track>> getAlbumTracks(String provider, String itemId) async {
    if (!isConnected) return [];

    try {
      return await _api!.getAlbumTracks(provider, itemId);
    } catch (e) {
      ErrorHandler.logError('Get album tracks', e);
      return [];
    }
  }

  Future<Map<String, List<MediaItem>>> search(String query, {bool libraryOnly = false}) async {
    if (!isConnected) {
      return {'artists': [], 'albums': [], 'tracks': []};
    }

    try {
      return await _api!.search(query, libraryOnly: libraryOnly);
    } catch (e) {
      ErrorHandler.logError('Search', e);
      return {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  String getStreamUrl(String provider, String itemId, {String? uri, List<ProviderMapping>? providerMappings}) {
    return _api?.getStreamUrl(provider, itemId, uri: uri, providerMappings: providerMappings) ?? '';
  }

  String? getImageUrl(MediaItem item, {int size = 256}) {
    return _api?.getImageUrl(item, size: size);
  }

  // ============================================================================
  // PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  Future<List<Player>> getPlayers() async {
    return await _api?.getPlayers() ?? [];
  }

  Future<PlayerQueue?> getQueue(String playerId) async {
    return await _api?.getQueue(playerId);
  }

  Future<void> playTrack(String playerId, Track track, {bool clearQueue = true}) async {
    try {
      await _api?.playTrack(playerId, track, clearQueue: clearQueue);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play track');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play track', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex, bool clearQueue = true}) async {
    try {
      await _api?.playTracks(playerId, tracks, startIndex: startIndex, clearQueue: clearQueue);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play tracks');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play tracks', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playRadio(String playerId, Track track) async {
    try {
      await _api?.playRadio(playerId, track);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play radio');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play radio', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<String?> getCurrentStreamUrl(String playerId) async {
    return await _api?.getCurrentStreamUrl(playerId);
  }

  Future<void> pausePlayer(String playerId) async {
    try {
      await _api?.pausePlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Pause player', e);
      rethrow;
    }
  }

  Future<void> resumePlayer(String playerId) async {
    try {
      await _api?.resumePlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Resume player', e);
      rethrow;
    }
  }

  Future<void> nextTrack(String playerId) async {
    try {
      await _api?.nextTrack(playerId);
    } catch (e) {
      ErrorHandler.logError('Next track', e);
      rethrow;
    }
  }

  Future<void> previousTrack(String playerId) async {
    try {
      await _api?.previousTrack(playerId);
    } catch (e) {
      ErrorHandler.logError('Previous track', e);
      rethrow;
    }
  }

  Future<void> stopPlayer(String playerId) async {
    try {
      await _api?.stopPlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Stop player', e);
      rethrow;
    }
  }

  Future<void> togglePower(String playerId) async {
    try {
      _logger.log('🔋 togglePower called for playerId: $playerId');

      // Check if this is the local builtin player
      final localPlayerId = await SettingsService.getBuiltinPlayerId();
      final isLocalPlayer = localPlayerId != null && playerId == localPlayerId;

      _logger.log('🔋 Is local builtin player: $isLocalPlayer (local ID: $localPlayerId)');

      if (isLocalPlayer && _isLocalPlaybackEnabled) {
        // For builtin player, manage power state locally
        _logger.log('🔋 Handling power toggle LOCALLY for builtin player');

        // Toggle the local power state
        _isLocalPlayerPowered = !_isLocalPlayerPowered;
        _logger.log('🔋 Local player power set to: $_isLocalPlayerPowered');

        // If powering off, stop playback
        if (!_isLocalPlayerPowered) {
          _logger.log('🔋 Stopping playback because powered off');
          await _localPlayer.stop();
        }

        // Report the new state to the server immediately
        await _reportLocalPlayerState();

        // Refresh player list to update UI
        await refreshPlayers();
      } else {
        // For regular MA players, send power command to server
        _logger.log('🔋 Sending power command to server for regular player');

        final player = _availablePlayers.firstWhere(
          (p) => p.playerId == playerId,
          orElse: () => _selectedPlayer != null && _selectedPlayer!.playerId == playerId
              ? _selectedPlayer!
              : throw Exception("Player not found"),
        );

        _logger.log('🔋 Current power state: ${player.powered}, will set to: ${!player.powered}');

        // Toggle the state
        await _api?.setPower(playerId, !player.powered);

        _logger.log('🔋 setPower command sent successfully');

        // Immediately refresh players to update UI
        await refreshPlayers();
      }
    } catch (e) {
      _logger.log('🔋 ERROR in togglePower: $e');
      ErrorHandler.logError('Toggle power', e);
      // Don't rethrow to avoid crashing UI, just log
    }
  }

  Future<void> setVolume(String playerId, int volumeLevel) async {
    try {
      await _api?.setVolume(playerId, volumeLevel);
      // Don't refresh immediately - let automatic polling pick up the change
      // This prevents the slider from snapping back before the server updates
    } catch (e) {
      ErrorHandler.logError('Set volume', e);
      rethrow;
    }
  }

  Future<void> setMute(String playerId, bool muted) async {
    try {
      await _api?.setMute(playerId, muted);
      // Refresh player state to get updated mute status
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Set mute', e);
      rethrow;
    }
  }

  Future<void> seek(String playerId, int position) async {
    try {
      await _api?.seek(playerId, position);
      // Player state will be updated on next poll
    } catch (e) {
      ErrorHandler.logError('Seek', e);
      rethrow;
    }
  }

  Future<void> toggleShuffle(String queueId) async {
    try {
      await _api?.toggleShuffle(queueId);
      // Queue state will be updated on next poll
    } catch (e) {
      ErrorHandler.logError('Toggle shuffle', e);
      rethrow;
    }
  }

  Future<void> setRepeatMode(String queueId, String mode) async {
    try {
      await _api?.setRepeatMode(queueId, mode);
      // Queue state will be updated on next poll
    } catch (e) {
      ErrorHandler.logError('Set repeat mode', e);
      rethrow;
    }
  }

  /// Cycle through repeat modes: off -> all -> one -> off
  Future<void> cycleRepeatMode(String queueId, String? currentMode) async {
    String nextMode;
    switch (currentMode) {
      case 'off':
      case null:
        nextMode = 'all';
        break;
      case 'all':
        nextMode = 'one';
        break;
      case 'one':
        nextMode = 'off';
        break;
      default:
        nextMode = 'off';
    }
    await setRepeatMode(queueId, nextMode);
  }

  // ============================================================================
  // END PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  // ============================================================================
  // PLAYER SELECTION
  // ============================================================================

  /// Load available players and auto-select one
  Future<void> _loadAndSelectPlayers({bool forceRefresh = false}) async {
    try {
      // Check cache first
      final now = DateTime.now();
      if (!forceRefresh &&
          _playersLastFetched != null &&
          _availablePlayers.isNotEmpty &&
          now.difference(_playersLastFetched!) < _playersCacheDuration) {
        return;
      }

      final allPlayers = await getPlayers();
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();

      // Filter out ghost players and duplicates
      // 1. "Music Assistant Mobile" players are legacy/ghosts (created by old versions)
      // 2. Valid players are those matching our current builtinPlayerId (if any)
      
      int filteredCount = 0;
      final List<String> ghostPlayerIds = [];

      _availablePlayers = allPlayers.where((player) {
        final nameLower = player.name.toLowerCase();

        // Filter out legacy "Music Assistant Mobile" ghosts
        if (nameLower.contains('music assistant mobile')) {
          filteredCount++;
          ghostPlayerIds.add('${player.playerId} (Mobile Ghost)');
          return false;
        }

        // "This Device" / Local Players
        // If this player matches OUR persistent ID, keep it (it's us!)
        if (builtinPlayerId != null && player.playerId == builtinPlayerId) {
          return true;
        }

        // If it's some OTHER "This Device" (from another installation/device), keep it too
        // We only strictly filter the known "Music Assistant Mobile" ghosts
        
        return true;
      }).toList();

      _playersLastFetched = DateTime.now();


      if (_availablePlayers.isNotEmpty) {
        // Smart player selection logic:
        // 1. If a player is already selected and still available, keep it (ALWAYS)
        // 2. Only auto-select a player if none is currently selected
        // 3. Prefer a playing player, then first available player

        Player? playerToSelect;

        // Keep current selection if still valid - ALWAYS prefer this
        if (_selectedPlayer != null) {
          final stillAvailable = _availablePlayers.any(
            (p) => p.playerId == _selectedPlayer!.playerId && p.available,
          );
          if (stillAvailable) {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.playerId == _selectedPlayer!.playerId,
            );
          }
        }

        // Only auto-select if NO player is currently selected
        if (playerToSelect == null) {
          // Try to find a playing player first
          try {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.state == 'playing' && p.available,
            );
          } catch (e) {
            // No playing player found, pick first available
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.available,
              orElse: () => _availablePlayers.first,
            );
          }
        }

        selectPlayer(playerToSelect);
      }

      // Don't call notifyListeners here - selectPlayer already does it
    } catch (e) {
      ErrorHandler.logError('Load and select players', e);
    }
  }

  /// Select a player for playback
  void selectPlayer(Player player, {bool skipNotify = false}) {
    _selectedPlayer = player;

    // Start polling for player state
    _startPlayerStatePolling();

    if (!skipNotify) {
      notifyListeners();
    }
  }

  /// Start polling for selected player's current state
  void _startPlayerStatePolling() {
    _playerStateTimer?.cancel();

    if (_selectedPlayer == null) return;

    // Poll every 5 seconds for better performance
    _playerStateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updatePlayerState();
    });

    // Also update immediately
    _updatePlayerState();
  }

  /// Update the selected player's current state
  Future<void> _updatePlayerState() async {
    if (_selectedPlayer == null || _api == null) return;

    try {
      bool stateChanged = false;

      // Fetch only the selected player's state instead of all players
      final allPlayers = await getPlayers();
      final updatedPlayer = allPlayers.firstWhere(
        (p) => p.playerId == _selectedPlayer!.playerId,
        orElse: () => _selectedPlayer!,
      );

      // Check if player state actually changed
      if (updatedPlayer.state != _selectedPlayer!.state ||
          updatedPlayer.volumeLevel != _selectedPlayer!.volumeLevel ||
          updatedPlayer.volumeMuted != _selectedPlayer!.volumeMuted ||
          updatedPlayer.available != _selectedPlayer!.available) {
        _selectedPlayer = updatedPlayer;
        stateChanged = true;
      }

      // Only show tracks if player is available and not idle
      final shouldShowTrack = _selectedPlayer!.available &&
                             (_selectedPlayer!.state == 'playing' || _selectedPlayer!.state == 'paused');

      if (!shouldShowTrack) {
        // Clear track if player is unavailable or idle
        if (_currentTrack != null) {
          _currentTrack = null;
          stateChanged = true;
        }

        if (stateChanged) {
          notifyListeners();
        }
        return;
      }

      // Get the player's queue
      final queue = await getQueue(_selectedPlayer!.playerId);

      if (queue != null && queue.currentItem != null) {
        // Only update if track actually changed
        if (_currentTrack == null ||
            _currentTrack!.uri != queue.currentItem!.track.uri ||
            _currentTrack!.name != queue.currentItem!.track.name) {
          _currentTrack = queue.currentItem!.track;
          stateChanged = true;
        }
      } else {
        if (_currentTrack != null) {
          // Clear current track if queue is empty
          _currentTrack = null;
          stateChanged = true;
        }
      }

      // Only notify if something actually changed
      if (stateChanged) {
        notifyListeners();
      }
    } catch (e) {
      _logger.log('❌ Error updating player state: $e');
    }
  }

  /// Control the selected player
  Future<void> playPauseSelectedPlayer() async {
    if (_selectedPlayer == null) {
      return;
    }

    if (_selectedPlayer!.isPlaying) {
      await pausePlayer(_selectedPlayer!.playerId);
    } else {
      await resumePlayer(_selectedPlayer!.playerId);
    }

    // Refresh player state immediately
    await refreshPlayers();
  }

  Future<void> nextTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await nextTrack(_selectedPlayer!.playerId);
    await Future.delayed(const Duration(milliseconds: 500));
    await _updatePlayerState();
  }

  Future<void> previousTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await previousTrack(_selectedPlayer!.playerId);
    await Future.delayed(const Duration(milliseconds: 500));
    await _updatePlayerState();
  }

  /// Refresh the list of available players
  Future<void> refreshPlayers() async {
    final previousState = _selectedPlayer?.state;
    final previousVolume = _selectedPlayer?.volumeLevel;

    await _loadAndSelectPlayers(forceRefresh: true);

    // Update the selected player with fresh data
    bool stateChanged = false;
    if (_selectedPlayer != null && _availablePlayers.isNotEmpty) {
      try {
        final updatedPlayer = _availablePlayers.firstWhere(
          (p) => p.playerId == _selectedPlayer!.playerId,
        );

        // Check if state actually changed
        if (updatedPlayer.state != previousState ||
            updatedPlayer.volumeLevel != previousVolume) {
          stateChanged = true;
        }

        _selectedPlayer = updatedPlayer;
      } catch (e) {
        // Selected player no longer available
        stateChanged = true;
      }
    }

    // Only notify if state changed
    if (stateChanged) {
      notifyListeners();
    }
  }

  // ============================================================================
  // END PLAYER SELECTION
  // ============================================================================

  /// Check connection and reconnect if needed (called when app resumes)
  Future<void> checkAndReconnect() async {
    if (_api == null || _serverUrl == null) {
      return;
    }

    // Check if we're disconnected
    if (_connectionState != MAConnectionState.connected) {
      try {
        await connectToServer(_serverUrl!);
      } catch (e) {
        // Reconnection failed, will try again later
      }
    } else {
      // Even if connected, refresh player state
      await refreshPlayers();
    }
  }

  @override
  void dispose() {
    _playerStateTimer?.cancel();
    _api?.dispose();
    super.dispose();
  }
}
