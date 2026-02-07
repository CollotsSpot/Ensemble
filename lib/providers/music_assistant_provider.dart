import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import '../models/provider_instance.dart';
import '../models/provider_manifest.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';
import '../services/auth/auth_manager.dart';
import '../services/device_id_service.dart';
import '../services/cache_service.dart';
import '../services/recently_played_service.dart';
import '../services/sync_service.dart';
import '../services/local_player_service.dart';
import '../services/metadata_service.dart';
import '../services/position_tracker.dart';
import '../services/group_volume_manager.dart';
import '../services/sendspin_service.dart';
import '../services/pcm_audio_player.dart';
import '../services/offline_action_queue.dart';
import '../constants/timings.dart';
import '../services/database_service.dart';
import '../services/library_status_service.dart';
import '../main.dart' show audioHandler;

/// Main provider that coordinates connection, player, and library state.
///
/// This is a facade that delegates to internal services while maintaining
/// backward compatibility with existing code that uses MusicAssistantProvider.
///
/// Architecture:
/// - CacheService: Handles all caching (non-notifying)
/// - Connection logic: WebSocket, auth, reconnection
/// - Player logic: Player selection, controls, local player
/// - Library logic: Artists, albums, tracks, search
class MusicAssistantProvider with ChangeNotifier {
  MusicAssistantAPI? _api;
  final AuthManager _authManager = AuthManager();
  final DebugLogger _logger = DebugLogger();
  final CacheService _cacheService = CacheService();
  final PositionTracker _positionTracker = PositionTracker();
  final GroupVolumeManager _groupVolumeManager = GroupVolumeManager();

  MAConnectionState _connectionState = MAConnectionState.disconnected;
  String? _serverUrl;
  String? _error;

  // Library state
  List<Artist> _artists = [];
  List<Album> _albums = [];
  List<Track> _tracks = [];
  List<Track> _cachedFavoriteTracks = []; // Cached for instant display before full library loads
  List<MediaItem> _radioStations = [];
  List<MediaItem> _podcasts = [];
  bool _isLoading = false;
  bool _isLoadingRadio = false;
  bool _isLoadingPodcasts = false;

  // Player state
  Player? _selectedPlayer;
  List<Player> _availablePlayers = [];
  bool _selectPlayerInProgress = false; // Reentrancy guard for selectPlayer()
  Map<String, String> _castToSendspinIdMap = {}; // Maps regular Cast IDs to Sendspin IDs for grouping

  // Pending volume cache: prevents stale API data from overwriting optimistic
  // volume updates in _updatePlayerState() and refreshPlayers().
  // Key: playerId, Value: volume level (0-100)
  final Map<String, int> _pendingVolumes = {};
  final Map<String, int> _pendingVolumeTimestamps = {}; // millisecondsSinceEpoch
  static const int _pendingVolumeTimeoutMs = 8000; // 8s for non-group players
  static const int _pendingVolumeTimeoutGroupMs = 30000; // 30s for group players (API returns null)
  static const int _pendingVolumeTolerancePoints = 3; // Confirm if within ±3 points

  Track? _currentTrack;
  Audiobook? _currentAudiobook; // Currently playing audiobook context (with chapters)
  String? _currentPodcastName; // Currently playing podcast's name (set when playing episode)
  Timer? _playerStateTimer;
  Timer? _notificationPositionTimer; // Updates notification position every second for remote players

  // Sleep timer state
  Timer? _sleepTimer;
  DateTime? _sleepTimerEndTime;
  int? _sleepTimerMinutes; // null = off, -1 = end of track, positive = minutes
  Timer? _sleepTimerDisplayTimer; // Updates remaining time display every second

  // Idle service timeout - stops foreground service after 30 min of no playback
  Timer? _idleServiceTimer;
  static const _idleServiceTimeout = Duration(minutes: 30);

  // Local player state
  bool _isLocalPlayerPowered = true;
  int _localPlayerVolume = 100; // Tracked MA volume for builtin player (0-100)
  bool _builtinPlayerAvailable = true; // False on MA 2.7.0b20+ (uses Sendspin instead)
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _localPlayerEventSubscription;
  StreamSubscription? _playerUpdatedEventSubscription;
  StreamSubscription? _playerAddedEventSubscription;
  StreamSubscription? _mediaItemAddedEventSubscription;
  StreamSubscription? _mediaItemDeletedEventSubscription;
  Timer? _localPlayerStateReportTimer;
  TrackMetadata? _pendingTrackMetadata;
  TrackMetadata? _currentNotificationMetadata;
  Completer<void>? _registrationInProgress;

  // Local player service
  late final LocalPlayerService _localPlayer;

  // Sendspin service (MA 2.7.0b20+ replacement for builtin_player)
  SendspinService? _sendspinService;
  bool _sendspinConnected = false;

  // PCM audio player for raw Sendspin audio streaming
  PcmAudioPlayer? _pcmAudioPlayer;

  // Search state persistence
  String _lastSearchQuery = '';
  Map<String, List<MediaItem>> _lastSearchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
  };

  // Podcast cover cache: podcastId -> best available cover URL
  // This is populated with episode covers when podcast covers are low-res
  final Map<String, String> _podcastCoverCache = {};

  // Provider filter: list of allowed provider instance IDs from MA user settings
  // Empty list means all providers are allowed
  List<String> _providerFilter = [];

  // Player filter: list of allowed player IDs from MA user settings
  // Empty list means all players are allowed
  List<String> _playerFilter = [];

  // User-controlled music provider filter (local settings in Ensemble)
  // Empty list means all providers are enabled (no filtering)
  List<String> _enabledProviderIds = [];

  // Available music providers discovered from MA
  List<ProviderInstance> _availableMusicProviders = [];

  // ============================================================================
  // GETTERS
  // ============================================================================

  MAConnectionState get connectionState => _connectionState;
  String? get serverUrl => _serverUrl;
  String? get error => _error;
  bool get isConnected => _connectionState == MAConnectionState.connected ||
                          _connectionState == MAConnectionState.authenticated;

  // Library getters with provider filtering applied
  List<Artist> get artists => filterByProvider(_artists);
  List<Album> get albums => filterByProvider(_albums);
  List<Track> get tracks => filterByProvider(_tracks);
  List<MediaItem> get radioStations => filterByProvider(_radioStations);
  List<MediaItem> get podcasts => filterByProvider(_podcasts);

  // Raw unfiltered access (for internal use only)
  List<Artist> get artistsUnfiltered => _artists;
  List<Album> get albumsUnfiltered => _albums;
  List<MediaItem> get podcastsUnfiltered => _podcasts;
  List<MediaItem> get radioStationsUnfiltered => _radioStations;
  bool get isLoading => _isLoading;
  bool get isLoadingRadio => _isLoadingRadio;
  bool get isLoadingPodcasts => _isLoadingPodcasts;

  /// Provider filter from MA user settings (empty = all providers allowed)
  List<String> get providerFilter => _providerFilter;

  /// Whether provider filtering is active
  bool get hasProviderFilter => _providerFilter.isNotEmpty;

  /// Check if a media item should be visible based on provider filter
  /// Returns true if:
  /// - No filter is active (empty list = all providers allowed)
  /// - The item has at least one provider mapping in the allowed list
  /// - The item's primary provider is in the allowed list
  bool isItemAllowedByProviderFilter(MediaItem item) {
    // No filter = show everything
    if (_providerFilter.isEmpty) return true;

    // Check if item's provider mappings include any allowed provider
    final mappings = item.providerMappings;
    if (mappings != null && mappings.isNotEmpty) {
      for (final mapping in mappings) {
        if (_providerFilter.contains(mapping.providerInstance)) {
          return true;
        }
      }
    }

    // Also check primary provider field (for items without full mappings)
    if (_providerFilter.contains(item.provider)) {
      return true;
    }

    return false;
  }

  /// Filter a list of media items based on provider filter
  List<T> filterByProvider<T extends MediaItem>(List<T> items) {
    if (_providerFilter.isEmpty) return items;
    return items.where(isItemAllowedByProviderFilter).toList();
  }

  /// Filter search results map based on provider filter
  Map<String, List<MediaItem>> filterSearchResults(Map<String, List<MediaItem>> results) {
    if (_providerFilter.isEmpty) return results;
    return {
      for (final entry in results.entries)
        entry.key: entry.value.where(isItemAllowedByProviderFilter).toList(),
    };
  }

  /// Player filter from MA user settings (empty = all players allowed)
  List<String> get playerFilter => _playerFilter;

  /// Whether player filtering is active
  bool get hasPlayerFilter => _playerFilter.isNotEmpty;

  /// Check if a player should be visible based on player filter
  bool isPlayerAllowedByFilter(Player player) {
    if (_playerFilter.isEmpty) return true;
    return _playerFilter.contains(player.playerId);
  }

  /// Filter a list of players based on player filter
  List<Player> filterPlayers(List<Player> players) {
    if (_playerFilter.isEmpty) return players;
    return players.where(isPlayerAllowedByFilter).toList();
  }

  // ============================================================================
  // USER-CONTROLLED MUSIC PROVIDER FILTER
  // ============================================================================

  /// List of available music providers from MA
  List<ProviderInstance> get availableMusicProviders => _availableMusicProviders;

  /// Get all provider manifests (contains icons)
  Map<String, ProviderManifest> get providerManifests =>
      _api?.providerManifests ?? {};

  /// Get SVG icon for a provider domain
  /// Returns null if no icon is available
  String? getProviderIconSvg(String domain, {bool isDark = false}) {
    return _api?.getProviderIconSvg(domain, isDark: isDark);
  }

  /// Get provider manifest by domain
  ProviderManifest? getProviderManifest(String domain) {
    return _api?.getProviderManifest(domain);
  }

  /// List of enabled provider instance IDs (empty = all enabled)
  List<String> get enabledProviderIds => _enabledProviderIds;

  /// Whether user has enabled specific providers (not all)
  bool get hasUserProviderFilter => _enabledProviderIds.isNotEmpty;

  /// Get provider IDs to pass to API calls
  /// Returns null if all providers are enabled (no filtering needed)
  /// Returns the list of enabled provider IDs otherwise
  List<String>? get providerIdsForApiCalls {
    if (_enabledProviderIds.isEmpty) return null; // All enabled
    return _enabledProviderIds;
  }

  /// Check if a specific provider is enabled by the user
  bool isProviderEnabled(String instanceId) {
    if (_enabledProviderIds.isEmpty) return true; // All enabled by default
    return _enabledProviderIds.contains(instanceId);
  }

  /// Get providers that have content in artists library (with item counts)
  Map<String, int> getProvidersWithArtists() {
    return _getProvidersWithCounts(_artists);
  }

  /// Get providers that have content in albums library (with item counts)
  Map<String, int> getProvidersWithAlbums() {
    return _getProvidersWithCounts(_albums);
  }

  /// Get providers that have content in tracks library (with item counts)
  Map<String, int> getProvidersWithTracks() {
    return _getProvidersWithCounts(_tracks);
  }

  /// Get providers that have content in playlists (with item counts)
  Map<String, int> getProvidersWithPlaylists() {
    return _getProvidersWithCounts(SyncService.instance.cachedPlaylists);
  }

  /// Get providers that have audiobooks (with item counts)
  Map<String, int> getProvidersWithAudiobooks() {
    return _getProvidersWithCounts(SyncService.instance.cachedAudiobooks);
  }

  /// Get providers that have radio stations (with item counts)
  Map<String, int> getProvidersWithRadio() {
    return _getProvidersWithCounts(_radioStations);
  }

  /// Get providers that have podcasts (with item counts)
  /// Only counts mappings where inLibrary is true - this indicates which provider
  /// the user actually added the podcast from (vs providers that can play it)
  Map<String, int> getProvidersWithPodcasts() {
    final counts = <String, int>{};
    for (final item in _podcasts) {
      final mappings = item.providerMappings;
      if (mappings != null) {
        for (final mapping in mappings) {
          // Only count if this provider "owns" the item (user added it from this account)
          if (mapping.inLibrary) {
            final instanceId = mapping.providerInstance;
            if (instanceId.isNotEmpty) {
              counts[instanceId] = (counts[instanceId] ?? 0) + 1;
            }
          }
        }
      }
    }
    return counts;
  }

  /// Internal helper to count items per provider from a list of media items
  /// Only counts mappings where inLibrary is true - this indicates which provider
  /// the user actually added the item from (vs providers that can play it)
  Map<String, int> _getProvidersWithCounts<T extends MediaItem>(List<T> items) {
    final counts = <String, int>{};
    for (final item in items) {
      final mappings = item.providerMappings;
      if (mappings != null) {
        for (final mapping in mappings) {
          // Only count if this provider "owns" the item (user added it from this account)
          if (mapping.inLibrary) {
            final instanceId = mapping.providerInstance;
            if (instanceId.isNotEmpty) {
              counts[instanceId] = (counts[instanceId] ?? 0) + 1;
            }
          }
        }
      }
    }
    return counts;
  }

  /// Get ProviderInstance objects for providers that have content in a category
  /// Returns list of (ProviderInstance, itemCount) tuples, sorted by name
  List<(ProviderInstance, int)> getRelevantProvidersForCategory(String category) {
    final Map<String, int> counts;
    switch (category) {
      case 'artists':
        counts = getProvidersWithArtists();
        break;
      case 'albums':
        counts = getProvidersWithAlbums();
        break;
      case 'tracks':
        counts = getProvidersWithTracks();
        break;
      case 'playlists':
        counts = getProvidersWithPlaylists();
        break;
      case 'audiobooks':
        counts = getProvidersWithAudiobooks();
        break;
      case 'radio':
        counts = getProvidersWithRadio();
        break;
      case 'podcasts':
        counts = getProvidersWithPodcasts();
        break;
      default:
        counts = {};
    }

    // Build list of providers that support this category, with their item counts
    // Only include providers that have at least 1 item (hides providers not synced to library)
    // Multiple instances of the same domain are allowed (e.g., two Spotify accounts)
    // but we dedupe if names match exactly (same account re-added with new instance ID)
    final result = <(ProviderInstance, int)>[];
    final addedInstanceIds = <String>{};
    final addedNames = <String, int>{}; // Track name -> count to dedupe same-name providers

    for (final provider in _availableMusicProviders) {
      // Only include providers that support this content type AND have items
      if (provider.supportsContentType(category)) {
        final count = counts[provider.instanceId] ?? 0;
        if (count > 0) {
          final existingCount = addedNames[provider.name];
          if (existingCount == null) {
            // First provider with this name
            result.add((provider, count));
            addedInstanceIds.add(provider.instanceId);
            addedNames[provider.name] = count;
          } else if (count > existingCount) {
            // Same name but more items - likely same account re-added, keep better one
            result.removeWhere((r) => r.$1.name == provider.name);
            result.add((provider, count));
            addedInstanceIds.add(provider.instanceId);
            addedNames[provider.name] = count;
          }
        }
      }
    }

    // Also include providers that have items but aren't in _availableMusicProviders
    // (e.g., search-only providers like iTunes, or orphaned items from removed providers)
    // For these synthetic providers, dedupe by domain since we don't have account-specific names
    final addedRealDomains = result.map((r) => r.$1.domain).toSet();
    final addedSyntheticDomains = <String>{};

    for (final entry in counts.entries) {
      if (!addedInstanceIds.contains(entry.key) && entry.value > 0) {
        // Create a synthetic ProviderInstance from the instance ID
        // Format is typically "domain--uniqueId" (e.g., "itunes--abc123")
        final instanceId = entry.key;
        final domain = instanceId.contains('--')
            ? instanceId.split('--').first
            : instanceId;

        // Skip if this domain is already represented by a real provider or synthetic
        if (addedRealDomains.contains(domain)) continue;
        if (addedSyntheticDomains.contains(domain)) continue;

        // Only add if this domain supports the category
        final capabilities = ProviderInstance.providerCapabilities[domain];
        if (capabilities != null && capabilities.contains(category)) {
          result.add((
            ProviderInstance(
              instanceId: instanceId,
              domain: domain,
              name: _formatProviderName(domain),
              available: true,
            ),
            entry.value,
          ));
          addedSyntheticDomains.add(domain);
        }
      }
    }

    // Sort by name
    result.sort((a, b) => a.$1.name.compareTo(b.$1.name));
    return result;
  }

  /// Format a provider domain into a readable display name
  String _formatProviderName(String domain) {
    const names = {
      'spotify': 'Spotify',
      'tidal': 'Tidal',
      'qobuz': 'Qobuz',
      'deezer': 'Deezer',
      'ytmusic': 'YouTube Music',
      'soundcloud': 'SoundCloud',
      'apple_music': 'Apple Music',
      'amazon_music': 'Amazon Music',
      'plex': 'Plex',
      'jellyfin': 'Jellyfin',
      'emby': 'Emby',
      'subsonic': 'Subsonic',
      'opensubsonic': 'OpenSubsonic',
      'navidrome': 'Navidrome',
      'audiobookshelf': 'Audiobookshelf',
      'filesystem': 'Filesystem',
      'itunes_podcasts': 'iTunes Podcasts',
      'tunein': 'TuneIn',
      'radiobrowser': 'Radio Browser',
    };
    return names[domain] ?? domain[0].toUpperCase() + domain.substring(1);
  }

  /// Whether library is syncing in background
  bool get isSyncing => SyncService.instance.isSyncing;

  /// Current sync status
  SyncStatus get syncStatus => SyncService.instance.status;

  /// Selected player - loads from cache if not yet set
  Player? get selectedPlayer {
    if (_selectedPlayer == null && _cacheService.getCachedSelectedPlayer() != null) {
      _selectedPlayer = _cacheService.getCachedSelectedPlayer();
    }
    return _selectedPlayer;
  }

  /// Available players - loads from cache for instant UI display
  /// Filtered by player_filter if active
  List<Player> get availablePlayers {
    if (_availablePlayers.isEmpty && _cacheService.hasCachedPlayers) {
      _availablePlayers = _cacheService.getCachedPlayers()!;
      _logger.log('⚡ Loaded ${_availablePlayers.length} players from cache (lazy)');
    }
    return filterPlayers(_availablePlayers);
  }

  /// Raw unfiltered players list (for internal use)
  List<Player> get availablePlayersUnfiltered => _availablePlayers;

  /// Group volume manager for resolving group player volumes
  GroupVolumeManager get groupVolumeManager => _groupVolumeManager;

  /// Check if a player should show the "manually synced" indicator (yellow border)
  /// Returns true for BOTH the leader AND children of a manually created sync group
  /// Excludes pre-configured MA speaker groups (provider = 'player_group')
  bool isPlayerManuallySynced(String playerId) {
    final player = _availablePlayers.where((p) => p.playerId == playerId).firstOrNull;
    if (player == null) return false;

    // Group players (like "All Speakers") should NEVER have yellow border
    // They are pre-configured containers, not manually synced players
    // Check this FIRST before any other logic to prevent edge cases
    if (player.provider == 'player_group') return false;

    // Case 1: Player is a child synced to another player
    if (player.syncedTo != null) {
      // Look up sync target - also check translated IDs for Cast+Sendspin players
      // The syncedTo might contain a Cast ID but the player list has the Sendspin version
      Player? syncTarget = _availablePlayers.where((p) => p.playerId == player.syncedTo).firstOrNull;

      // If not found, try looking up by translated Sendspin ID
      if (syncTarget == null) {
        final translatedId = _castToSendspinIdMap[player.syncedTo];
        if (translatedId != null) {
          syncTarget = _availablePlayers.where((p) => p.playerId == translatedId).firstOrNull;
        }
      }

      // Also check reverse: syncedTo might be Sendspin ID, look for Cast player
      if (syncTarget == null) {
        // Build reverse map on demand
        for (final entry in _castToSendspinIdMap.entries) {
          if (entry.value == player.syncedTo) {
            syncTarget = _availablePlayers.where((p) => p.playerId == entry.key).firstOrNull;
            if (syncTarget != null) break;
          }
        }
      }

      if (syncTarget == null) return false;

      // If synced to a group player, it's part of a pre-configured group
      if (syncTarget.provider == 'player_group') return false;

      // Synced to a regular player - this is a manual sync child
      return true;
    }

    // Case 2: Player is a leader with group members
    if (player.groupMembers != null && player.groupMembers!.length > 1) {
      // Key distinction: In a MANUAL sync, the leader's own ID is in groupMembers
      // In a PRE-CONFIGURED group (UGP), the group player's ID is NOT in groupMembers
      // (the members are the child players, not including the group itself)
      final isInOwnGroup = player.groupMembers!.contains(player.playerId);
      if (!isInOwnGroup) {
        // This is a pre-configured group player (like "All Speakers")
        return false;
      }
      // Leader's ID is in groupMembers = manual sync
      return true;
    }

    return false;
  }

  Track? get currentTrack => _currentTrack;

  // Sleep timer getters
  bool get sleepTimerActive => _sleepTimerMinutes != null;
  int? get sleepTimerMinutes => _sleepTimerMinutes;
  Duration? get sleepTimerRemaining {
    if (_sleepTimerEndTime == null) return null;
    final remaining = _sleepTimerEndTime!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Whether we have cached players available (for instant UI display on app resume)
  bool get hasCachedPlayers => _cacheService.hasCachedPlayers;

  /// Currently playing audiobook context (with chapters) - set when playing an audiobook
  Audiobook? get currentAudiobook => _currentAudiobook;

  /// Whether we're currently playing an audiobook
  bool get isPlayingAudiobook => _currentAudiobook != null;

  /// Whether we're currently playing a podcast episode
  /// Detected by checking if the current track's URI contains podcast_episode
  bool get isPlayingPodcast {
    final uri = _currentTrack?.uri;
    if (uri == null) return false;
    return uri.contains('podcast_episode') || uri.contains('podcast/');
  }

  /// Whether we're currently playing a radio station
  /// Detected by checking if the current track's URI contains 'radio/' or media_type is 'radio'
  bool get isPlayingRadio {
    final uri = _currentTrack?.uri;
    if (uri == null) return false;
    return uri.contains('library://radio/') || uri.contains('/radio/');
  }

  /// Get the radio station name when playing a radio stream
  /// Returns the station name from album (where MA puts it for radio streams)
  String? get currentRadioStationName {
    if (!isPlayingRadio || _currentTrack == null) return null;

    // For radio, the station name is typically in the album field
    if (_currentTrack!.album != null && _currentTrack!.album!.name.isNotEmpty) {
      return _currentTrack!.album!.name;
    }
    return null;
  }

  /// Get the podcast name when playing a podcast episode
  /// Returns the podcast name from stored context, metadata, or fallbacks
  String? get currentPodcastName {
    if (!isPlayingPodcast || _currentTrack == null) return null;

    // Primary source: stored podcast name from when episode was played
    if (_currentPodcastName != null && _currentPodcastName!.isNotEmpty) {
      return _currentPodcastName;
    }

    // Try metadata (if episode has parent podcast info from API)
    final metadata = _currentTrack!.metadata;
    if (metadata != null) {
      if (metadata['podcast_name'] != null) {
        return metadata['podcast_name'] as String;
      }
      if (metadata['podcast'] is Map) {
        final podcast = metadata['podcast'] as Map;
        if (podcast['name'] != null) {
          return podcast['name'] as String;
        }
      }
    }

    // Fallbacks removed - album/artist contain episode name, not podcast name
    // Return null to let UI show generic "Podcasts" label
    return null;
  }

  /// Set the current podcast context (call when playing a podcast episode)
  void setCurrentPodcastName(String? podcastName) {
    _currentPodcastName = podcastName;
    _logger.log('🎙️ Set current podcast name: $podcastName');
  }

  /// Clear the podcast context
  void clearCurrentPodcastName() {
    if (_currentPodcastName != null) {
      _logger.log('🎙️ Cleared podcast context');
      _currentPodcastName = null;
    }
  }

  String get lastSearchQuery => _lastSearchQuery;
  Map<String, List<MediaItem>> get lastSearchResults => _lastSearchResults;

  MusicAssistantAPI? get api => _api;
  AuthManager get authManager => _authManager;

  /// Position tracker for playback progress - single source of truth
  PositionTracker get positionTracker => _positionTracker;

  /// Whether Sendspin (PCM streaming) is connected for builtin player
  bool get isSendspinConnected => _sendspinConnected;

  /// Whether PCM audio is currently playing via Sendspin
  bool get isPcmPlaying => _sendspinConnected && _pcmAudioPlayer != null && _pcmAudioPlayer!.isPlaying;

  /// Get current PCM audio format info (when using Sendspin)
  /// Returns null if not using Sendspin PCM streaming
  String? get currentAudioFormat {
    if (!_sendspinConnected || _pcmAudioPlayer == null) return null;
    return '48kHz • Stereo • 16-bit PCM';
  }

  /// Get the current playback source description
  String get playbackSource {
    if (_sendspinConnected && _pcmAudioPlayer != null) {
      return 'Sendspin (Local PCM)';
    }
    return 'Music Assistant';
  }

  /// Get cached track for a player (used for smooth swipe transitions)
  /// For grouped child players, returns the leader's track
  /// Also checks translated Cast<->Sendspin IDs (both from map and computed dynamically)
  Track? getCachedTrackForPlayer(String playerId) {
    // If player is a group child, get the leader's track instead
    final player = _availablePlayers.firstWhere(
      (p) => p.playerId == playerId,
      orElse: () => Player(
        playerId: playerId,
        name: '',
        available: false,
        powered: false,
        state: 'idle',
      ),
    );

    final effectivePlayerId = (player.isGroupChild && player.syncedTo != null)
        ? player.syncedTo!
        : playerId;

    // Try direct lookup first
    var track = _cacheService.getCachedTrackForPlayer(effectivePlayerId);

    // If not found, try translated Cast<->Sendspin ID
    if (track == null) {
      // Check Cast -> Sendspin (from map)
      final sendspinId = _castToSendspinIdMap[effectivePlayerId];
      if (sendspinId != null) {
        track = _cacheService.getCachedTrackForPlayer(sendspinId);
      }

      // Check Sendspin -> Cast (reverse lookup from map)
      if (track == null) {
        for (final entry in _castToSendspinIdMap.entries) {
          if (entry.value == effectivePlayerId) {
            track = _cacheService.getCachedTrackForPlayer(entry.key);
            if (track != null) break;
          }
        }
      }

      // Dynamic ID computation for chromecast players
      // This handles cases where the map doesn't have the entry yet
      if (track == null) {
        // If effectivePlayerId looks like a Sendspin ID (cast-{8chars}), compute Cast ID
        if (effectivePlayerId.startsWith('cast-') && effectivePlayerId.length >= 13) {
          // Sendspin ID: cast-7df484e3 -> need to find Cast ID that starts with 7df484e3
          final prefix = effectivePlayerId.substring(5); // Remove "cast-"
          // Search through available players for a chromecast player with matching UUID prefix
          for (final p in _availablePlayers) {
            if (p.provider == 'chromecast' && p.playerId.startsWith(prefix)) {
              track = _cacheService.getCachedTrackForPlayer(p.playerId);
              if (track != null) {
                _logger.log('🔍 Found track via computed Cast ID: ${p.playerId}');
                break;
              }
            }
          }
          // Also try direct cache lookup with the prefix as partial ID
          if (track == null) {
            // Try common UUID patterns - the cache might have the full Cast UUID
            final possibleCastIds = _cacheService.getAllCachedPlayerIds()
                .where((id) => id.startsWith(prefix))
                .toList();
            for (final castId in possibleCastIds) {
              track = _cacheService.getCachedTrackForPlayer(castId);
              if (track != null) {
                _logger.log('🔍 Found track via cache scan for prefix $prefix: $castId');
                break;
              }
            }
          }
        }

        // If effectivePlayerId looks like a Cast UUID, compute Sendspin ID
        if (track == null && effectivePlayerId.length >= 8 && effectivePlayerId.contains('-')) {
          final computedSendspinId = 'cast-${effectivePlayerId.substring(0, 8)}';
          track = _cacheService.getCachedTrackForPlayer(computedSendspinId);
          if (track != null) {
            _logger.log('🔍 Found track via computed Sendspin ID: $computedSendspinId');
          }
        }
      }
    }

    return track;
  }

  /// Get artwork URL for a player from cache
  String? getCachedArtworkUrl(String playerId, {int size = 512}) {
    final track = getCachedTrackForPlayer(playerId);
    if (track == null) return null;
    return getImageUrl(track, size: size);
  }

  /// Clear cached track for a player (e.g., after queue transfer)
  void clearPlayerTrackCache(String playerId) {
    _cacheService.clearCachedTrackForPlayer(playerId);
    notifyListeners();
  }

  /// Number of pending offline actions
  int get pendingOfflineActionsCount => OfflineActionQueue.instance.pendingCount;

  /// Whether there are pending offline actions
  bool get hasPendingOfflineActions => OfflineActionQueue.instance.hasPendingActions;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  MusicAssistantProvider() {
    _localPlayer = LocalPlayerService(_authManager);
    _initialize();
  }

  Future<void> _initialize() async {
    _serverUrl = await SettingsService.getServerUrl();

    // Load cached players from database for instant display (before connecting)
    await _loadPlayersFromDatabase();

    // Load cached library from SyncService for instant favorites display
    await _loadLibraryFromCache();

    // Load cached favorite tracks from database (tracks aren't in SyncService)
    await _loadFavoriteTracksFromDatabase();

    // Load cached home rows from database for instant discover/recent display
    await _cacheService.loadHomeRowsFromDatabase();

    // Load podcast cover cache (iTunes URLs) for instant high-res display
    await _loadPodcastCoverCache();

    // Initialize offline action queue
    await OfflineActionQueue.instance.initialize();

    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      await _restoreAuthCredentials();
      await connectToServer(_serverUrl!);
      await _initializeLocalPlayback();
    }
  }

  /// Load cached players from database for instant UI display
  Future<void> _loadPlayersFromDatabase() async {
    try {
      if (!DatabaseService.instance.isInitialized) {
        await DatabaseService.instance.initialize();
      }

      final cachedPlayers = await DatabaseService.instance.getCachedPlayers();
      if (cachedPlayers.isEmpty) {
        _logger.log('📦 No cached players in database');
        return;
      }

      final players = <Player>[];
      for (final cached in cachedPlayers) {
        try {
          final playerData = jsonDecode(cached.playerJson) as Map<String, dynamic>;
          players.add(Player.fromJson(playerData));
        } catch (e) {
          _logger.log('⚠️ Error parsing cached player: $e');
        }
      }

      if (players.isNotEmpty) {
        _availablePlayers = players;
        _cacheService.setCachedPlayers(players);

        // Restore selected player from settings
        final lastSelectedPlayerId = await SettingsService.getLastSelectedPlayerId();
        if (lastSelectedPlayerId != null) {
          try {
            _selectedPlayer = players.firstWhere((p) => p.playerId == lastSelectedPlayerId);
            _cacheService.setCachedSelectedPlayer(_selectedPlayer);
            _logger.log('📦 Restored selected player from database: ${_selectedPlayer?.name}');
          } catch (_) {
            // Player not in cached list
          }
        }

        _logger.log('📦 Loaded ${players.length} players from database (instant)');
        notifyListeners();

        // Also load saved playback state for instant track display
        if (_selectedPlayer != null) {
          await _loadPlaybackStateFromDatabase();
        }
      }
    } catch (e) {
      _logger.log('⚠️ Error loading players from database: $e');
    }
  }

  /// Load saved playback state (currentTrack) from database for instant display
  Future<void> _loadPlaybackStateFromDatabase() async {
    try {
      final playbackState = await DatabaseService.instance.getPlaybackState();
      if (playbackState == null) {
        _logger.log('📦 No saved playback state in database');
        return;
      }

      // Only restore if it matches the current player
      if (playbackState.playerId != _selectedPlayer?.playerId) {
        _logger.log('📦 Saved playback state is for different player, skipping');
        return;
      }

      if (playbackState.currentTrackJson != null) {
        try {
          final trackData = jsonDecode(playbackState.currentTrackJson!) as Map<String, dynamic>;
          _currentTrack = Track.fromJson(trackData);
          _logger.log('📦 Restored currentTrack from database: ${_currentTrack?.name}');
          notifyListeners();
        } catch (e) {
          _logger.log('⚠️ Error parsing cached track: $e');
        }
      }
    } catch (e) {
      _logger.log('⚠️ Error loading playback state: $e');
    }
  }

  /// Load library data from SyncService cache for instant favorites display
  Future<void> _loadLibraryFromCache() async {
    try {
      final syncService = SyncService.instance;

      // Ensure SyncService has loaded from database
      if (!syncService.hasCache) {
        await syncService.loadFromCache();
      }

      if (syncService.hasCache) {
        _albums = syncService.cachedAlbums;
        _artists = syncService.cachedArtists;
        // Note: tracks are loaded separately via API, not cached in SyncService
        _logger.log('📦 Pre-loaded library for favorites: ${_albums.length} albums, ${_artists.length} artists');
        _syncLibraryStatusToService();
        notifyListeners();
      }
    } catch (e) {
      _logger.log('⚠️ Error loading library from cache: $e');
    }
  }

  /// Load podcast cover cache (iTunes URLs) from storage for instant high-res display
  Future<void> _loadPodcastCoverCache() async {
    try {
      final cache = await SettingsService.getPodcastCoverCache();
      if (cache.isNotEmpty) {
        _podcastCoverCache.addAll(cache);
        _logger.log('📦 Loaded ${cache.length} podcast covers from cache (instant high-res)');
      }
    } catch (e) {
      _logger.log('⚠️ Error loading podcast cover cache: $e');
    }
  }

  /// Persist current playback state to database (fire-and-forget)
  void _persistPlaybackState() {
    if (_selectedPlayer == null) return;

    () async {
      try {
        if (!DatabaseService.instance.isInitialized) return;

        await DatabaseService.instance.savePlaybackState(
          playerId: _selectedPlayer!.playerId,
          playerName: _selectedPlayer!.name,
          currentTrackJson: _currentTrack != null ? jsonEncode(_currentTrack!.toJson()) : null,
          isPlaying: _selectedPlayer!.state == 'playing',
        );
        _logger.log('💾 Persisted playback state to database');
      } catch (e) {
        _logger.log('⚠️ Error persisting playback state: $e');
      }
    }();
  }

  /// Persist favorite tracks to database (fire-and-forget)
  void _persistFavoriteTracks(List<Track> tracks) {
    () async {
      try {
        if (!DatabaseService.instance.isInitialized) return;
        final tracksJson = jsonEncode(tracks.map((t) => t.toJson()).toList());
        await DatabaseService.instance.saveHomeRowCache('favorite_tracks', tracksJson);
        _logger.log('💾 Persisted ${tracks.length} favorite tracks to database');
      } catch (e) {
        _logger.log('⚠️ Error persisting favorite tracks: $e');
      }
    }();
  }

  /// Load cached favorite tracks from database
  Future<void> _loadFavoriteTracksFromDatabase() async {
    try {
      if (!DatabaseService.instance.isInitialized) return;

      final data = await DatabaseService.instance.getHomeRowCache('favorite_tracks');
      if (data == null) return;

      final items = (jsonDecode(data.itemsJson) as List)
          .map((json) => Track.fromJson(json as Map<String, dynamic>))
          .toList();
      _cachedFavoriteTracks = items;
      _logger.log('📦 Loaded ${items.length} cached favorite tracks from database');
    } catch (e) {
      _logger.log('⚠️ Error loading favorite tracks: $e');
    }
  }

  /// Persist players to database for app restart persistence
  void _persistPlayersToDatabase(List<Player> players) {
    // Run async but don't await - this is fire-and-forget persistence
    () async {
      try {
        if (!DatabaseService.instance.isInitialized) return;

        final playerMaps = players.map((p) => {
          'playerId': p.playerId,
          'playerJson': jsonEncode(p.toJson()),
          'currentTrackJson': null as String?, // Will be updated separately when track changes
        }).toList();

        await DatabaseService.instance.cachePlayers(playerMaps);
        _logger.log('💾 Persisted ${players.length} players to database');
      } catch (e) {
        _logger.log('⚠️ Error persisting players to database: $e');
      }
    }();
  }

  Future<void> _restoreAuthCredentials() async {
    final storedToken = await SettingsService.getMaAuthToken();
    if (storedToken != null) {
      _logger.log('🔐 Restoring saved MA token...');
      _authManager.setToken(storedToken);
      _logger.log('🔐 Auth token restored');
    }
  }

  // ============================================================================
  // CONNECTION
  // ============================================================================

  Future<void> connectToServer(String serverUrl) async {
    try {
      _error = null;
      _serverUrl = serverUrl;
      await SettingsService.setServerUrl(serverUrl);

      // Dispose the old API to stop any pending reconnects
      _api?.dispose();

      _api = MusicAssistantAPI(serverUrl, _authManager);

      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = _api!.connectionState.listen(
        (state) async {
          if (state == MAConnectionState.connected) {
            _logger.log('🔗 WebSocket connected to MA server');

            if (_api!.authRequired && !_api!.isAuthenticated) {
              // Don't broadcast 'connected' yet — AppStartup watches isConnected
              // and would transition to HomeScreen before auth completes, causing
              // data fetches to fail with "Not authenticated".
              _logger.log('🔐 MA auth required, attempting authentication...');
              final authenticated = await _handleMaAuthentication();
              if (!authenticated) {
                _connectionState = MAConnectionState.error;
                _error = 'Authentication required. Please log in again.';
                notifyListeners();
                return;
              }
              // After authentication succeeds, authenticated state will trigger initialization
              // Don't call _initializeAfterConnection() here - wait for authenticated state
              return;
            }

            // No auth required — safe to broadcast connected and initialize
            _connectionState = state;
            notifyListeners();
            await _initializeAfterConnection();
          } else if (state == MAConnectionState.authenticated) {
            _connectionState = state;
            notifyListeners();
            _logger.log('✅ MA authentication successful');
            // Now safe to initialize since we're authenticated
            await _initializeAfterConnection();
          } else if (state == MAConnectionState.disconnected) {
            _connectionState = state;
            notifyListeners();
            // DON'T clear players or caches on disconnect!
            // Keep showing cached data for instant UI display on reconnect
            // Player list and state will be refreshed when connection is restored
            _logger.log('📡 Disconnected - keeping cached players and data for instant resume');
          } else {
            _connectionState = state;
            notifyListeners();
          }
        },
        onError: (error) {
          _logger.log('Connection state stream error: $error');
          _connectionState = MAConnectionState.error;
          notifyListeners();
        },
      );

      _localPlayerEventSubscription?.cancel();
      _localPlayerEventSubscription = _api!.builtinPlayerEvents.listen(
        _handleLocalPlayerEvent,
        onError: (error) => _logger.log('Builtin player event stream error: $error'),
      );

      _playerUpdatedEventSubscription?.cancel();
      _playerUpdatedEventSubscription = _api!.playerUpdatedEvents.listen(
        _handlePlayerUpdatedEvent,
        onError: (error) => _logger.log('Player updated event stream error: $error'),
      );

      _playerAddedEventSubscription?.cancel();
      _playerAddedEventSubscription = _api!.playerAddedEvents.listen(
        _handlePlayerAddedEvent,
        onError: (error) => _logger.log('Player added event stream error: $error'),
      );

      // Subscribe to library change events for instant UI updates
      _mediaItemAddedEventSubscription?.cancel();
      _mediaItemAddedEventSubscription = _api!.mediaItemAddedEvents.listen(
        _handleMediaItemAddedEvent,
        onError: (error) => _logger.log('Media item added event stream error: $error'),
      );

      _mediaItemDeletedEventSubscription?.cancel();
      _mediaItemDeletedEventSubscription = _api!.mediaItemDeletedEvents.listen(
        _handleMediaItemDeletedEvent,
        onError: (error) => _logger.log('Media item deleted event stream error: $error'),
      );

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

  Future<bool> _handleMaAuthentication() async {
    if (_api == null) return false;

    try {
      final storedToken = await SettingsService.getMaAuthToken();
      if (storedToken != null) {
        _logger.log('🔐 Trying stored MA token...');
        final success = await _api!.authenticateWithToken(storedToken);
        if (success) {
          _logger.log('✅ MA authentication with stored token successful');
          await _fetchUserSettings();
          return true;
        }
        _logger.log('⚠️ Stored MA token invalid, clearing...');
        await SettingsService.clearMaAuthToken();
      }

      final username = await SettingsService.getUsername();
      final password = await SettingsService.getPassword();

      if (username != null && password != null && username.isNotEmpty && password.isNotEmpty) {
        _logger.log('🔐 Trying stored credentials...');
        final accessToken = await _api!.loginWithCredentials(username, password);

        if (accessToken != null) {
          _logger.log('✅ MA login with stored credentials successful');

          final longLivedToken = await _api!.createLongLivedToken();
          if (longLivedToken != null) {
            await SettingsService.setMaAuthToken(longLivedToken);
            _logger.log('✅ Saved new long-lived MA token');
          } else {
            await SettingsService.setMaAuthToken(accessToken);
          }

          await _fetchUserSettings();
          return true;
        }
      }

      _logger.log('❌ MA authentication failed - no valid token or credentials');
      return false;
    } catch (e) {
      _logger.log('❌ MA authentication error: $e');
      return false;
    }
  }

  Future<void> _fetchUserSettings() async {
    if (_api == null) return;

    try {
      final userInfo = await _api!.getCurrentUserInfo();
      if (userInfo == null) return;

      // Set profile name
      final displayName = userInfo['display_name'] as String?;
      final username = userInfo['username'] as String?;

      final profileName = (displayName != null && displayName.isNotEmpty) ? displayName : username;

      if (profileName != null && profileName.isNotEmpty) {
        await SettingsService.setOwnerName(profileName);
        _logger.log('✅ Set owner name from MA profile: $profileName');
      }

      // Capture provider filter (empty list = all providers allowed)
      final providerFilterRaw = userInfo['provider_filter'];
      if (providerFilterRaw is List) {
        _providerFilter = providerFilterRaw.cast<String>().toList();
        if (_providerFilter.isNotEmpty) {
          _logger.log('🔒 Provider filter active: ${_providerFilter.length} providers allowed');
          _logger.log('   Allowed: ${_providerFilter.join(", ")}');
        } else {
          _logger.log('🔓 No provider filter - all providers visible');
        }
      } else {
        _providerFilter = [];
        _logger.log('🔓 No provider filter in user settings');
      }

      // Capture player filter (empty list = all players allowed)
      final playerFilterRaw = userInfo['player_filter'];
      if (playerFilterRaw is List) {
        _playerFilter = playerFilterRaw.cast<String>().toList();
        if (_playerFilter.isNotEmpty) {
          _logger.log('🔒 Player filter active: ${_playerFilter.length} players allowed');
          _logger.log('   Allowed: ${_playerFilter.join(", ")}');
        } else {
          _logger.log('🔓 No player filter - all players visible');
        }
      } else {
        _playerFilter = [];
        _logger.log('🔓 No player filter in user settings');
      }
    } catch (e) {
      _logger.log('⚠️ Could not fetch user settings (non-fatal): $e');
    }
  }

  /// Load available music providers from MA and restore saved filter settings
  Future<void> loadMusicProviders() async {
    if (_api == null) return;

    try {
      _logger.log('🎵 Loading music providers...');

      // Fetch available providers from MA
      _availableMusicProviders = await _api!.getMusicProviders();

      // Save discovered providers to settings
      final discoveredList = _availableMusicProviders.map((p) => {
        'instanceId': p.instanceId,
        'domain': p.domain,
        'name': p.name,
      }).toList();
      await SettingsService.setDiscoveredMusicProviders(discoveredList);

      // Load saved enabled providers
      final savedEnabled = await SettingsService.getEnabledMusicProviders();
      if (savedEnabled != null) {
        // Validate saved IDs against available providers
        final availableIds = _availableMusicProviders.map((p) => p.instanceId).toSet();
        _enabledProviderIds = savedEnabled.where((id) => availableIds.contains(id)).toList();

        // If all saved providers are gone, reset to all enabled
        if (_enabledProviderIds.isEmpty && savedEnabled.isNotEmpty) {
          _enabledProviderIds = [];
          await SettingsService.clearEnabledMusicProviders();
          _logger.log('🔄 Reset provider filter - saved providers no longer available');
        } else if (_enabledProviderIds.isNotEmpty) {
          _logger.log('🔒 Loaded provider filter: ${_enabledProviderIds.length} providers enabled');
        }
      } else {
        _enabledProviderIds = [];
        _logger.log('🔓 No provider filter - all ${_availableMusicProviders.length} providers enabled');
      }

      notifyListeners();
    } catch (e) {
      _logger.log('⚠️ Could not load music providers (non-fatal): $e');
    }
  }

  /// Toggle a specific music provider on/off
  /// Uses debounce to allow multiple toggles before syncing
  Future<bool> toggleProviderEnabled(String instanceId, bool enabled) async {
    final allIds = _availableMusicProviders.map((p) => p.instanceId).toList();

    // Don't allow disabling the last provider
    if (!enabled && _enabledProviderIds.isNotEmpty && _enabledProviderIds.length <= 1) {
      _logger.log('⚠️ Cannot disable last provider');
      return false;
    }

    // Update local state directly for immediate UI response
    // If currently "all enabled" (empty list) and disabling one, need to switch to explicit mode
    if (_enabledProviderIds.isEmpty && !enabled) {
      // Initialize with all providers except the one being disabled
      _enabledProviderIds = allIds.where((id) => id != instanceId).toList();
    } else if (enabled) {
      // Add to list if not present
      if (!_enabledProviderIds.contains(instanceId)) {
        _enabledProviderIds = [..._enabledProviderIds, instanceId];
      }
    } else {
      // Remove from list
      _enabledProviderIds = _enabledProviderIds.where((id) => id != instanceId).toList();
    }

    // Persist to settings (async, but don't wait for UI update)
    SettingsService.toggleMusicProvider(instanceId, enabled, allIds);

    _logger.log('🔄 Provider filter updated: ${_enabledProviderIds.isEmpty ? "all enabled" : "${_enabledProviderIds.length} enabled"}');

    // Clear discover caches so they get refetched with new filter
    _cacheService.clearDiscoverCaches();

    // Notify listeners IMMEDIATELY so UI rebuilds with client-side filtering
    // This enables instant UI updates using cached data with source tracking
    notifyListeners();

    // NOTE: Debounced sync is handled by the UI layer (new_library_screen.dart)
    // to avoid duplicate timers and ensure single point of control

    // Return true to indicate UI should update
    return true;
  }

  Future<void> _initializeAfterConnection() async {
    if (_api == null) return;

    try {
      _logger.log('🚀 Initializing after connection...');

      await _api!.fetchState();

      if (_api!.authRequired) {
        await _fetchUserSettings();
      }

      // Load available music providers and user's filter preferences
      await loadMusicProviders();

      await _tryAdoptGhostPlayer();
      await _registerLocalPlayer();
      await _loadAndSelectPlayers(coldStart: true);

      loadLibrary();

      // Process any queued offline actions now that we're connected
      await _processOfflineQueue();

      _logger.log('✅ Post-connection initialization complete');
    } catch (e) {
      _logger.log('❌ Error during post-connection initialization: $e');
      _error = 'Failed to initialize after connection';
      notifyListeners();
    }
  }

  /// Process queued offline actions (favorites, playlist modifications, etc.)
  Future<void> _processOfflineQueue() async {
    if (_api == null || !isConnected) return;

    final queue = OfflineActionQueue.instance;
    if (!queue.hasPendingActions) return;

    _logger.log('📋 Processing ${queue.pendingCount} offline actions...');

    await queue.processQueue((action) async {
      try {
        switch (action.type) {
          case OfflineActionTypes.toggleFavorite:
            return await _executeToggleFavorite(action.params);
          case OfflineActionTypes.addToPlaylist:
            return await _executeAddToPlaylist(action.params);
          case OfflineActionTypes.removeFromPlaylist:
            return await _executeRemoveFromPlaylist(action.params);
          default:
            _logger.log('⚠️ Unknown offline action type: ${action.type}');
            return false;
        }
      } catch (e) {
        _logger.log('❌ Error executing offline action ${action.type}: $e');
        return false;
      }
    });
  }

  /// Execute a queued toggle favorite action
  Future<bool> _executeToggleFavorite(Map<String, dynamic> params) async {
    if (_api == null) return false;

    final mediaType = params['mediaType'] as String;
    final add = params['add'] as bool;

    if (add) {
      final itemId = params['itemId'] as String;
      final provider = params['provider'] as String;
      await _api!.addToFavorites(mediaType, itemId, provider);
    } else {
      final libraryItemId = params['libraryItemId'] as int;
      await _api!.removeFromFavorites(mediaType, libraryItemId);
    }
    return true;
  }

  /// Execute a queued add to playlist action
  Future<bool> _executeAddToPlaylist(Map<String, dynamic> params) async {
    // TODO: Implement when playlist modification is added
    return false;
  }

  /// Execute a queued remove from playlist action
  Future<bool> _executeRemoveFromPlaylist(Map<String, dynamic> params) async {
    // TODO: Implement when playlist modification is added
    return false;
  }

  // ============================================================================
  // FAVORITE MANAGEMENT (WITH OFFLINE SUPPORT)
  // ============================================================================

  /// Add item to favorites with offline queuing support
  /// Returns true if action was executed or queued successfully
  Future<bool> addToFavorites({
    required String mediaType,
    required String itemId,
    required String provider,
  }) async {
    if (isConnected && _api != null) {
      // Online - execute immediately
      try {
        await _api!.addToFavorites(mediaType, itemId, provider);
        // Update local cache for instant UI feedback
        _updateLocalFavoriteStatus(mediaType, itemId, true);
        return true;
      } catch (e) {
        _logger.log('❌ Failed to add to favorites: $e');
        return false;
      }
    } else {
      // Offline - queue the action
      await OfflineActionQueue.instance.queueAction(
        OfflineActionTypes.toggleFavorite,
        {
          'mediaType': mediaType,
          'add': true,
          'itemId': itemId,
          'provider': provider,
        },
      );
      _logger.log('📋 Queued add to favorites (offline): $mediaType');
      // Still update local state for offline support
      _updateLocalFavoriteStatus(mediaType, itemId, true);
      return true;
    }
  }

  /// Remove item from favorites with offline queuing support
  /// Returns true if action was executed or queued successfully
  Future<bool> removeFromFavorites({
    required String mediaType,
    required int libraryItemId,
  }) async {
    if (isConnected && _api != null) {
      // Online - execute immediately
      try {
        await _api!.removeFromFavorites(mediaType, libraryItemId);
        // Update local cache for instant UI feedback
        _updateLocalFavoriteStatusByLibraryId(mediaType, libraryItemId, false);
        return true;
      } catch (e) {
        _logger.log('❌ Failed to remove from favorites: $e');
        return false;
      }
    } else {
      // Offline - queue the action
      await OfflineActionQueue.instance.queueAction(
        OfflineActionTypes.toggleFavorite,
        {
          'mediaType': mediaType,
          'add': false,
          'libraryItemId': libraryItemId,
        },
      );
      _logger.log('📋 Queued remove from favorites (offline): $mediaType');
      // Still update local state for offline support
      _updateLocalFavoriteStatusByLibraryId(mediaType, libraryItemId, false);
      return true;
    }
  }

  /// Update favorite status in local cache for instant UI feedback
  void _updateLocalFavoriteStatus(String mediaType, String itemId, bool isFavorite) {
    bool updated = false;

    if (mediaType == 'artist') {
      final index = _artists.indexWhere((a) => a.itemId == itemId);
      if (index != -1) {
        final artist = _artists[index];
        _artists[index] = Artist(
          itemId: artist.itemId,
          provider: artist.provider,
          name: artist.name,
          sortName: artist.sortName,
          uri: artist.uri,
          providerMappings: artist.providerMappings,
          metadata: artist.metadata,
          favorite: isFavorite,
        );
        updated = true;
      }
    } else if (mediaType == 'album') {
      final index = _albums.indexWhere((a) => a.itemId == itemId);
      if (index != -1) {
        final album = _albums[index];
        _albums[index] = Album(
          itemId: album.itemId,
          provider: album.provider,
          name: album.name,
          artists: album.artists,
          albumType: album.albumType,
          year: album.year,
          sortName: album.sortName,
          uri: album.uri,
          providerMappings: album.providerMappings,
          metadata: album.metadata,
          favorite: isFavorite,
        );
        updated = true;
      }
    } else if (mediaType == 'track') {
      final index = _tracks.indexWhere((t) => t.itemId == itemId);
      if (index != -1) {
        final track = _tracks[index];
        _tracks[index] = Track(
          itemId: track.itemId,
          provider: track.provider,
          name: track.name,
          artists: track.artists,
          album: track.album,
          duration: track.duration,
          sortName: track.sortName,
          uri: track.uri,
          providerMappings: track.providerMappings,
          metadata: track.metadata,
          favorite: isFavorite,
        );
        updated = true;
      }
    }

    if (updated) {
      notifyListeners();
    }
  }

  /// Update favorite status by library item ID (for remove operations)
  void _updateLocalFavoriteStatusByLibraryId(String mediaType, int libraryItemId, bool isFavorite) {
    final libraryIdStr = libraryItemId.toString();
    bool updated = false;

    if (mediaType == 'artist') {
      final index = _artists.indexWhere((a) =>
        a.provider == 'library' && a.itemId == libraryIdStr ||
        a.providerMappings?.any((m) => m.providerInstance == 'library' && m.itemId == libraryIdStr) == true
      );
      if (index != -1) {
        final artist = _artists[index];
        _artists[index] = Artist(
          itemId: artist.itemId,
          provider: artist.provider,
          name: artist.name,
          sortName: artist.sortName,
          uri: artist.uri,
          providerMappings: artist.providerMappings,
          metadata: artist.metadata,
          favorite: isFavorite,
        );
        updated = true;
      }
    } else if (mediaType == 'album') {
      final index = _albums.indexWhere((a) =>
        a.provider == 'library' && a.itemId == libraryIdStr ||
        a.providerMappings?.any((m) => m.providerInstance == 'library' && m.itemId == libraryIdStr) == true
      );
      if (index != -1) {
        final album = _albums[index];
        _albums[index] = Album(
          itemId: album.itemId,
          provider: album.provider,
          name: album.name,
          artists: album.artists,
          albumType: album.albumType,
          year: album.year,
          sortName: album.sortName,
          uri: album.uri,
          providerMappings: album.providerMappings,
          metadata: album.metadata,
          favorite: isFavorite,
        );
        updated = true;
      }
    } else if (mediaType == 'track') {
      final index = _tracks.indexWhere((t) =>
        t.provider == 'library' && t.itemId == libraryIdStr ||
        t.providerMappings?.any((m) => m.providerInstance == 'library' && m.itemId == libraryIdStr) == true
      );
      if (index != -1) {
        final track = _tracks[index];
        _tracks[index] = Track(
          itemId: track.itemId,
          provider: track.provider,
          name: track.name,
          artists: track.artists,
          album: track.album,
          duration: track.duration,
          sortName: track.sortName,
          uri: track.uri,
          providerMappings: track.providerMappings,
          metadata: track.metadata,
          favorite: isFavorite,
        );
        updated = true;
      }
    }

    if (updated) {
      notifyListeners();
    }
  }

  // ============================================================================
  // LIBRARY MANAGEMENT
  // ============================================================================

  /// Sync library status to centralized service for reactive UI updates
  void _syncLibraryStatusToService() {
    final service = LibraryStatusService.instance;

    // Sync albums
    service.syncFromLibrary(
      mediaType: 'album',
      items: _albums,
      getInLibrary: (a) => (a as Album).inLibrary,
      getFavorite: (a) => (a as Album).favorite ?? false,
      getProvider: (a) => (a as Album).provider,
      getItemId: (a) => (a as Album).itemId,
    );

    // Sync artists
    service.syncFromLibrary(
      mediaType: 'artist',
      items: _artists,
      getInLibrary: (a) => (a as Artist).inLibrary,
      getFavorite: (a) => (a as Artist).favorite ?? false,
      getProvider: (a) => (a as Artist).provider,
      getItemId: (a) => (a as Artist).itemId,
    );

    // Sync tracks
    service.syncFromLibrary(
      mediaType: 'track',
      items: _tracks,
      getInLibrary: (t) => (t as Track).inLibrary,
      getFavorite: (t) => (t as Track).favorite ?? false,
      getProvider: (t) => (t as Track).provider,
      getItemId: (t) => (t as Track).itemId,
    );
  }

  /// Add item to library
  /// Returns true if action was executed successfully
  Future<bool> addToLibrary({
    required String mediaType,
    required String itemId,
    required String provider,
  }) async {
    if (isConnected && _api != null) {
      try {
        await _api!.addItemToLibrary(mediaType, itemId, provider);
        // Trigger a background refresh to update library with new item
        _scheduleLibraryRefresh(mediaType);
        // Invalidate caches that could show stale inLibrary status
        _cacheService.invalidateSearchCache();
        if (mediaType == 'album') {
          _cacheService.invalidateArtistAlbumsCache();
          _cacheService.invalidateHomeAlbumCaches();
        } else if (mediaType == 'track') {
          _cacheService.invalidateAllAlbumTracksCaches();
          _cacheService.invalidateAllPlaylistTracksCaches();
        } else if (mediaType == 'artist') {
          _cacheService.invalidateHomeArtistCaches();
        }
        return true;
      } catch (e) {
        _logger.log('❌ Failed to add to library: $e');
        return false;
      }
    } else {
      _logger.log('❌ Cannot add to library while offline');
      return false;
    }
  }

  /// Remove item from library
  /// Returns true if action was executed successfully
  /// Uses optimistic update: local cache is updated immediately before API call
  Future<bool> removeFromLibrary({
    required String mediaType,
    required int libraryItemId,
  }) async {
    if (isConnected && _api != null) {
      // OPTIMISTIC UPDATE: Update local cache immediately for instant UI feedback
      // This ensures library screens show the change even before API completes
      _removeFromLocalLibrary(mediaType, libraryItemId);
      // Also remove from SyncService's in-memory cache
      SyncService.instance.removeFromCacheByLibraryId(mediaType, libraryItemId);
      // Also mark as deleted in database cache so it doesn't reappear on next load
      // Use the library ID aware method that handles cases where itemId differs from libraryId
      DatabaseService.instance.markCachedItemDeletedByLibraryId(mediaType, libraryItemId.toString());
      // Invalidate caches that could show stale inLibrary status
      _cacheService.invalidateSearchCache();
      if (mediaType == 'album') {
        _cacheService.invalidateArtistAlbumsCache();
        _cacheService.invalidateHomeAlbumCaches();
      } else if (mediaType == 'track') {
        _cacheService.invalidateAllAlbumTracksCaches();
        _cacheService.invalidateAllPlaylistTracksCaches();
      } else if (mediaType == 'artist') {
        _cacheService.invalidateHomeArtistCaches();
      }

      try {
        await _api!.removeItemFromLibrary(mediaType, libraryItemId);
        return true;
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        // "not found in library" means item is already removed - treat as success
        if (errorStr.contains('not found in library')) {
          _logger.log('ℹ️ Item already removed from library');
          return true;
        }
        // On actual error, we'd ideally restore the item, but that's complex
        // For now, just log the error - the background refresh will fix state
        _logger.log('❌ Failed to remove from library (local cache already updated): $e');
        _scheduleLibraryRefresh(mediaType);
        return false;
      }
    } else {
      _logger.log('❌ Cannot remove from library while offline');
      return false;
    }
  }

  /// Remove item from local library cache for instant UI feedback
  /// Creates new list instances to ensure Selector widgets detect changes
  void _removeFromLocalLibrary(String mediaType, int libraryItemId) {
    final libraryIdStr = libraryItemId.toString();
    bool updated = false;

    // Helper to check if item matches the library ID being removed
    // Checks both direct provider=library match AND providerMappings
    bool matchesLibraryId(String? provider, String? itemId, List<ProviderMapping>? mappings) {
      // Direct match: item's own provider is 'library' and ID matches
      if (provider == 'library' && itemId == libraryIdStr) {
        return true;
      }
      // Mapping match: check if any providerMapping has library instance with matching ID
      if (mappings != null) {
        for (final m in mappings) {
          if ((m.providerInstance == 'library' || m.providerDomain == 'library') &&
              m.itemId == libraryIdStr) {
            return true;
          }
        }
      }
      return false;
    }

    if (mediaType == 'artist') {
      final before = _artists.length;
      // Create new list to trigger Selector rebuilds (reference equality)
      _artists = _artists.where((a) =>
        !matchesLibraryId(a.provider, a.itemId, a.providerMappings)
      ).toList();
      updated = _artists.length != before;
    } else if (mediaType == 'album') {
      final before = _albums.length;
      _albums = _albums.where((a) =>
        !matchesLibraryId(a.provider, a.itemId, a.providerMappings)
      ).toList();
      updated = _albums.length != before;
    } else if (mediaType == 'track') {
      final before = _tracks.length;
      _tracks = _tracks.where((t) =>
        !matchesLibraryId(t.provider, t.itemId, t.providerMappings)
      ).toList();
      updated = _tracks.length != before;
    } else if (mediaType == 'radio') {
      final before = _radioStations.length;
      _radioStations = _radioStations.where((r) =>
        !matchesLibraryId(r.provider, r.itemId, r.providerMappings)
      ).toList();
      updated = _radioStations.length != before;
    } else if (mediaType == 'podcast') {
      final before = _podcasts.length;
      _podcasts = _podcasts.where((p) =>
        !matchesLibraryId(p.provider, p.itemId, p.providerMappings)
      ).toList();
      updated = _podcasts.length != before;
    }

    if (updated) {
      _logger.log('🗑️ Removed $mediaType with libraryId=$libraryItemId from local cache');
      notifyListeners();
    }
  }

  /// Refresh library data for a media type after library change
  /// Runs immediately (no delay) to ensure UI stays in sync
  void _scheduleLibraryRefresh(String mediaType) {
    // Run immediately - no delay to ensure data consistency
    () async {
      if (!isConnected || _api == null) return;

      try {
        if (mediaType == 'artist') {
          _artists = await _api!.getArtists(
            limit: LibraryConstants.maxLibraryItems,
            albumArtistsOnly: false,
          );
        } else if (mediaType == 'album') {
          _albums = await _api!.getAlbums(limit: LibraryConstants.maxLibraryItems);
        } else if (mediaType == 'track') {
          _tracks = await _api!.getTracks(limit: LibraryConstants.maxLibraryItems);
        } else if (mediaType == 'radio') {
          _radioStations = await _api!.getRadioStations(limit: 100);
        } else if (mediaType == 'podcast') {
          _podcasts = await _api!.getPodcasts(limit: 100);
        }
        _syncLibraryStatusToService();
        notifyListeners();
      } catch (e) {
        _logger.log('⚠️ Background library refresh failed: $e');
      }
    }();
  }

  Future<void> disconnect() async {
    _playerStateTimer?.cancel();
    _playerStateTimer = null;
    _notificationPositionTimer?.cancel();
    _notificationPositionTimer = null;
    _localPlayerStateReportTimer?.cancel();
    _localPlayerEventSubscription?.cancel();
    _playerUpdatedEventSubscription?.cancel();
    _playerAddedEventSubscription?.cancel();
    _mediaItemAddedEventSubscription?.cancel();
    _mediaItemDeletedEventSubscription?.cancel();
    _positionTracker.clear();
    // Disconnect Sendspin and PCM player if connected
    if (_sendspinConnected) {
      await _pcmAudioPlayer?.disconnect();
      await _sendspinService?.disconnect();
      _sendspinConnected = false;
    }
    await _api?.disconnect();
    _connectionState = MAConnectionState.disconnected;
    // DON'T clear caches or player state - keep for instant reconnect
    _logger.log('📡 Explicit disconnect - keeping cached data for instant resume');
    notifyListeners();
  }

  /// Clear all caches and state (for logout or server change)
  void clearAllOnLogout() {
    _availablePlayers = [];
    _selectedPlayer = null;
    _artists = [];
    _albums = [];
    _tracks = [];
    _currentTrack = null;
    _cacheService.clearAll();
    _groupVolumeManager.clear();
    _pendingVolumes.clear();
    _pendingVolumeTimestamps.clear();
    _logger.log('🗑️ Cleared all data on logout');
    notifyListeners();
  }

  Future<void> checkAndReconnect() async {
    _logger.log('🔄 checkAndReconnect called - state: $_connectionState');

    if (_serverUrl == null) {
      _logger.log('🔄 No server URL saved, skipping reconnect');
      return;
    }

    // IMMEDIATELY load cached players for instant UI display
    // This makes mini player and device button appear instantly on app resume
    if (_availablePlayers.isEmpty && _cacheService.hasCachedPlayers) {
      _availablePlayers = _cacheService.getCachedPlayers()!;

      // Sort cached players immediately so list appears in correct order
      final smartSort = await SettingsService.getSmartSortPlayers();
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      _sortPlayersSync(_availablePlayers, smartSort, builtinPlayerId);

      _selectedPlayer = _cacheService.getCachedSelectedPlayer();
      // Also try to restore from settings if cache doesn't have selected player
      if (_selectedPlayer == null && _availablePlayers.isNotEmpty) {
        final lastSelectedPlayerId = await SettingsService.getLastSelectedPlayerId();
        if (lastSelectedPlayerId != null) {
          try {
            _selectedPlayer = _availablePlayers.firstWhere(
              (p) => p.playerId == lastSelectedPlayerId,
            );
          } catch (e) {
            _selectedPlayer = _availablePlayers.first;
          }
        } else {
          _selectedPlayer = _availablePlayers.first;
        }
      }
      _logger.log('⚡ Loaded ${_availablePlayers.length} cached players instantly (sorted)');
      notifyListeners(); // Update UI immediately with cached data
    }

    if (_connectionState != MAConnectionState.connected &&
        _connectionState != MAConnectionState.authenticated) {
      _logger.log('🔄 Not connected, attempting reconnect to $_serverUrl');
      try {
        await connectToServer(_serverUrl!);
        _logger.log('🔄 Reconnection successful');
      } catch (e) {
        _logger.log('🔄 Reconnection failed: $e');
      }
    } else {
      _logger.log('🔄 Already connected, verifying connection...');
      try {
        await refreshPlayers();
        await _updatePlayerState();
        // Note: _preloadAdjacentPlayers is already called in refreshPlayers() -> _loadAndSelectPlayers()
        _logger.log('🔄 Connection verified, players and state refreshed');
      } catch (e) {
        _logger.log('🔄 Connection verification failed, reconnecting: $e');
        try {
          await connectToServer(_serverUrl!);
        } catch (reconnectError) {
          _logger.log('🔄 Reconnection failed: $reconnectError');
        }
      }
    }
  }

  // ============================================================================
  // LOCAL PLAYER
  // ============================================================================

  Future<void> _initializeLocalPlayback() async {
    await _localPlayer.initialize();
    _isLocalPlayerPowered = true;

    // Wire up notification button callbacks
    audioHandler.onSkipToNext = () {
      _logger.log('🎵 Notification: Skip to next pressed');
      nextTrackSelectedPlayer();
    };
    audioHandler.onSkipToPrevious = () {
      _logger.log('🎵 Notification: Skip to previous pressed');
      previousTrackSelectedPlayer();
    };
    audioHandler.onPlay = () {
      _logger.log('🎵 Notification: Play pressed');
      playPauseSelectedPlayer();
    };
    audioHandler.onPause = () {
      _logger.log('🎵 Notification: Pause pressed');
      playPauseSelectedPlayer();
    };
    audioHandler.onSwitchPlayer = () {
      _logger.log('🎵 Notification: Switch player pressed');
      selectNextPlayer();
    };

    // Player registration is now handled in _initializeAfterConnection()
    // which runs after authentication completes (when auth is required)
  }

  Future<bool> _tryAdoptGhostPlayer() async {
    if (_api == null) return false;

    try {
      final isFresh = await DeviceIdService.isFreshInstallation();
      if (!isFresh) return false;

      final ownerName = await SettingsService.getOwnerName();
      if (ownerName == null || ownerName.isEmpty) return false;

      _logger.log('👻 Fresh install detected, searching for adoptable ghost for "$ownerName"...');
      final adoptableId = await _api!.findAdoptableGhostPlayer(ownerName);
      if (adoptableId == null) return false;

      _logger.log('👻 Found adoptable ghost: $adoptableId');
      await DeviceIdService.adoptPlayerId(adoptableId);
      _logger.log('✅ Successfully adopted ghost player');
      return true;
    } catch (e) {
      _logger.log('⚠️ Ghost adoption failed (non-fatal): $e');
      return false;
    }
  }

  /// Parse server version into components for version comparisons
  /// Returns null if version cannot be parsed
  ({int major, int minor, int patch, int? beta})? _parseServerVersion() {
    final serverInfo = _api?.serverInfo;
    if (serverInfo == null) return null;

    final versionStr = serverInfo['server_version'] as String?;
    if (versionStr == null) return null;

    // Parse version like "2.8.0b2" or "2.7.0b20" or "2.7.1"
    // Format: MAJOR.MINOR.PATCH[bBETA]
    final versionRegex = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:b(\d+))?');
    final match = versionRegex.firstMatch(versionStr);
    if (match == null) return null;

    return (
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      beta: match.group(4) != null ? int.parse(match.group(4)!) : null,
    );
  }

  /// Check if server version is >= 2.7.0b20 (uses Sendspin instead of builtin_player)
  bool _serverUsesSendspin() {
    final version = _parseServerVersion();
    if (version == null) return false;

    final (:major, :minor, :patch, :beta) = version;

    // Compare with 2.7.0b20
    if (major > 2) return true;
    if (major < 2) return false;
    // major == 2
    if (minor > 7) return true;
    if (minor < 7) return false;
    // minor == 7
    if (patch > 0) return true;
    if (patch < 0) return false;
    // patch == 0, so version is 2.7.0 - need beta >= 20
    if (beta == null) return true; // 2.7.0 release is newer than 2.7.0b20
    return beta >= 20;
  }

  /// Check if server has built-in Sendspin proxy (added in MA 2.7.1)
  bool _serverHasSendspinProxy() {
    final version = _parseServerVersion();
    if (version == null) return false;

    final (:major, :minor, :patch, :beta) = version;

    // Compare with 2.7.1
    if (major > 2) return true;
    if (major < 2) return false;
    // major == 2
    if (minor > 7) return true;
    if (minor < 7) return false;
    // minor == 7, need patch >= 1
    return patch >= 1;
  }

  /// Get the server version string for logging
  String _getServerVersionString() {
    final serverInfo = _api?.serverInfo;
    return serverInfo?['server_version'] as String? ?? 'unknown';
  }

  Future<void> _registerLocalPlayer() async {
    if (_api == null) return;

    if (_registrationInProgress != null) {
      _logger.log('⏳ Registration already in progress, waiting...');
      return _registrationInProgress!.future;
    }

    _registrationInProgress = Completer<void>();

    try {
      final playerId = await DeviceIdService.getOrCreateDevicePlayerId();
      _logger.log('🆔 Using player ID: $playerId');

      await SettingsService.setBuiltinPlayerId(playerId);

      final name = await SettingsService.getLocalPlayerName();

      // Check if server uses Sendspin (MA 2.7.0b20+) - skip builtin_player entirely
      if (_serverUsesSendspin()) {
        _logger.log('📡 Server uses Sendspin (MA 2.7.0b20+), skipping builtin_player');
        _builtinPlayerAvailable = false;

        final sendspinSuccess = await _connectViaSendspin();
        if (sendspinSuccess) {
          _logger.log('✅ Connected via Sendspin - local player available');
          _startReportingLocalPlayerState();
        } else {
          _logger.log('⚠️ Sendspin connection failed - local player unavailable');
        }

        if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
          _registrationInProgress!.complete();
        }
        _registrationInProgress = null;
        return;
      }

      final existingPlayers = await _api!.getPlayers();
      final existingPlayer = existingPlayers.where((p) => p.playerId == playerId).firstOrNull;

      if (existingPlayer != null && existingPlayer.available) {
        _logger.log('✅ Player already registered and available: $playerId');
        _startReportingLocalPlayerState();
        if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
          _registrationInProgress!.complete();
        }
        _registrationInProgress = null;
        return;
      } else if (existingPlayer != null && !existingPlayer.available) {
        _logger.log('⚠️ Player exists but unavailable (stale), re-registering: $playerId');
      } else {
        _logger.log('🆔 Player not found in MA, registering as new');
      }

      _logger.log('🎵 Registering player with MA: id=$playerId, name=$name');
      await _api!.registerBuiltinPlayer(playerId, name);

      _logger.log('✅ Player registration complete');
      _startReportingLocalPlayerState();

      if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
        _registrationInProgress!.complete();
      }
      _registrationInProgress = null;
    } catch (e) {
      // Check if this is because builtin_player API is not available (MA 2.7.0b20+)
      final errorStr = e.toString();
      if (errorStr.contains('Invalid command') && errorStr.contains('builtin_player')) {
        _logger.log('⚠️ Builtin player API not available (MA 2.7.0b20+ uses Sendspin)');
        _builtinPlayerAvailable = false;

        // Try to connect via Sendspin instead
        _logger.log('🔄 Attempting Sendspin connection...');
        final sendspinSuccess = await _connectViaSendspin();

        if (sendspinSuccess) {
          _logger.log('✅ Connected via Sendspin - local player available');
          _startReportingLocalPlayerState();
        } else {
          _logger.log('⚠️ Sendspin connection failed - local player unavailable');
          _logger.log('ℹ️ Use other players (Chromecast, etc) or ensure /sendspin route is configured');
        }

        if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
          _registrationInProgress!.complete();
        }
        _registrationInProgress = null;
        return; // Non-fatal, continue
      }

      _logger.log('❌ Player registration failed: $e');
      if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
        _registrationInProgress!.completeError(e);
      }
      _registrationInProgress = null;
      rethrow;
    }
  }

  /// Connect to Music Assistant via Sendspin protocol (MA 2.7.0b20+)
  /// This is the replacement for builtin_player when that API is not available.
  ///
  /// Connection strategy depends on MA version and network:
  /// - MA 2.7.1+: Has built-in /sendspin proxy, works with any reverse proxy setup
  /// - MA 2.7.x: NO proxy, must either:
  ///   - Use local IP with port 8927 exposed, OR
  ///   - Manually configure reverse proxy to route /sendspin to port 8927
  Future<bool> _connectViaSendspin() async {
    if (_api == null || _serverUrl == null) return false;

    try {
      final serverVersion = _getServerVersionString();
      final hasProxy = _serverHasSendspinProxy();
      _logger.log('Sendspin: Server version $serverVersion, has proxy: $hasProxy');

      // Initialize Sendspin service
      _sendspinService?.dispose();
      _sendspinService = SendspinService(_serverUrl!);

      // Set auth token for proxy authentication (MA 2.7.1+ or manually configured proxy)
      final authToken = await SettingsService.getMaAuthToken();
      if (authToken != null) {
        _sendspinService!.setAuthToken(authToken);
        _logger.log('Sendspin: Auth token set for proxy authentication');
      }

      // Initialize PCM audio player for raw audio streaming
      _pcmAudioPlayer?.dispose();
      _pcmAudioPlayer = PcmAudioPlayer();
      final pcmInitialized = await _pcmAudioPlayer!.initialize();
      if (pcmInitialized) {
        _logger.log('✅ PCM audio player initialized for Sendspin');
        // Connect PCM player to Sendspin audio stream
        await _pcmAudioPlayer!.connectToStream(_sendspinService!.audioDataStream);
      } else {
        _logger.log('⚠️ PCM audio player initialization failed');
      }

      // Wire up callbacks
      _sendspinService!.onPlay = _handleSendspinPlay;
      _sendspinService!.onPause = _handleSendspinPause;
      _sendspinService!.onStop = _handleSendspinStop;
      _sendspinService!.onSeek = _handleSendspinSeek;
      _sendspinService!.onVolume = _handleSendspinVolume;
      _sendspinService!.onStreamStart = _handleSendspinStreamStart;
      _sendspinService!.onStreamEnd = _handleSendspinStreamEnd;

      final playerId = await DeviceIdService.getOrCreateDevicePlayerId();
      _logger.log('Sendspin: Player ID: $playerId');

      // Parse server URL to determine connection strategy
      final serverUri = Uri.parse(_serverUrl!.startsWith('http')
          ? _serverUrl!
          : 'https://$_serverUrl');
      final isLocalIp = _isLocalNetworkHost(serverUri.host);
      final isHttps = serverUri.scheme == 'https' ||
                      (!_serverUrl!.contains('://') && !isLocalIp);

      // Strategy 1: For local IPs, connect directly to Sendspin port 8927
      if (isLocalIp) {
        final localSendspinUrl = 'ws://${serverUri.host}:8927/sendspin';
        _logger.log('Sendspin: Local network detected, trying direct connection: $localSendspinUrl');
        final connected = await _sendspinService!.connectWithUrl(localSendspinUrl);
        if (connected) {
          _sendspinConnected = true;
          _logger.log('✅ Sendspin: Connected via local network (port 8927)');
          return true;
        }
        _logger.log('⚠️ Sendspin: Local connection to port 8927 failed');

        // For local IPs, also try the proxy path (MA 2.7.1+ has built-in /sendspin proxy)
        _logger.log('Sendspin: Trying local proxy fallback...');
        final localProxyUrl = 'ws://${serverUri.host}:${serverUri.hasPort ? serverUri.port : 8095}/sendspin';
        final proxyConnected = await _sendspinService!.connectWithUrl(localProxyUrl, useProxyAuth: true);
        if (proxyConnected) {
          _sendspinConnected = true;
          _logger.log('✅ Sendspin: Connected via local proxy');
          return true;
        }
      }

      // Strategy 2: For external/HTTPS servers, use the proxy at /sendspin
      if (isHttps || !isLocalIp) {
        if (hasProxy) {
          _logger.log('Sendspin: MA 2.7.1+ detected, using built-in /sendspin proxy');
        } else {
          _logger.log('Sendspin: MA 2.7.x detected, trying /sendspin (requires manual proxy config)');
        }

        final connected = await _sendspinService!.connect();
        if (connected) {
          _sendspinConnected = true;
          _logger.log('✅ Sendspin: Connected via external proxy');
          return true;
        }
        _logger.log('⚠️ Sendspin: External proxy connection failed');
      }

      // All strategies failed - provide version-specific guidance
      _logger.log('❌ Sendspin: All connection strategies failed');
      _logSendspinTroubleshooting(isLocalIp, hasProxy, serverVersion);

      return false;
    } catch (e) {
      _logger.log('❌ Sendspin connection error: $e');
      return false;
    }
  }

  /// Log troubleshooting guidance based on setup
  void _logSendspinTroubleshooting(bool isLocalIp, bool hasProxy, String serverVersion) {
    if (isLocalIp) {
      _logger.log('ℹ️ LOCAL IP SETUP: Add port 8927 to your Docker compose:');
      _logger.log('   ports:');
      _logger.log('     - "8095:8095"');
      _logger.log('     - "8927:8927"  # Required for Sendspin');
    } else if (!hasProxy) {
      // MA 2.7.x without built-in proxy
      _logger.log('ℹ️ MA $serverVersion does not have built-in /sendspin proxy');
      _logger.log('ℹ️ OPTIONS:');
      _logger.log('   1. Upgrade to Music Assistant 2.8.0+ (recommended)');
      _logger.log('   2. Or add reverse proxy config for /sendspin → port 8927');
      _logger.log('   Traefik: PathPrefix(`/sendspin`) → service port 8927');
      _logger.log('   Nginx: location /sendspin { proxy_pass http://ma:8927; }');
    } else {
      // MA 2.7.1+ but still failing
      _logger.log('ℹ️ MA $serverVersion should have /sendspin proxy');
      _logger.log('ℹ️ Check that your reverse proxy forwards WebSocket connections');
      _logger.log('   Ensure Upgrade and Connection headers are passed through');
    }
  }

  /// Handle Sendspin play command
  void _handleSendspinPlay(String streamUrl, Map<String, dynamic> trackInfo) async {
    _logger.log('🎵 Sendspin: Play command received');

    try {
      // Build full URL if needed
      String fullUrl = streamUrl;
      if (!streamUrl.startsWith('http') && _serverUrl != null) {
        var baseUrl = _serverUrl!;
        if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
          baseUrl = 'https://$baseUrl';
        }
        baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
        final path = streamUrl.startsWith('/') ? streamUrl : '/$streamUrl';
        fullUrl = '$baseUrl$path';
      }

      // Extract metadata from track info
      final trackName = trackInfo['title'] as String? ?? trackInfo['name'] as String? ?? 'Unknown Track';
      final artistName = trackInfo['artist'] as String? ?? 'Unknown Artist';
      final albumName = trackInfo['album'] as String?;
      var artworkUrl = trackInfo['image_url'] as String? ?? trackInfo['artwork_url'] as String?;
      final durationSecs = trackInfo['duration'] as int?;

      if (artworkUrl != null && artworkUrl.startsWith('http://')) {
        artworkUrl = artworkUrl.replaceFirst('http://', 'https://');
      }

      final metadata = TrackMetadata(
        title: trackName,
        artist: artistName,
        album: albumName,
        artworkUrl: artworkUrl,
        duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
      );

      _localPlayer.setCurrentTrackMetadata(metadata);
      _currentNotificationMetadata = metadata;

      await _localPlayer.playUrl(fullUrl);

      // Report state back to MA
      _sendspinService?.reportState(playing: true, paused: false);
    } catch (e) {
      _logger.log('❌ Sendspin: Error handling play command: $e');
    }
  }

  /// Handle Sendspin pause command
  void _handleSendspinPause() async {
    _logger.log('⏸️ Sendspin: Pause command received');
    // Pause both players - PCM for raw streaming, local for URL-based
    await _pcmAudioPlayer?.pause();
    await _localPlayer.pause();
    _sendspinService?.reportState(playing: false, paused: true);
  }

  /// Handle Sendspin stop command
  void _handleSendspinStop() async {
    _logger.log('⏹️ Sendspin: Stop command received');
    // Stop both players - PCM for raw streaming, local for URL-based
    await _pcmAudioPlayer?.stop();
    await _localPlayer.stop();
    _sendspinService?.reportState(playing: false, paused: false);
  }

  /// Handle Sendspin seek command
  void _handleSendspinSeek(int positionSeconds) async {
    _logger.log('⏩ Sendspin: Seek to $positionSeconds seconds');
    await _localPlayer.seek(Duration(seconds: positionSeconds));
    _sendspinService?.reportState(position: positionSeconds);
  }

  /// Handle Sendspin volume command
  void _handleSendspinVolume(int volumeLevel) async {
    _logger.log('🔊 Sendspin: Set volume to $volumeLevel');
    _localPlayerVolume = volumeLevel;
    await FlutterVolumeController.setVolume(volumeLevel / 100.0);
    _sendspinService?.reportState(volume: volumeLevel);
  }

  /// Handle Sendspin stream start - server is about to send PCM audio data
  /// This is called when audio streaming begins, before any audio frames arrive.
  /// We use this to:
  /// 1. Ensure PCM player is ready
  /// 2. Start the foreground service to prevent background throttling
  /// 3. Reset position for new track and start position timer
  void _handleSendspinStreamStart(Map<String, dynamic>? trackInfo) async {
    _logger.log('🎵 Sendspin: Stream starting');

    // Ensure PCM player is initialized and ready
    if (_pcmAudioPlayer == null || _pcmAudioPlayer!.state == PcmPlayerState.idle) {
      _logger.log('🎵 Sendspin: Reinitializing PCM player for stream');
      _pcmAudioPlayer?.dispose();
      _pcmAudioPlayer = PcmAudioPlayer();
      final initialized = await _pcmAudioPlayer!.initialize();
      if (initialized) {
        await _pcmAudioPlayer!.connectToStream(_sendspinService!.audioDataStream);
      } else {
        _logger.log('⚠️ Sendspin: Failed to initialize PCM player');
        return;
      }
    }

    // CRITICAL: Reset paused state when stream starts
    // This clears _isPausePending and sets state to playing
    // so that _onAudioData will process incoming audio
    await _pcmAudioPlayer!.play();

    // Reset position for new stream (new track)
    _pcmAudioPlayer!.resetPosition();

    // Extract track info for notification
    String? title = trackInfo?['title'] as String? ?? trackInfo?['name'] as String?;
    String? artist = trackInfo?['artist'] as String?;
    String? album = trackInfo?['album'] as String?;
    String? artworkUrl = trackInfo?['image_url'] as String? ?? trackInfo?['artwork_url'] as String?;
    int? durationSecs = trackInfo?['duration'] as int?;

    // If no track info in stream/start, try to get from cached notification metadata
    if (title == null && _currentNotificationMetadata != null) {
      title = _currentNotificationMetadata!.title;
      artist = _currentNotificationMetadata!.artist;
      album = _currentNotificationMetadata!.album;
      artworkUrl = _currentNotificationMetadata!.artworkUrl;
      durationSecs = _currentNotificationMetadata!.duration?.inSeconds;
    }

    // Keep the foreground service active to prevent Android from throttling
    // the PCM audio playback when the app goes to background.
    // We use setRemotePlaybackState to maintain the notification without
    // actually playing audio through just_audio.
    final mediaItem = audio_service.MediaItem(
      id: 'sendspin_pcm_stream',
      title: title ?? 'Playing via Sendspin',
      artist: artist ?? 'Music Assistant',
      album: album,
      artUri: artworkUrl != null ? Uri.parse(artworkUrl) : null,
      duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
    );

    // Initialize notification with position 0
    _cancelIdleServiceTimer();
    audioHandler.setRemotePlaybackState(
      item: mediaItem,
      playing: true,
      position: Duration.zero,
      duration: mediaItem.duration,
    );

    // Start notification position timer for Sendspin PCM
    _manageNotificationPositionTimer();

    _logger.log('🎵 Sendspin: Foreground service activated for PCM streaming');
  }

  /// Handle Sendspin stream end - server stopped sending PCM audio data
  /// This is called when audio streaming ends (pause, stop, track end, etc.)
  void _handleSendspinStreamEnd() async {
    // Capture current position before stopping
    final lastPosition = _pcmAudioPlayer?.elapsedTime ?? Duration.zero;
    _logger.log('🎵 Sendspin: Stream ended at position ${lastPosition.inSeconds}s');

    // Stop notification position timer
    _notificationPositionTimer?.cancel();

    // Pause PCM playback (preserves position) instead of stop (resets position)
    await _pcmAudioPlayer?.pause();

    // Update foreground service to show paused/stopped state with last position
    // Don't completely clear it - keep showing the notification
    // in case user wants to resume
    final metadata = _currentNotificationMetadata;
    final mediaItem = audio_service.MediaItem(
      id: 'sendspin_pcm_stream',
      title: metadata?.title ?? 'Music Assistant',
      artist: metadata?.artist ?? 'Paused',
      album: metadata?.album,
      artUri: metadata?.artworkUrl != null ? Uri.parse(metadata!.artworkUrl!) : null,
      duration: metadata?.duration,
    );

    // Show paused state with preserved position
    _cancelIdleServiceTimer();
    audioHandler.setRemotePlaybackState(
      item: mediaItem,
      playing: false,
      position: lastPosition,
      duration: mediaItem.duration,
    );
  }

  void _startReportingLocalPlayerState() {
    _localPlayerStateReportTimer?.cancel();
    _localPlayerStateReportTimer = Timer.periodic(Timings.localPlayerReportInterval, (_) async {
      try {
        await _reportLocalPlayerState();
      } catch (e) {
        _logger.log('Error reporting local player state (will retry): $e');
      }
    });
  }

  Future<void> _reportLocalPlayerState() async {
    if (_api == null) return;

    // Don't try to report state if not authenticated - avoids spamming errors
    if (_api!.currentConnectionState != MAConnectionState.authenticated) return;

    final playerId = await SettingsService.getBuiltinPlayerId();
    if (playerId == null) return;

    final isPlaying = _localPlayer.isPlaying;
    final position = _localPlayer.position.inSeconds;
    // Use tracked MA volume instead of just_audio player volume
    // just_audio volume is for local playback, MA volume is for server sync
    final volume = _localPlayerVolume;
    final isPaused = !isPlaying && position > 0;

    // Report via Sendspin if connected (MA 2.7.0b20+)
    if (_sendspinConnected && _sendspinService != null) {
      _sendspinService!.reportState(
        powered: _isLocalPlayerPowered,
        playing: isPlaying,
        paused: isPaused,
        position: position,
        volume: volume,
        muted: _localPlayerVolume == 0,
      );
      return;
    }

    // Otherwise use builtin_player API (older MA versions)
    if (!_builtinPlayerAvailable) return;

    await _api!.updateBuiltinPlayerState(
      playerId,
      powered: _isLocalPlayerPowered,
      playing: isPlaying,
      paused: isPaused,
      position: position,
      volume: volume,
      muted: _localPlayerVolume == 0,
    );
  }

  Future<void> _handleLocalPlayerEvent(Map<String, dynamic> event) async {
    _logger.log('📥 Local player event received: ${event['type'] ?? event['command']}');

    try {
      final eventPlayerId = event['player_id'] as String?;
      final myPlayerId = await SettingsService.getBuiltinPlayerId();

      if (eventPlayerId != null && myPlayerId != null && eventPlayerId != myPlayerId) {
        _logger.log('🚫 Ignoring event for different player: $eventPlayerId (my player: $myPlayerId)');
        return;
      }

      final command = (event['type'] as String?) ?? (event['command'] as String?);

      switch (command) {
        case 'play_media':
          final urlPath = event['media_url'] as String? ?? event['url'] as String?;

          _logger.log('🎵 play_media: urlPath=$urlPath, _serverUrl=$_serverUrl');

          if (urlPath != null && _serverUrl != null) {
            String fullUrl;
            if (urlPath.startsWith('http')) {
              fullUrl = urlPath;
            } else {
              var baseUrl = _serverUrl!;
              if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
                baseUrl = 'https://$baseUrl';
              }
              baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
              final path = urlPath.startsWith('/') ? urlPath : '/$urlPath';
              fullUrl = '$baseUrl$path';
            }

            TrackMetadata metadata;
            if (_pendingTrackMetadata != null) {
              metadata = _pendingTrackMetadata!;
              _logger.log('🎵 Using metadata from player_updated: ${metadata.title} by ${metadata.artist}');
            } else {
              final trackName = event['track_name'] as String? ?? event['name'] as String? ?? 'Unknown Track';
              final artistName = event['artist_name'] as String? ?? event['artist'] as String? ?? 'Unknown Artist';
              final albumName = event['album_name'] as String? ?? event['album'] as String?;
              var artworkUrl = event['image_url'] as String? ?? event['artwork_url'] as String?;
              final durationSecs = event['duration'] as int?;

              if (artworkUrl != null && artworkUrl.startsWith('http://')) {
                artworkUrl = artworkUrl.replaceFirst('http://', 'https://');
              }

              metadata = TrackMetadata(
                title: trackName,
                artist: artistName,
                album: albumName,
                artworkUrl: artworkUrl,
                duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
              );
            }

            _localPlayer.setCurrentTrackMetadata(metadata);
            _currentNotificationMetadata = metadata;

            await _localPlayer.playUrl(fullUrl);
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
        case 'set_volume':
          final volume = event['volume_level'] as int? ?? event['volume'] as int?;
          if (volume != null) {
            _localPlayerVolume = volume;
            await FlutterVolumeController.setVolume(volume / 100.0);
          }
          break;

        case 'power_on':
        case 'power_off':
        case 'power':
          _logger.log('🔋 POWER COMMAND RECEIVED: $command');

          bool? newPowerState;
          if (command == 'power_on') {
            newPowerState = true;
          } else if (command == 'power_off') {
            newPowerState = false;
          } else {
            newPowerState = event['powered'] as bool?;
          }

          if (newPowerState != null) {
            _isLocalPlayerPowered = newPowerState;
            _logger.log('🔋 Local player power set to: $_isLocalPlayerPowered');
            if (!_isLocalPlayerPowered) {
              _logger.log('🔋 Stopping playback because powered off');
              await _localPlayer.stop();
            }
          }
          break;
      }

      await _reportLocalPlayerState();
    } catch (e) {
      _logger.log('Error handling local player event: $e');
    }
  }

  /// Handle player_added event - refresh player list when new players join
  Future<void> _handlePlayerAddedEvent(Map<String, dynamic> event) async {
    try {
      final playerId = event['player_id'] as String?;
      final playerName = event['name'] as String?;
      _logger.log('🆕 Player added: $playerName ($playerId)');

      // Refresh the player list to include the new player
      await _loadAndSelectPlayers(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      _logger.log('Error handling player added event: $e');
    }
  }

  /// Handle media_item_added event - refresh library when items are added
  /// This handles the case where addToLibrary API call times out but the item was actually added
  void _handleMediaItemAddedEvent(Map<String, dynamic> event) {
    try {
      final mediaType = event['media_type'] as String?;
      _cacheService.invalidateSearchCache();
      _scheduleLibraryRefresh(mediaType ?? 'artist');
    } catch (e) {
      _logger.log('Error handling media item added event: $e');
    }
  }

  /// Handle media_item_deleted event - refresh library when items are removed
  /// This ensures UI updates even if removeFromLibrary API call times out
  void _handleMediaItemDeletedEvent(Map<String, dynamic> event) {
    try {
      final mediaType = event['media_type'] as String?;
      _cacheService.invalidateSearchCache();
      _scheduleLibraryRefresh(mediaType ?? 'artist');
    } catch (e) {
      _logger.log('Error handling media item deleted event: $e');
    }
  }

  Future<void> _handlePlayerUpdatedEvent(Map<String, dynamic> event) async {
    try {
      final playerId = event['player_id'] as String?;
      if (playerId == null) return;

      // Check if this event is for the selected player - also check translated Cast<->Sendspin IDs
      // Events may come with Cast ID but selected player uses Sendspin ID (or vice versa)
      if (_selectedPlayer != null) {
        final selectedId = _selectedPlayer!.playerId;
        final isMatch = playerId == selectedId ||
            _castToSendspinIdMap[playerId] == selectedId ||
            _castToSendspinIdMap[selectedId] == playerId;
        if (isMatch) {
          _updatePlayerState();
        }
      }

      // Update member volume in _availablePlayers for accurate group volume
      // computation. When MA changes a group member's volume (after setVolume
      // on the group player), it fires player_updated for each member.
      // Without this, _availablePlayers member volumes stay stale until the
      // next _updatePlayerState poll, which could cause the group average
      // to be wrong during the convergence check.
      final rawVolume = event['volume_level'];
      final eventVolume = rawVolume is int
          ? rawVolume
          : (rawVolume is double ? rawVolume.round() : null);
      if (eventVolume != null) {
        final idx = _availablePlayers.indexWhere((p) => p.playerId == playerId);
        if (idx != -1 && _availablePlayers[idx].volumeLevel != eventVolume) {
          _availablePlayers[idx] =
              _availablePlayers[idx].copyWith(volumeLevel: eventVolume);
        }
      }

      final currentMedia = event['current_media'] as Map<String, dynamic>?;
      final playerName = event['name'] as String? ?? playerId;

      if (currentMedia != null) {
        final mediaType = currentMedia['media_type'] as String?;
        final uri = currentMedia['uri'] as String?;

        // Debug: Log all currentMedia fields for podcast episodes
        if (uri != null && (uri.contains('podcast_episode') || uri.contains('podcast/'))) {
          _logger.log('🎙️ Podcast currentMedia keys: ${currentMedia.keys.toList()}');
          _logger.log('🎙️ Podcast currentMedia: $currentMedia');
        }

        // Check for external source (optical, Spotify Connect, etc.) - skip caching stale metadata
        // Use same logic as Player.fromJson:
        // 1. If app_id == 'music_assistant' -> NOT external
        // 2. If active_queue has value -> NOT external (MA controls playback)
        // 3. If app_id is set and != 'music_assistant' -> external
        // 4. Fallback: check for simple external IDs (optical, etc.)
        final appId = event['app_id'] as String?;
        final activeQueue = event['active_queue'] as String?;

        bool isExternalSource = false;
        if (appId == 'music_assistant') {
          isExternalSource = false;
        } else if (activeQueue != null && activeQueue.isNotEmpty) {
          isExternalSource = false;
        } else if (appId != null && appId.isNotEmpty) {
          isExternalSource = true;
        } else if (uri != null) {
          final uriLower = uri.toLowerCase();
          // Only check for simple external source identifiers (physical inputs)
          // Do NOT flag spotify://, etc. - those need app_id/active_queue context
          final isSimpleExternalId = !uri.contains('://') && !uri.contains('/') &&
              (uriLower == 'optical' || uriLower == 'line_in' || uriLower == 'bluetooth' ||
               uriLower == 'hdmi' || uriLower == 'tv' || uriLower == 'aux' ||
               uriLower == 'coaxial' || uriLower == 'toslink');
          isExternalSource = isSimpleExternalId;

          // Also treat unknown media type with non-MA URIs as external
          if (!isExternalSource && mediaType == 'unknown' &&
              !uri.startsWith('library://') && !uri.contains('://track/')) {
            isExternalSource = true;
          }
        }

        if (isExternalSource) {
          _logger.log('📡 External source detected for $playerName (app_id: $appId, uri: $uri) - skipping metadata cache');
          // Clear cached track for this player to avoid showing stale data
          _cacheService.clearCachedTrackForPlayer(playerId);
          return; // Skip further processing for external sources
        }

        // Clear audiobook context when switching to music (track) playback
        if (mediaType == 'track' && _currentAudiobook != null) {
          _logger.log('📚 Media type changed to track - clearing audiobook context');
          clearCurrentAudiobook();
        }

        // Clear podcast context when switching to non-podcast media
        if (mediaType != 'podcast_episode' && _currentPodcastName != null) {
          _logger.log('🎙️ Media type changed to $mediaType - clearing podcast context');
          clearCurrentPodcastName();
        }

        if (mediaType != 'flow_stream') {
          final durationSecs = (currentMedia['duration'] as num?)?.toInt();
          final albumName = currentMedia['album'] as String?;
          final imageUrl = currentMedia['image_url'] as String?;

          Map<String, dynamic>? metadata;
          if (imageUrl != null) {
            var finalImageUrl = imageUrl;
            if (_serverUrl != null) {
              try {
                final imgUri = Uri.parse(imageUrl);
                final queryString = imgUri.query;
                var baseUrl = _serverUrl!;
                if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
                  baseUrl = 'https://$baseUrl';
                }
                if (baseUrl.endsWith('/')) {
                  baseUrl = baseUrl.substring(0, baseUrl.length - 1);
                }
                finalImageUrl = '$baseUrl/imageproxy?$queryString';
              } catch (e) {
                // Use original URL
              }
            }
            metadata = {
              'images': [
                {'path': finalImageUrl, 'provider': 'direct'}
              ]
            };
          }

          // Extract podcast info if available (for podcast episodes)
          final podcastData = currentMedia['podcast'];
          if (podcastData != null) {
            metadata ??= {};
            metadata['podcast'] = podcastData;
            _logger.log('🎙️ Found podcast in currentMedia: $podcastData');
          }

          // Parse artist from title if artist is missing but title contains " - "
          var trackTitle = currentMedia['title'] as String? ?? 'Unknown Track';
          var artistName = currentMedia['artist'] as String?;

          // Check if this is a radio stream
          final isRadioStream = uri != null && (uri.contains('library://radio/') || uri.contains('/radio/'));

          // For radio streams, log the currentMedia to debug metadata structure
          if (isRadioStream) {
            _logger.log('📻 Radio currentMedia keys: ${currentMedia.keys.toList()}');
            _logger.log('📻 Radio currentMedia: $currentMedia');
          }

          // For radio streams, try additional artist sources if primary is missing
          if (isRadioStream && (artistName == null || artistName.isEmpty)) {
            // Check for artists array (like in Track.fromJson)
            final artistsData = currentMedia['artists'];
            if (artistsData is List && artistsData.isNotEmpty) {
              final firstArtist = artistsData.first;
              if (firstArtist is Map<String, dynamic>) {
                artistName = firstArtist['name'] as String?;
              } else if (firstArtist is String) {
                artistName = firstArtist;
              }
              _logger.log('📻 Found artist from artists array: $artistName');
            }

            // Check for stream_title which contains the actual now-playing metadata
            // For radio, stream_title has "Artist - Title" format from the stream's ICY metadata
            final streamTitle = currentMedia['stream_title'] as String?;
            if (streamTitle != null && streamTitle.isNotEmpty) {
              if (streamTitle.contains(' - ')) {
                // Parse "Artist - Title" format
                final parts = streamTitle.split(' - ');
                if (parts.length >= 2) {
                  artistName = parts[0].trim();
                  trackTitle = parts.sublist(1).join(' - ').trim();
                  _logger.log('📻 Parsed from stream_title: artist=$artistName, title=$trackTitle');
                }
              } else {
                // No separator, use stream_title as the title
                trackTitle = streamTitle;
                _logger.log('📻 Using stream_title as title: $trackTitle');
              }
            }
          }

          if ((artistName == null || artistName == 'Unknown Artist') && trackTitle.contains(' - ')) {
            final parts = trackTitle.split(' - ');
            if (parts.length >= 2) {
              artistName = parts[0].trim();
              trackTitle = parts.sublist(1).join(' - ').trim();
            }
          }
          artistName ??= 'Unknown Artist';

          final trackFromEvent = Track(
            itemId: currentMedia['queue_item_id'] as String? ?? '',
            provider: 'library',
            name: trackTitle,
            uri: currentMedia['uri'] as String?,
            duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
            artists: [Artist(itemId: '', provider: 'library', name: artistName)],
            album: albumName != null ? Album(itemId: '', provider: 'library', name: albumName) : null,
            metadata: metadata,
          );

          // Only cache if we don't already have better data from queue
          final existingTrack = _cacheService.getCachedTrackForPlayer(playerId);
          // Check if existing track has proper artist (not Unknown Artist and not empty)
          final existingArtist = existingTrack?.artistsString;
          final existingHasProperArtist = existingTrack != null &&
              existingArtist != null &&
              existingArtist != 'Unknown Artist' &&
              existingArtist.trim().isNotEmpty;
          final existingHasImage = existingTrack?.metadata?['images'] != null;
          final newHasImage = metadata != null;
          final newHasAlbum = albumName != null;
          final existingHasAlbum = existingTrack?.album != null;
          // Check if new data has proper artist AND title (not malformed like "- Something")
          final newTitleIsMalformed = trackTitle.startsWith('- ') || trackTitle.trim().isEmpty;
          final newHasProperArtist = artistName != 'Unknown Artist' && !newTitleIsMalformed;

          // For podcasts, album info is crucial (it's the podcast name)
          // If new track has album but existing doesn't, prefer new or merge
          final isPodcastUri = uri != null && (uri.contains('podcast_episode') || uri.contains('podcast/'));

          // For radio streams, always update when we have new metadata (song changes frequently)
          // This ensures radio artist/title changes are reflected immediately
          final isRadioUri = uri != null && (uri.contains('library://radio/') || uri.contains('/radio/'));

          // Keep existing if it has proper artist OR has image that new one lacks
          // BUT for podcasts, if new has album and existing doesn't, we need that album data
          // AND for radio, always update when new track has proper artist (song changed)
          final keepExisting = (existingHasProperArtist || (existingHasImage && !newHasImage))
              && !(isPodcastUri && newHasAlbum && !existingHasAlbum)
              && !(isRadioUri && newHasProperArtist);

          if (!keepExisting) {
            _cacheService.setCachedTrackForPlayer(playerId, trackFromEvent);
            _logger.log('📋 Cached track for $playerName from player_updated: ${trackFromEvent.name}');

            // Dual-cache for Cast<->Sendspin players so track is findable by either ID
            final sendspinId = _castToSendspinIdMap[playerId];
            if (sendspinId != null) {
              _cacheService.setCachedTrackForPlayer(sendspinId, trackFromEvent);
              _logger.log('📋 Also cached under Sendspin ID: $sendspinId');
            } else if (playerId.length >= 8 && playerId.contains('-')) {
              // Compute Sendspin ID for chromecast players not yet in map
              final computedSendspinId = 'cast-${playerId.substring(0, 8)}';
              _cacheService.setCachedTrackForPlayer(computedSendspinId, trackFromEvent);
              _logger.log('📋 Also cached under computed Sendspin ID: $computedSendspinId');
            }
          } else if (isPodcastUri && newHasAlbum && existingTrack != null && !existingHasAlbum) {
            // Merge: keep existing but add album from new track
            final mergedTrack = Track(
              itemId: existingTrack.itemId,
              provider: existingTrack.provider,
              name: existingTrack.name,
              uri: existingTrack.uri,
              duration: existingTrack.duration,
              artists: existingTrack.artists,
              album: trackFromEvent.album, // Take album from new track
              metadata: existingTrack.metadata,
            );
            _cacheService.setCachedTrackForPlayer(playerId, mergedTrack);
            _logger.log('📋 Merged album info into existing track for $playerName: ${albumName}');
          } else {
            _logger.log('📋 Skipped caching for $playerName - already have better data (artist: $existingHasProperArtist, image: $existingHasImage)');
          }

          // For selected player, _updatePlayerState() is already called above which fetches queue data
          // Update _currentTrack if:
          // - We don't have it yet
          // - Podcast with new album data
          // - Radio with new stream metadata (artist changed from Unknown)
          final currentHasUnknownArtist = _currentTrack?.artistsString == 'Unknown Artist' ||
              _currentTrack?.artistsString == null;
          final shouldUpdateCurrentTrack = _selectedPlayer != null &&
              playerId == _selectedPlayer!.playerId &&
              (_currentTrack == null ||
               (isPodcastUri && newHasAlbum && _currentTrack?.album == null) ||
               (isRadioUri && newHasProperArtist && currentHasUnknownArtist));
          if (shouldUpdateCurrentTrack) {
            _currentTrack = _cacheService.getCachedTrackForPlayer(playerId) ?? trackFromEvent;
            _logger.log('📋 Updated _currentTrack: ${_currentTrack?.name} by ${_currentTrack?.artistsString}');
          }

          notifyListeners();
        }
      }

      // Handle notification metadata for local player
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId == null) return;

      if (playerId != builtinPlayerId) return;

      if (currentMedia == null) return;

      var title = currentMedia['title'] as String? ?? 'Unknown Track';
      var artist = currentMedia['artist'] as String?;
      final album = currentMedia['album'] as String?;
      var imageUrl = currentMedia['image_url'] as String?;
      final durationSecs = (currentMedia['duration'] as num?)?.toInt();
      final notificationUri = currentMedia['uri'] as String?;
      final isRadioNotification = notificationUri != null &&
          (notificationUri.contains('library://radio/') || notificationUri.contains('/radio/'));

      // For radio streams, try to extract artist from various sources
      if (isRadioNotification && (artist == null || artist.isEmpty)) {
        // Check for artists array
        final artistsData = currentMedia['artists'];
        if (artistsData is List && artistsData.isNotEmpty) {
          final firstArtist = artistsData.first;
          if (firstArtist is Map<String, dynamic>) {
            artist = firstArtist['name'] as String?;
          } else if (firstArtist is String) {
            artist = firstArtist;
          }
        }

        // Check for stream_title which contains the actual now-playing metadata
        final streamTitle = currentMedia['stream_title'] as String?;
        if (streamTitle != null && streamTitle.isNotEmpty) {
          if (streamTitle.contains(' - ')) {
            // Parse "Artist - Title" format
            final parts = streamTitle.split(' - ');
            if (parts.length >= 2) {
              artist = parts[0].trim();
              title = parts.sublist(1).join(' - ').trim();
            }
          } else {
            // No separator, use stream_title as the title
            title = streamTitle;
          }
        }
      }

      // Parse artist from title if still missing
      if ((artist == null || artist == 'Unknown Artist') && title.contains(' - ')) {
        final parts = title.split(' - ');
        if (parts.length >= 2) {
          artist = parts[0].trim();
          title = parts.sublist(1).join(' - ').trim();
        }
      }
      artist ??= 'Unknown Artist';

      if (imageUrl != null && _serverUrl != null) {
        try {
          final imgUri = Uri.parse(imageUrl);
          final queryString = imgUri.query;
          var baseUrl = _serverUrl!;
          if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
            baseUrl = 'https://$baseUrl';
          }
          if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.substring(0, baseUrl.length - 1);
          }
          imageUrl = '$baseUrl/imageproxy?$queryString';
        } catch (e) {
          if (imageUrl != null && imageUrl.startsWith('http://')) {
            imageUrl = imageUrl.replaceFirst('http://', 'https://');
          }
        }
      }

      final newMetadata = TrackMetadata(
        title: title,
        artist: artist,
        album: album,
        artworkUrl: imageUrl,
        duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
      );

      final mediaType = currentMedia['media_type'] as String?;
      if (mediaType == 'flow_stream') return;

      _pendingTrackMetadata = newMetadata;
      _logger.log('📋 Captured track metadata from player_updated: $title by $artist');

      final notificationNeedsUpdate = _currentNotificationMetadata != null &&
          (_currentNotificationMetadata!.title != title ||
           _currentNotificationMetadata!.artist != artist);

      if (_localPlayer.isPlaying && notificationNeedsUpdate) {
        _logger.log('📋 Notification has stale metadata - updating to: $title by $artist');
        await _localPlayer.updateNotificationWhilePlaying(newMetadata);
        _currentNotificationMetadata = newMetadata;
      }
    } catch (e) {
      _logger.log('Error handling player_updated event: $e');
    }
  }

  // ============================================================================
  // SEARCH STATE
  // ============================================================================

  void saveSearchState(String query, Map<String, List<MediaItem>> results) {
    _lastSearchQuery = query;
    _lastSearchResults = results;
  }

  void clearSearchState() {
    _lastSearchQuery = '';
    _lastSearchResults = {'artists': [], 'albums': [], 'tracks': []};
  }

  // ============================================================================
  // HOME SCREEN ROW CACHING
  // ============================================================================

  Future<List<Album>> getRecentAlbumsWithCache({bool forceRefresh = false}) async {
    // Always fetch from API to ensure we have full album data with images
    // Local/cached data is used by getCachedRecentAlbums() for instant display
    if (_api == null) {
      // Fallback when offline: try memory cache, then local database
      final cached = _cacheService.getCachedRecentAlbums();
      if (cached != null && cached.isNotEmpty) return cached;
      return RecentlyPlayedService.instance.getRecentAlbums(
        limit: LibraryConstants.defaultRecentLimit,
      );
    }

    try {
      _logger.log('🔄 Fetching fresh recent albums from MA...');
      final albums = await _api!.getRecentAlbums(limit: LibraryConstants.defaultRecentLimit);
      // Apply provider filtering
      final filtered = filterByProvider(albums);
      _cacheService.setCachedRecentAlbums(filtered);
      return filtered;
    } catch (e) {
      _logger.log('❌ Failed to fetch recent albums: $e');
      // Fallback on error: try memory cache, then local database
      final cached = _cacheService.getCachedRecentAlbums();
      if (cached != null && cached.isNotEmpty) return filterByProvider(cached);
      final local = await RecentlyPlayedService.instance.getRecentAlbums(
        limit: LibraryConstants.defaultRecentLimit,
      );
      return filterByProvider(local);
    }
  }

  Future<List<Artist>> getDiscoverArtistsWithCache({bool forceRefresh = false}) async {
    if (_cacheService.isDiscoverArtistsCacheValid(forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached discover artists');
      return _cacheService.getCachedDiscoverArtists()!;
    }

    if (_api == null) return _cacheService.getCachedDiscoverArtists() ?? [];

    try {
      _logger.log('🔄 Fetching fresh discover artists...');
      final artists = await _api!.getRandomArtists(
        limit: LibraryConstants.defaultRecentLimit,
        providerInstanceIds: providerIdsForApiCalls,
      );
      _cacheService.setCachedDiscoverArtists(artists);
      return artists;
    } catch (e) {
      _logger.log('❌ Failed to fetch discover artists: $e');
      return _cacheService.getCachedDiscoverArtists() ?? [];
    }
  }

  Future<List<Album>> getDiscoverAlbumsWithCache({bool forceRefresh = false}) async {
    if (_cacheService.isDiscoverAlbumsCacheValid(forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached discover albums');
      return _cacheService.getCachedDiscoverAlbums()!;
    }

    if (_api == null) return _cacheService.getCachedDiscoverAlbums() ?? [];

    try {
      _logger.log('🔄 Fetching fresh discover albums...');
      final albums = await _api!.getRandomAlbums(
        limit: LibraryConstants.defaultRecentLimit,
        providerInstanceIds: providerIdsForApiCalls,
      );
      _cacheService.setCachedDiscoverAlbums(albums);
      return albums;
    } catch (e) {
      _logger.log('❌ Failed to fetch discover albums: $e');
      return _cacheService.getCachedDiscoverAlbums() ?? [];
    }
  }

  void invalidateHomeCache() {
    _cacheService.invalidateHomeCache();
  }

  /// Get cached recent albums synchronously (for instant display)
  List<Album>? getCachedRecentAlbums() => _cacheService.getCachedRecentAlbums();

  /// Get cached discover artists synchronously (for instant display)
  List<Artist>? getCachedDiscoverArtists() => _cacheService.getCachedDiscoverArtists();

  /// Get cached discover albums synchronously (for instant display)
  List<Album>? getCachedDiscoverAlbums() => _cacheService.getCachedDiscoverAlbums();

  /// Force a full library sync (for pull-to-refresh)
  Future<void> forceLibrarySync() async {
    if (_api == null) {
      _logger.log('⚠️ forceLibrarySync: API is null, skipping');
      return;
    }

    final providerIds = providerIdsForApiCalls;
    _logger.log('🔄 Forcing full library sync with providers: ${providerIds ?? "ALL"}');
    await SyncService.instance.forceSync(_api!, providerInstanceIds: providerIds);

    // Update local lists from sync result
    _albums = SyncService.instance.cachedAlbums;
    _artists = SyncService.instance.cachedArtists;

    // Also refresh tracks from API
    try {
      _tracks = await _api!.getTracks(
        limit: LibraryConstants.maxLibraryItems,
        providerInstanceIds: providerIdsForApiCalls,
      );
    } catch (e) {
      _logger.log('⚠️ Failed to refresh tracks: $e');
    }

    _syncLibraryStatusToService();
    notifyListeners();
    _logger.log('✅ Force sync complete');
  }

  // ============================================================================
  // FAVORITES FOR HOME SCREEN
  // ============================================================================

  /// Get favorite albums from the library
  Future<List<Album>> getFavoriteAlbums() async {
    // Filter from loaded library - favorites are already loaded
    return _albums.where((a) => a.favorite == true).toList();
  }

  /// Get favorite artists from the library
  Future<List<Artist>> getFavoriteArtists() async {
    // Filter from loaded library - favorites are already loaded
    return _artists.where((a) => a.favorite == true).toList();
  }

  /// Get favorite tracks from the library
  Future<List<Track>> getFavoriteTracks() async {
    // If full tracks list is loaded, filter from it
    if (_tracks.isNotEmpty) {
      final favTracks = _tracks.where((t) => t.favorite == true).toList();
      // Update cache if we have new data
      if (favTracks.isNotEmpty && favTracks.length != _cachedFavoriteTracks.length) {
        _cachedFavoriteTracks = favTracks;
        _persistFavoriteTracks(favTracks);
      }
      return favTracks;
    }
    // Otherwise return cached favorites (for instant display before full library loads)
    return _cachedFavoriteTracks;
  }

  /// Get favorite playlists from the library
  Future<List<Playlist>> getFavoritePlaylists() async {
    if (_api == null) return [];
    try {
      return await getPlaylists(favoriteOnly: true);
    } catch (e) {
      _logger.log('❌ Failed to fetch favorite playlists: $e');
      return [];
    }
  }

  /// Get favorite radio stations from the library
  Future<List<MediaItem>> getFavoriteRadioStations() async {
    if (_api == null) return [];
    try {
      final stations = await _api!.getRadioStations(favoriteOnly: true);
      return filterByProvider(stations);
    } catch (e) {
      _logger.log('❌ Failed to fetch favorite radio stations: $e');
      return [];
    }
  }

  /// Get favorite podcasts from the library
  Future<List<MediaItem>> getFavoritePodcasts() async {
    if (_api == null) return [];
    try {
      final podcasts = await _api!.getPodcasts(favoriteOnly: true);
      return filterByProvider(podcasts);
    } catch (e) {
      _logger.log('❌ Failed to fetch favorite podcasts: $e');
      return [];
    }
  }

  // ============================================================================
  // AUDIOBOOK HOME SCREEN ROWS
  // ============================================================================

  /// Get audiobooks that have progress (continue listening) with caching
  Future<List<Audiobook>> getInProgressAudiobooksWithCache({bool forceRefresh = false}) async {
    // Check cache first
    if (!forceRefresh && _cacheService.isInProgressAudiobooksCacheValid()) {
      _logger.log('📦 Using cached in-progress audiobooks');
      return _cacheService.getCachedInProgressAudiobooks()!;
    }

    if (_api == null) {
      // Fallback to cache when offline
      final cached = _cacheService.getCachedInProgressAudiobooks();
      if (cached != null && cached.isNotEmpty) return cached;
      return [];
    }

    try {
      _logger.log('📚 Fetching in-progress audiobooks...');
      final allAudiobooks = filterByProvider(await _api!.getAudiobooks());
      // Filter to only those with progress, sorted by most recent/highest progress
      final inProgress = allAudiobooks
          .where((a) => a.progress > 0 && a.progress < 1.0) // Has progress but not complete
          .toList()
        ..sort((a, b) => b.progress.compareTo(a.progress)); // Sort by progress descending
      final result = inProgress.take(20).toList(); // Limit to 20 for home row
      _logger.log('📚 Found ${result.length} in-progress audiobooks');
      _cacheService.setCachedInProgressAudiobooks(result);
      return result;
    } catch (e) {
      _logger.log('❌ Failed to fetch in-progress audiobooks: $e');
      // Fallback to cache on error
      final cached = _cacheService.getCachedInProgressAudiobooks();
      if (cached != null && cached.isNotEmpty) return cached;
      return [];
    }
  }

  /// Get cached in-progress audiobooks synchronously (for instant display)
  List<Audiobook>? getCachedInProgressAudiobooks() => _cacheService.getCachedInProgressAudiobooks();

  /// Get random audiobooks for discovery with caching
  Future<List<Audiobook>> getDiscoverAudiobooksWithCache({bool forceRefresh = false}) async {
    // Check cache first
    if (!forceRefresh && _cacheService.isDiscoverAudiobooksCacheValid()) {
      _logger.log('📦 Using cached discover audiobooks');
      return _cacheService.getCachedDiscoverAudiobooks()!;
    }

    if (_api == null) {
      // Fallback to cache when offline
      final cached = _cacheService.getCachedDiscoverAudiobooks();
      if (cached != null && cached.isNotEmpty) return cached;
      return [];
    }

    try {
      _logger.log('📚 Fetching discover audiobooks...');
      final allAudiobooks = filterByProvider(await _api!.getAudiobooks());
      // Shuffle and take a subset
      final shuffled = List<Audiobook>.from(allAudiobooks)..shuffle();
      final result = shuffled.take(20).toList();
      _logger.log('📚 Found ${allAudiobooks.length} total audiobooks, returning random selection');
      _cacheService.setCachedDiscoverAudiobooks(result);
      return result;
    } catch (e) {
      _logger.log('❌ Failed to fetch discover audiobooks: $e');
      // Fallback to cache on error
      final cached = _cacheService.getCachedDiscoverAudiobooks();
      if (cached != null && cached.isNotEmpty) return cached;
      return [];
    }
  }

  /// Get cached discover audiobooks synchronously (for instant display)
  List<Audiobook>? getCachedDiscoverAudiobooks() => _cacheService.getCachedDiscoverAudiobooks();

  /// Get random series for discovery with caching
  Future<List<AudiobookSeries>> getDiscoverSeriesWithCache({bool forceRefresh = false}) async {
    // Check cache first
    if (!forceRefresh && _cacheService.isDiscoverSeriesCacheValid()) {
      _logger.log('📦 Using cached discover series');
      return _cacheService.getCachedDiscoverSeries()!;
    }

    if (_api == null) {
      // Fallback to cache when offline
      final cached = _cacheService.getCachedDiscoverSeries();
      if (cached != null && cached.isNotEmpty) return cached;
      return [];
    }

    try {
      _logger.log('📚 Fetching discover series...');
      final allSeries = await _api!.getAudiobookSeries();
      // Shuffle and take a subset
      final shuffled = List<AudiobookSeries>.from(allSeries)..shuffle();
      final result = shuffled.take(20).toList();
      _logger.log('📚 Found ${allSeries.length} total series, returning random selection');
      _cacheService.setCachedDiscoverSeries(result);
      return result;
    } catch (e) {
      _logger.log('❌ Failed to fetch discover series: $e');
      // Fallback to cache on error
      final cached = _cacheService.getCachedDiscoverSeries();
      if (cached != null && cached.isNotEmpty) return cached;
      return [];
    }
  }

  /// Get cached discover series synchronously (for instant display)
  List<AudiobookSeries>? getCachedDiscoverSeries() => _cacheService.getCachedDiscoverSeries();

  // ============================================================================
  // DETAIL SCREEN CACHING
  // ============================================================================

  Future<List<Track>> getAlbumTracksWithCache(String provider, String itemId, {bool forceRefresh = false}) async {
    final cacheKey = '${provider}_$itemId';

    if (_cacheService.isAlbumTracksCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached album tracks for $cacheKey');
      return _cacheService.getCachedAlbumTracks(cacheKey)!;
    }

    if (_api == null) return _cacheService.getCachedAlbumTracks(cacheKey) ?? [];

    try {
      _logger.log('🔄 Fetching fresh album tracks for $cacheKey...');
      final tracks = await _api!.getAlbumTracks(provider, itemId);
      _cacheService.setCachedAlbumTracks(cacheKey, tracks);
      return tracks;
    } catch (e) {
      _logger.log('❌ Failed to fetch album tracks: $e');
      return _cacheService.getCachedAlbumTracks(cacheKey) ?? [];
    }
  }

  Future<List<Track>> getPlaylistTracksWithCache(String provider, String itemId, {bool forceRefresh = false}) async {
    final cacheKey = '${provider}_$itemId';

    if (_cacheService.isPlaylistTracksCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached playlist tracks for $cacheKey');
      return _cacheService.getCachedPlaylistTracks(cacheKey)!;
    }

    if (_api == null) return _cacheService.getCachedPlaylistTracks(cacheKey) ?? [];

    try {
      _logger.log('🔄 Fetching fresh playlist tracks for $cacheKey...');
      final tracks = await _api!.getPlaylistTracks(provider, itemId);
      _cacheService.setCachedPlaylistTracks(cacheKey, tracks);
      return tracks;
    } catch (e) {
      _logger.log('❌ Failed to fetch playlist tracks: $e');
      return _cacheService.getCachedPlaylistTracks(cacheKey) ?? [];
    }
  }

  Future<List<Album>> getArtistAlbumsWithCache(String artistName, {bool forceRefresh = false}) async {
    final cacheKey = artistName.toLowerCase();

    if (_cacheService.isArtistAlbumsCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached artist albums for "$artistName"');
      return _cacheService.getCachedArtistAlbums(cacheKey)!;
    }

    if (_api == null) return _cacheService.getCachedArtistAlbums(cacheKey) ?? [];

    try {
      _logger.log('🔄 Fetching albums for artist "$artistName"...');

      // Fetch all library albums (with high limit to get full library)
      final libraryAlbums = await _api!.getAlbums(limit: LibraryConstants.maxLibraryItems);
      _logger.log('📚 Fetched ${libraryAlbums.length} total library albums');
      final artistAlbums = libraryAlbums.where((album) {
        final albumArtists = album.artists;
        if (albumArtists == null || albumArtists.isEmpty) return false;
        return albumArtists.any((a) => a.name.toLowerCase() == artistName.toLowerCase());
      }).toList();

      final searchResults = await _api!.search(artistName);
      final searchAlbums = searchResults['albums'] as List<MediaItem>? ?? [];
      final providerAlbums = searchAlbums.whereType<Album>().where((album) {
        final albumArtists = album.artists;
        if (albumArtists == null || albumArtists.isEmpty) return false;
        return albumArtists.any((a) => a.name.toLowerCase() == artistName.toLowerCase());
      }).toList();

      final allAlbums = <Album>[];
      final seenNames = <String>{};

      for (final album in [...artistAlbums, ...providerAlbums]) {
        final key = album.name.toLowerCase();
        if (!seenNames.contains(key)) {
          seenNames.add(key);
          allAlbums.add(album);
        }
      }

      _cacheService.setCachedArtistAlbums(cacheKey, allAlbums);
      _logger.log('✅ Cached ${allAlbums.length} albums for artist "$artistName"');
      return allAlbums;
    } catch (e) {
      _logger.log('❌ Failed to fetch artist albums: $e');
      return _cacheService.getCachedArtistAlbums(cacheKey) ?? [];
    }
  }

  void invalidateAlbumTracksCache(String albumId) {
    _cacheService.invalidateAlbumTracksCache(albumId);
  }

  void invalidatePlaylistTracksCache(String playlistId) {
    _cacheService.invalidatePlaylistTracksCache(playlistId);
  }

  // ============================================================================
  // SEARCH CACHING
  // ============================================================================

  Future<Map<String, List<MediaItem>>> searchWithCache(String query, {bool forceRefresh = false, bool libraryOnly = false}) async {
    final baseKey = query.toLowerCase().trim();
    if (baseKey.isEmpty) return {'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': []};

    // Include libraryOnly in cache key to separate results
    final cacheKey = libraryOnly ? '$baseKey:library' : baseKey;

    if (_cacheService.isSearchCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached search results for "$query" (libraryOnly: $libraryOnly)');
      return _cacheService.getCachedSearchResults(cacheKey)!;
    }

    if (_api == null) {
      return _cacheService.getCachedSearchResults(cacheKey) ?? {'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': []};
    }

    try {
      _logger.log('🔄 Searching for "$query" (libraryOnly: $libraryOnly)...');
      final results = await _api!.search(query, libraryOnly: libraryOnly);

      final cachedResults = <String, List<MediaItem>>{
        'artists': results['artists'] ?? [],
        'albums': results['albums'] ?? [],
        'tracks': results['tracks'] ?? [],
        'playlists': results['playlists'] ?? [],
        'audiobooks': results['audiobooks'] ?? [],
      };

      _cacheService.setCachedSearchResults(cacheKey, cachedResults);
      _logger.log('✅ Cached search results for "$query"');
      return cachedResults;
    } catch (e) {
      _logger.log('❌ Search failed: $e');
      return _cacheService.getCachedSearchResults(cacheKey) ?? {'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': []};
    }
  }

  void clearAllDetailCaches() {
    _cacheService.clearAllDetailCaches();
  }

  /// Get cached album tracks (for instant display before background refresh)
  List<Track>? getCachedAlbumTracks(String cacheKey) {
    return _cacheService.getCachedAlbumTracks(cacheKey);
  }

  /// Get cached playlist tracks (for instant display before background refresh)
  List<Track>? getCachedPlaylistTracks(String cacheKey) {
    return _cacheService.getCachedPlaylistTracks(cacheKey);
  }

  /// Get cached artist albums (for instant display before background refresh)
  List<Album>? getCachedArtistAlbums(String artistName) {
    return _cacheService.getCachedArtistAlbums(artistName.toLowerCase());
  }

  // ============================================================================
  // PLAYER SELECTION
  // ============================================================================

  Future<List<Player>> getAllPlayersUnfiltered() async {
    return await getPlayers();
  }

  Future<String?> getCurrentPlayerId() async {
    return await SettingsService.getBuiltinPlayerId();
  }

  /// Sort players list based on smart sort setting
  /// Can be called synchronously with pre-fetched settings for cached players
  void _sortPlayersSync(List<Player> players, bool smartSort, String? builtinPlayerId) {
    if (smartSort) {
      // Smart sort: local player first, then playing, then on, then off
      players.sort((a, b) {
        // Local player always first
        final aIsLocal = builtinPlayerId != null && a.playerId == builtinPlayerId;
        final bIsLocal = builtinPlayerId != null && b.playerId == builtinPlayerId;
        if (aIsLocal && !bIsLocal) return -1;
        if (bIsLocal && !aIsLocal) return 1;

        // Then by status: playing > on > off
        int statusPriority(Player p) {
          if (p.state == 'playing') return 0;
          if (p.powered && p.state != 'off') return 1;
          return 2;
        }
        final aPriority = statusPriority(a);
        final bPriority = statusPriority(b);
        if (aPriority != bPriority) return aPriority.compareTo(bPriority);

        // Within same status, sort alphabetically
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } else {
      // Default alphabetical sort
      players.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  Future<void> _loadAndSelectPlayers({bool forceRefresh = false, bool coldStart = false}) async {
    try {
      // Don't skip on coldStart - we need to apply full auto-selection priority logic
      if (!forceRefresh &&
          !coldStart &&
          _cacheService.isPlayersCacheValid() &&
          _availablePlayers.isNotEmpty) {
        return;
      }

      // Load persisted Cast-to-Sendspin mappings from database
      // This ensures we remember mappings even when Sendspin players are unavailable
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

      final allPlayers = await getPlayers();
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();

      _logger.log('🎛️ getPlayers returned ${allPlayers.length} players:');

      int filteredCount = 0;

      _availablePlayers = allPlayers.where((player) {
        final nameLower = player.name.toLowerCase();

        if (nameLower.contains('music assistant mobile')) {
          filteredCount++;
          return false;
        }

        // Filter out MA Web UI's built-in player (provider is 'builtin_player' and starts with 'ma_')
        // Note: We check BOTH conditions to avoid filtering snapcast/other players that may have 'ma_' prefix
        if (player.provider == 'builtin_player' && player.playerId.startsWith('ma_')) {
          _logger.log('🚫 Filtering out MA Web UI player: ${player.name} (provider: ${player.provider}, id: ${player.playerId})');
          filteredCount++;
          return false;
        }

        // Also filter "This Device" named players without proper provider
        if (nameLower == 'this device') {
          _logger.log('🚫 Filtering out "This Device" player: ${player.name}');
          filteredCount++;
          return false;
        }

        if (player.playerId.startsWith('ensemble_')) {
          if (builtinPlayerId == null || player.playerId != builtinPlayerId) {
            _logger.log('🚫 Filtering out other device\'s player: ${player.name}');
            filteredCount++;
            return false;
          }
        }

        if (!player.available) {
          if (builtinPlayerId != null && player.playerId == builtinPlayerId) {
            return true;
          }
          filteredCount++;
          return false;
        }

        return true;
      }).toList();

      // Smart Sendspin/Cast player switching:
      // - When grouped: show Sendspin version (renamed), hide original Cast
      // - When ungrouped: show original Cast, hide Sendspin version
      // This gives power control and proper queue behavior when not syncing
      final sendspinSuffix = ' (Sendspin)';

      // Detect Sendspin players by:
      // 1. Name ends with " (Sendspin)" (e.g., "Kitchen speaker (Sendspin)")
      // 2. ID starts with "cast-" and name equals ID (e.g., ID="cast-7df484e3", name="cast-7df484e3")
      //    This handles Cast devices where MA registers Sendspin player with raw ID as name
      bool isSendspinPlayer(Player p) {
        if (p.name.endsWith(sendspinSuffix)) return true;
        // Check for Sendspin players named with their raw ID (cast-{uuid-prefix})
        if (p.playerId.startsWith('cast-') && p.name == p.playerId) return true;
        return false;
      }

      final sendspinPlayers = _availablePlayers.where(isSendspinPlayer).toList();

      // NOTE: Don't clear _castToSendspinIdMap - we want to remember mappings
      // even when the Sendspin player is temporarily unavailable (e.g., device off)
      // This allows syncing to work when the device powers back on

      if (sendspinPlayers.isNotEmpty) {
        // Build maps for Sendspin players and their grouped status
        final sendspinByBaseName = <String, Player>{};
        final groupedSendspinBaseNames = <String>{};
        // Track Sendspin players that have raw ID as name (need renaming)
        final rawIdSendspinPlayers = <String, Player>{};

        for (final player in sendspinPlayers) {
          String baseName;
          Player? regularCastPlayer;

          if (player.name.endsWith(sendspinSuffix)) {
            // Standard "(Sendspin)" suffix naming
            baseName = player.name.substring(0, player.name.length - sendspinSuffix.length);
            regularCastPlayer = _availablePlayers.where(
              (p) => p.name == baseName && !isSendspinPlayer(p)
            ).firstOrNull;
          } else if (player.playerId.startsWith('cast-') && player.name == player.playerId) {
            // Raw ID naming (e.g., "cast-7df484e3") - find matching Cast player by UUID prefix
            // Sendspin ID format: cast-{first 8 chars of Cast UUID}
            // Cast ID format: {uuid} e.g., 7df484e3-d2ee-c897-f746-2dffc29595ff
            final sendspinPrefix = player.playerId.substring(5); // Remove "cast-" prefix
            regularCastPlayer = _availablePlayers.where(
              (p) => p.playerId.startsWith(sendspinPrefix) && !isSendspinPlayer(p)
            ).firstOrNull;
            baseName = regularCastPlayer?.name ?? player.name;
            if (regularCastPlayer != null) {
              rawIdSendspinPlayers[player.playerId] = player;
              _logger.log('🔍 Found raw-ID Sendspin player: ${player.playerId} matches Cast player "${regularCastPlayer.name}"');
            }
          } else {
            continue;
          }

          sendspinByBaseName[baseName] = player;

          // Store the ID mapping and persist to database
          if (regularCastPlayer != null) {
            _castToSendspinIdMap[regularCastPlayer.playerId] = player.playerId;
            _logger.log('🔗 Mapped Cast ID ${regularCastPlayer.playerId} -> Sendspin ID ${player.playerId}');
            // Persist mapping so it survives when Sendspin player is unavailable
            DatabaseService.instance.saveCastToSendspinMapping(
              regularCastPlayer.playerId,
              player.playerId,
            );
          }

          if (player.isGrouped) {
            groupedSendspinBaseNames.add(baseName);
            _logger.log('🔊 Sendspin player "$baseName" is grouped - will prefer Sendspin version');
          } else {
            _logger.log('🔊 Sendspin player "$baseName" is ungrouped - will prefer original Cast');
          }
        }

        // Filter players based on grouped status
        _availablePlayers = _availablePlayers.where((player) {
          final isSendspin = isSendspinPlayer(player);

          if (isSendspin) {
            // Get base name for this Sendspin player
            String baseName;
            if (player.name.endsWith(sendspinSuffix)) {
              baseName = player.name.substring(0, player.name.length - sendspinSuffix.length);
            } else if (rawIdSendspinPlayers.containsKey(player.playerId)) {
              // For raw ID players, find the base name from our earlier mapping
              baseName = sendspinByBaseName.entries
                  .firstWhere((e) => e.value.playerId == player.playerId,
                      orElse: () => MapEntry(player.name, player))
                  .key;
            } else {
              baseName = player.name;
            }

            // Keep Sendspin only if grouped
            if (player.isGrouped) {
              return true;
            } else {
              _logger.log('🚫 Hiding ungrouped Sendspin player: ${player.name}');
              filteredCount++;
              return false;
            }
          } else {
            // For regular players, hide if Sendspin version exists AND is grouped
            if (groupedSendspinBaseNames.contains(player.name)) {
              _logger.log('🚫 Preferring grouped Sendspin version over: ${player.name}');
              filteredCount++;
              return false;
            }
            return true;
          }
        }).toList();

        // Rename remaining Sendspin players to remove the suffix or give proper name
        _availablePlayers = _availablePlayers.map((player) {
          if (player.name.endsWith(sendspinSuffix)) {
            final cleanName = player.name.substring(0, player.name.length - sendspinSuffix.length);
            _logger.log('✨ Renaming "${player.name}" to "$cleanName"');
            return player.copyWith(name: cleanName);
          }
          // Rename raw ID Sendspin players to their proper name
          if (rawIdSendspinPlayers.containsKey(player.playerId)) {
            final properName = sendspinByBaseName.entries
                .firstWhere((e) => e.value.playerId == player.playerId,
                    orElse: () => MapEntry(player.name, player))
                .key;
            if (properName != player.name) {
              _logger.log('✨ Renaming raw ID Sendspin "${player.name}" to "$properName"');
              return player.copyWith(name: properName);
            }
          }
          return player;
        }).toList();
      }

      // Sort players using helper method
      final smartSort = await SettingsService.getSmartSortPlayers();
      _sortPlayersSync(_availablePlayers, smartSort, builtinPlayerId);

      // Cache players for instant display on app resume
      _cacheService.setCachedPlayers(_availablePlayers);

      // Persist players to database for app restart persistence
      _persistPlayersToDatabase(_availablePlayers);

      _logger.log('🎛️ After filtering: ${_availablePlayers.length} players available');

      if (_availablePlayers.isNotEmpty) {
        Player? playerToSelect;
        final lastSelectedPlayerId = await SettingsService.getLastSelectedPlayerId();

        _logger.log('⚙️ Current selection: ${_selectedPlayer?.name ?? 'none'}, lastSelected=$lastSelectedPlayerId, coldStart=$coldStart');

        // SIMPLIFIED PLAYER SELECTION LOGIC:
        // 1. User's manual selection is always respected
        // 2. On app reopen: restore last selection
        // 3. If selected player unavailable: switch to local player
        // 4. First launch (no history): select local player
        // 5. Local player unavailable: select first available

        // Keep currently selected player if still available
        if (_selectedPlayer != null && !coldStart) {
          // Check if selected player is still available - also check translated Cast/Sendspin IDs
          final selectedId = _selectedPlayer!.playerId;
          final translatedId = _castToSendspinIdMap[selectedId];
          String? reverseTranslatedId;
          for (final entry in _castToSendspinIdMap.entries) {
            if (entry.value == selectedId) {
              reverseTranslatedId = entry.key;
              break;
            }
          }

          final stillAvailable = _availablePlayers.any(
            (p) => p.available && (p.playerId == selectedId ||
                   (translatedId != null && p.playerId == translatedId) ||
                   (reverseTranslatedId != null && p.playerId == reverseTranslatedId)),
          );
          if (stillAvailable) {
            final currentPlayer = _availablePlayers.firstWhere(
              (p) => p.playerId == selectedId ||
                     (translatedId != null && p.playerId == translatedId) ||
                     (reverseTranslatedId != null && p.playerId == reverseTranslatedId),
            );
            playerToSelect = currentPlayer;
            if (currentPlayer.playerId != selectedId) {
              _logger.log('🔄 Selected player ID changed (Cast<->Sendspin): $selectedId -> ${currentPlayer.playerId}');
            } else {
              _logger.log('✓ Keeping current selection: ${currentPlayer.name}');
            }
          } else {
            // Selected player went offline - will fall through to local player
            _logger.log('⚠️ Selected player ${_selectedPlayer!.name} no longer available');
          }
        }

        // Priority 1: Restore last selected player (on coldStart)
        if (playerToSelect == null && coldStart && lastSelectedPlayerId != null) {
          playerToSelect = _availablePlayers.cast<Player?>().firstWhere(
            (p) => p!.playerId == lastSelectedPlayerId && p.available,
            orElse: () => null,
          );
          if (playerToSelect != null) {
            _logger.log('🔄 Restored last selected player: ${playerToSelect.name}');
          }
        }

        // Priority 2: Local player (default fallback)
        if (playerToSelect == null && builtinPlayerId != null) {
          try {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.playerId == builtinPlayerId && p.available,
            );
            _logger.log('📱 Selected local player: ${playerToSelect.name}');
          } catch (e) {
            _logger.log('⚠️ Local player not available');
          }
        }

        // Priority 3: First available player
        if (playerToSelect == null) {
          playerToSelect = _availablePlayers.firstWhere(
            (p) => p.available,
            orElse: () => _availablePlayers.first,
          );
          _logger.log('🔄 Fallback to first available player: ${playerToSelect.name}');
        }

        selectPlayer(playerToSelect);
      }

      // Preload track data and images in background for swipe gestures
      // Don't await - UI should show immediately with cached data
      unawaited(_preloadAdjacentPlayers(preloadAll: true));
    } catch (e) {
      ErrorHandler.logError('Load and select players', e);
    }
  }

  void selectPlayer(Player player, {bool skipNotify = false}) async {
    // Reentrancy guard - prevent concurrent selection which can cause race conditions
    if (_selectPlayerInProgress) {
      _logger.log('⚠️ selectPlayer already in progress, skipping for ${player.name}');
      return;
    }
    _selectPlayerInProgress = true;

    try {
      _selectedPlayer = player;

    // Cache for instant display on app resume
    _cacheService.setCachedSelectedPlayer(player);
    SettingsService.setLastSelectedPlayerId(player.playerId);

    // Immediately set currentTrack from cache to avoid flash during player switch
    // This ensures the UI shows the correct track info immediately, before
    // the async _updatePlayerState() completes.
    // IMPORTANT: Always set from cache, even if null - this prevents showing
    // stale track info when switching to a non-playing player.
    // For grouped child players, this returns the leader's track
    // NOTE: Always use cache even for external sources - the overlay shows cached
    // track info, so we should match that. The async _updatePlayerState() will
    // clear it if the player is truly playing external content.
    _currentTrack = getCachedTrackForPlayer(player.playerId);

    // Initialize position tracker for this player (skip for external sources)
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

    // Switch audio handler mode based on player type
    final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
    final isBuiltinPlayer = builtinPlayerId != null && player.playerId == builtinPlayerId;
    if (isBuiltinPlayer) {
      audioHandler.setLocalMode();
      // Update notification for builtin player using local mode method (keeps pause working)
      if (_currentTrack != null && (player.state == 'playing' || player.state == 'paused')) {
        final track = _currentTrack!;
        final artworkUrl = _api?.getImageUrl(track, size: 512);
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
        // Position comes from actual player in updateLocalModeNotification
        audioHandler.updateLocalModeNotification(
          item: mediaItem,
          playing: player.state == 'playing',
          duration: track.duration,
        );
      } else if (player.state == 'playing' || player.state == 'paused') {
        // Builtin player active but no cached track - show player name placeholder
        final mediaItem = audio_service.MediaItem(
          id: 'player_${player.playerId}',
          title: player.name,
          artist: 'Loading...',
        );
        audioHandler.updateLocalModeNotification(
          item: mediaItem,
          playing: player.state == 'playing',
        );
      } else {
        // Builtin player is idle - clear notification (fixes issue #42)
        audioHandler.clearRemotePlaybackState();
        _startIdleServiceTimer();
      }
    } else {
      // For remote players, immediately show notification if we have cached track info
      // and the player is playing (don't wait for polling to kick in)
      if (_currentTrack != null && (player.state == 'playing' || player.state == 'paused')) {
        final track = _currentTrack!;
        final artworkUrl = _api?.getImageUrl(track, size: 512);
        // Include player name in artist line: "Artist • Player Name"
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
        // Use position tracker for consistent position
        final position = _positionTracker.currentPosition;
        _cancelIdleServiceTimer();
        audioHandler.setRemotePlaybackState(
          item: mediaItem,
          playing: player.state == 'playing',
          position: position,
          duration: track.duration,
        );
      } else if (player.state == 'playing' || player.state == 'paused') {
        // Player is active but no cached track - show player name placeholder
        // This prevents stale notification from previous player
        final mediaItem = audio_service.MediaItem(
          id: 'player_${player.playerId}',
          title: player.name,
          artist: 'Loading...',
        );
        final position = _positionTracker.currentPosition;
        _cancelIdleServiceTimer();
        audioHandler.setRemotePlaybackState(
          item: mediaItem,
          playing: player.state == 'playing',
          position: position,
          duration: Duration.zero,
        );
      } else {
        // Player is idle - clear the notification to prevent stale metadata
        // from previous player showing (fixes issue #42)
        audioHandler.clearRemotePlaybackState();
        _startIdleServiceTimer();
      }
    }

    _startPlayerStatePolling();

    // Start notification position timer for remote players
    _manageNotificationPositionTimer();

    _preloadAdjacentPlayers();

    // Immediately fetch fresh track data from queue to avoid showing stale cache
    // This is important when resuming app after being in background - cached data
    // from player_updated events may have incomplete artist info
    await _updatePlayerState();

    if (!skipNotify) {
      notifyListeners();
    }
    } finally {
      _selectPlayerInProgress = false;
    }
  }

  /// Cycle to the next active player (for notification switch button)
  /// Only cycles through players that are currently playing or paused
  Future<void> selectNextPlayer() async {
    // If not connected yet (cold start), wait briefly for connection
    if (!isConnected) {
      _logger.log('🔄 Not connected yet, waiting for connection...');
      // Wait up to 3 seconds for connection to be established
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (isConnected) break;
      }
      if (!isConnected) {
        _logger.log('🔄 Still not connected, cannot switch player');
        return;
      }
    }

    // If players haven't loaded yet (cold start), try to load them first
    if (_availablePlayers.isEmpty && _api != null) {
      _logger.log('🔄 Players not loaded yet, loading...');
      await _loadAndSelectPlayers();
    }

    // Only include players that are available AND actively playing/paused
    // Always include the builtin player so user can switch to local device
    final activePlayers = _availablePlayers.where((p) =>
      p.available && (
        p.state == 'playing' ||
        p.state == 'paused' ||
        p.playerId.startsWith('ensemble_')  // Always include builtin player
      )
    ).toList();

    if (activePlayers.isEmpty) {
      _logger.log('🔄 No active players to switch to');
      return;
    }

    if (_selectedPlayer == null) {
      // If no player selected, select the first active one
      _logger.log('🔄 No player selected, selecting first active: ${activePlayers.first.name}');
      selectPlayer(activePlayers.first);
      return;
    }

    // Find current player in active list
    final currentIndex = activePlayers.indexWhere((p) => p.playerId == _selectedPlayer!.playerId);

    // Calculate next index - if current isn't in active list, start at 0
    final nextIndex = currentIndex == -1 ? 0 : (currentIndex + 1) % activePlayers.length;
    final nextPlayer = activePlayers[nextIndex];

    _logger.log('🔄 Switching to next active player: ${nextPlayer.name} (${nextIndex + 1}/${activePlayers.length})');
    selectPlayer(nextPlayer);
  }

  /// Manage notification position timer for remote players and Sendspin PCM.
  /// This timer updates the notification position every second using interpolated time,
  /// making the progress bar smooth instead of jumping every 5 seconds (polling interval).
  void _manageNotificationPositionTimer() {
    _notificationPositionTimer?.cancel();

    if (_selectedPlayer == null || _currentTrack == null) return;

    // Check if this is a builtin/local player
    final playerId = _selectedPlayer!.playerId;
    if (playerId.startsWith('ensemble_')) {
      // This is a local player ID, but we need to check if it's using Sendspin PCM
      // Sendspin PCM needs the timer because flutter_pcm_sound doesn't broadcast position
      // just_audio (non-Sendspin) handles position automatically via native events
      if (!_sendspinConnected || _pcmAudioPlayer == null) {
        // True local player using just_audio - no timer needed
        return;
      }
      // Sendspin PCM player - continue to start timer
      _logger.log('🔔 Starting notification timer for Sendspin PCM player');
    }

    // Only run timer if player is playing
    if (_selectedPlayer!.state != 'playing') return;

    _notificationPositionTimer = Timer.periodic(
      const Duration(milliseconds: 500), // 500ms for smoother progress
      (_) => _updateNotificationPosition(),
    );
  }

  /// Update just the notification position (called every 500ms for remote/Sendspin players)
  /// Set [forceUpdate] to true to update even when paused (used after seek)
  void _updateNotificationPosition({bool forceUpdate = false}) {
    if (_selectedPlayer == null || _currentTrack == null) {
      _notificationPositionTimer?.cancel();
      return;
    }

    final isPlaying = _selectedPlayer!.state == 'playing';

    // Don't update if player is not playing (unless forced for seek)
    if (!isPlaying && !forceUpdate) {
      _notificationPositionTimer?.cancel();
      return;
    }

    final track = _currentTrack!;

    // Always use position tracker for notification position - it's the single source of truth.
    // Previously used PCM elapsed time for Sendspin, but this breaks when:
    // 1. Stream starts mid-track (resume from pause) - PCM elapsed resets to 0
    // 2. Switching between multiple Sendspin players - PCM elapsed doesn't match
    final position = _positionTracker.currentPosition;

    // Check if track has ended (position reached duration)
    if (_positionTracker.hasReachedEnd) {
      _logger.log('PositionTracker: Track appears to have ended (position >= duration)');
      return;
    }

    final artworkUrl = _api?.getImageUrl(track, size: 512);
    final artistWithPlayer = track.artistsString.isNotEmpty
        ? '${track.artistsString} • ${_selectedPlayer!.name}'
        : _selectedPlayer!.name;
    final mediaItem = audio_service.MediaItem(
      id: track.uri ?? track.itemId,
      title: track.name,
      artist: artistWithPlayer,
      album: track.album?.name ?? '',
      duration: track.duration,
      artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
    );

    _cancelIdleServiceTimer();
    audioHandler.setRemotePlaybackState(
      item: mediaItem,
      playing: isPlaying,
      position: position,
      duration: track.duration,
    );
  }

  Future<void> _preloadAdjacentPlayers({bool preloadAll = false}) async {
    if (_api == null) return;

    final players = _availablePlayers.where((p) => p.available).toList();
    if (players.isEmpty) return;

    if (preloadAll) {
      _logger.log('🖼️ Preloading track info for all ${players.length} players...');
      await Future.wait(
        players.map((player) => _preloadPlayerTrack(player)),
      );
      _logger.log('🖼️ Preloading complete');
      return;
    }

    if (_selectedPlayer == null) return;
    if (players.length <= 1) return;

    final currentIndex = players.indexWhere((p) => p.playerId == _selectedPlayer!.playerId);
    if (currentIndex == -1) return;

    final prevIndex = currentIndex <= 0 ? players.length - 1 : currentIndex - 1;
    final nextIndex = currentIndex >= players.length - 1 ? 0 : currentIndex + 1;

    final playersToPreload = <Player>{};
    if (prevIndex != currentIndex) playersToPreload.add(players[prevIndex]);
    if (nextIndex != currentIndex) playersToPreload.add(players[nextIndex]);

    // Await all preloads so images are ready for next swipe
    await Future.wait(
      playersToPreload.map((player) => _preloadPlayerTrack(player)),
    );
  }

  Future<void> _preloadPlayerTrack(Player player) async {
    if (_api == null) return;

    try {
      // Log app_id and active_queue for playing players to help diagnose external source detection
      if (player.state == 'playing') {
        _logger.log('🔍 Preload ${player.name}: state=${player.state}, app_id=${player.appId}, active_queue=${player.activeQueue != null ? "set" : "null"}, isExternalSource=${player.isExternalSource}');
      } else {
        _logger.log('🔍 Preload ${player.name}: state=${player.state}, available=${player.available}');
      }

      // Skip external sources - they're not playing MA content
      if (player.isExternalSource) {
        _logger.log('🔍 Preload ${player.name}: SKIPPED - external source (app_id=${player.appId}, active_queue=${player.activeQueue != null ? "set" : "null"})');
        _cacheService.setCachedTrackForPlayer(player.playerId, null);
        return;
      }

      if (!player.available || !player.powered) {
        _logger.log('🔍 Preload ${player.name}: SKIPPED - not available or powered');
        _cacheService.setCachedTrackForPlayer(player.playerId, null);
        return;
      }

      final queue = await getQueue(player.playerId);
      _logger.log('🔍 Preload ${player.name}: queue=${queue != null}, currentItem=${queue?.currentItem != null}');

      if (queue != null && queue.currentItem != null) {
        final track = queue.currentItem!.track;

        final existingTrack = _cacheService.getCachedTrackForPlayer(player.playerId);
        final existingHasImage = existingTrack?.metadata?['images'] != null;
        final newHasImage = track.metadata?['images'] != null;

        if (existingHasImage && !newHasImage) {
          _logger.log('🔍 Preload ${player.name}: SKIPPED - keeping cached track with image');
        } else {
          _cacheService.setCachedTrackForPlayer(player.playerId, track);
          _logger.log('🔍 Preload ${player.name}: CACHED track "${track.name}"');

          // Dual-cache for Cast<->Sendspin players
          final sendspinId = _castToSendspinIdMap[player.playerId];
          if (sendspinId != null) {
            _cacheService.setCachedTrackForPlayer(sendspinId, track);
          } else if (player.provider == 'chromecast' && player.playerId.length >= 8) {
            final computedSendspinId = 'cast-${player.playerId.substring(0, 8)}';
            _cacheService.setCachedTrackForPlayer(computedSendspinId, track);
          }

          // Also precache the image so it's ready for swipe preview
          final imageUrl = getImageUrl(track, size: 512);
          if (imageUrl != null) {
            _precacheImage(imageUrl);
          }
        }
      } else {
        _logger.log('🔍 Preload ${player.name}: NO TRACK - queue empty');
        final existingTrack = _cacheService.getCachedTrackForPlayer(player.playerId);
        if (existingTrack?.metadata?['images'] == null) {
          _cacheService.setCachedTrackForPlayer(player.playerId, null);
        }
      }
    } catch (e) {
      _logger.log('Error preloading player track for ${player.name}: $e');
    }
  }

  /// Precache an image URL so it loads instantly when displayed
  Future<void> _precacheImage(String url) async {
    try {
      final imageProvider = CachedNetworkImageProvider(url);
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      final completer = Completer<void>();
      late ImageStreamListener listener;

      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (!completer.isCompleted) completer.complete();
          imageStream.removeListener(listener);
        },
        onError: (exception, stackTrace) {
          if (!completer.isCompleted) completer.completeError(exception);
          imageStream.removeListener(listener);
        },
      );

      imageStream.addListener(listener);
      await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
        imageStream.removeListener(listener);
      });
    } catch (e) {
      // Silently ignore precache errors - image will load on demand
    }
  }

  Future<void> preloadAllPlayerTracks() async {
    if (_api == null) return;

    final players = _availablePlayers.where((p) => p.available).toList();

    await Future.wait(
      players.map((player) => _preloadPlayerTrack(player)),
    );

    // After preloading, update _currentTrack from cache if it has better data
    // This fixes the issue where mini player shows wrong info but device list is correct
    // For grouped child players, this gets the leader's track
    if (_selectedPlayer != null && _currentTrack != null) {
      final cachedTrack = getCachedTrackForPlayer(_selectedPlayer!.playerId);
      if (cachedTrack != null && cachedTrack.uri == _currentTrack!.uri) {
        final cachedHasImage = cachedTrack.metadata?['images'] != null;
        final currentHasImage = _currentTrack!.metadata?['images'] != null;
        final cachedHasArtist = cachedTrack.artistsString.isNotEmpty &&
            cachedTrack.artistsString != 'Unknown Artist';
        final currentHasArtist = _currentTrack!.artistsString.isNotEmpty &&
            _currentTrack!.artistsString != 'Unknown Artist';

        if ((cachedHasImage && !currentHasImage) || (cachedHasArtist && !currentHasArtist)) {
          _currentTrack = cachedTrack;
          _logger.log('🎵 Updated currentTrack from cache with better metadata');
          notifyListeners();
        }
      }
    }
  }

  void _startPlayerStatePolling() {
    _playerStateTimer?.cancel();

    if (_selectedPlayer == null) return;

    _playerStateTimer = Timer.periodic(Timings.playerPollingInterval, (_) async {
      try {
        await _updatePlayerState();
      } catch (e) {
        _logger.log('Error updating player state (will retry): $e');
      }
    });

    _updatePlayerState();
  }

  /// Start the idle service timer - stops foreground service after 30 min of no playback
  /// Called when playback stops (player state becomes idle)
  void _startIdleServiceTimer() {
    _idleServiceTimer?.cancel();
    _logger.log('⏱️ Starting idle service timer (${_idleServiceTimeout.inMinutes} min)');
    _idleServiceTimer = Timer(_idleServiceTimeout, () {
      _logger.log('⏱️ Idle service timeout reached - stopping foreground service');
      audioHandler.stopService();
    });
  }

  /// Cancel the idle service timer - called when playback starts
  void _cancelIdleServiceTimer() {
    if (_idleServiceTimer?.isActive == true) {
      _logger.log('⏱️ Cancelling idle service timer (playback resumed)');
      _idleServiceTimer?.cancel();
      _idleServiceTimer = null;
    }
  }

  /// Apply volume protection for the selected player.
  /// Injects effective volume for group players (whose API volume is null)
  /// and protects optimistic volume updates from stale API data.
  void _applyVolumeProtection(Player updatedPlayer, List<Player> allPlayers) {
    if (_groupVolumeManager.isGroupPlayer(updatedPlayer)) {
      final effectiveVolume = _groupVolumeManager.getEffectiveVolumeLevel(
          updatedPlayer, allPlayers);
      if (effectiveVolume != null) {
        _selectedPlayer = _selectedPlayer!.copyWith(volumeLevel: effectiveVolume);
      }
    }

    final pendingVol = _pendingVolumes[updatedPlayer.playerId];
    final pendingTs = _pendingVolumeTimestamps[updatedPlayer.playerId];
    if (pendingVol != null && pendingTs != null) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - pendingTs;
      final isGroup = _groupVolumeManager.isGroupPlayer(updatedPlayer);
      final timeoutMs = isGroup ? _pendingVolumeTimeoutGroupMs : _pendingVolumeTimeoutMs;
      if (elapsed >= timeoutMs) {
        _pendingVolumes.remove(updatedPlayer.playerId);
        _pendingVolumeTimestamps.remove(updatedPlayer.playerId);
      } else {
        final currentEffective = _selectedPlayer?.volumeLevel;
        if (currentEffective != null &&
            (currentEffective - pendingVol).abs() <= _pendingVolumeTolerancePoints) {
          _pendingVolumes.remove(updatedPlayer.playerId);
          _pendingVolumeTimestamps.remove(updatedPlayer.playerId);
        } else {
          _selectedPlayer = _selectedPlayer!.copyWith(volumeLevel: pendingVol);
        }
      }
    }
  }

  Future<void> _updatePlayerState() async {
    if (_selectedPlayer == null || _api == null) return;

    // Capture player ID at start to detect stale operations
    // If player changes during async operations, we should abort
    final operationPlayerId = _selectedPlayer!.playerId;

    try {
      bool stateChanged = false;

      // Get fresh player data - but look up from _availablePlayers which has
      // the processed names (Sendspin suffix removed) and correct filtering
      // Also check translated Cast<->Sendspin IDs
      final selectedId = _selectedPlayer!.playerId;
      final translatedSendspinId = _castToSendspinIdMap[selectedId];
      String? translatedCastId;
      for (final entry in _castToSendspinIdMap.entries) {
        if (entry.value == selectedId) {
          translatedCastId = entry.key;
          break;
        }
      }

      // Try to refresh from API first for latest state
      final allPlayers = await getPlayers();

      // Check for stale operation - player may have changed during async call
      if (_selectedPlayer?.playerId != operationPlayerId) {
        _logger.log('⚠️ _updatePlayerState: Player changed during operation, aborting');
        return;
      }

      // Update _availablePlayers with fresh volume/state data from API.
      // This is critical for group volume computation: member players don't get
      // individual _updatePlayerState() calls, so their volumes in _availablePlayers
      // would go stale. Without this, after the pending timeout expires, the
      // computed group average uses old member volumes and snaps back to 0.
      for (final freshPlayer in allPlayers) {
        final idx = _availablePlayers.indexWhere(
            (p) => p.playerId == freshPlayer.playerId);
        if (idx != -1) {
          _availablePlayers[idx] = _availablePlayers[idx].copyWith(
            volumeLevel: freshPlayer.volumeLevel,
            state: freshPlayer.state,
            powered: freshPlayer.powered,
            available: freshPlayer.available,
          );
        }
      }

      Player? rawPlayer = allPlayers.firstWhere(
        (p) => p.playerId == selectedId ||
               (translatedSendspinId != null && p.playerId == translatedSendspinId) ||
               (translatedCastId != null && p.playerId == translatedCastId),
        orElse: () => _selectedPlayer!,
      );

      // Now get the processed version from _availablePlayers to preserve renamed name
      // But update with latest state (volume, playing state, etc.) from rawPlayer
      final processedPlayer = _availablePlayers.firstWhere(
        (p) => p.playerId == selectedId ||
               (translatedSendspinId != null && p.playerId == translatedSendspinId) ||
               (translatedCastId != null && p.playerId == translatedCastId),
        orElse: () => rawPlayer,
      );

      // Use the processed player's name but raw player's state
      final updatedPlayer = processedPlayer.copyWith(
        state: rawPlayer.state,
        volumeLevel: rawPlayer.volumeLevel,
        volumeMuted: rawPlayer.volumeMuted,
        elapsedTime: rawPlayer.elapsedTime,
        elapsedTimeLastUpdated: rawPlayer.elapsedTimeLastUpdated,
        powered: rawPlayer.powered,
        available: rawPlayer.available,
        groupMembers: rawPlayer.groupMembers,
        syncedTo: rawPlayer.syncedTo,
        currentItemId: rawPlayer.currentItemId,
        isExternalSource: rawPlayer.isExternalSource,
        appId: rawPlayer.appId,
        activeQueue: rawPlayer.activeQueue,
      );

      _selectedPlayer = updatedPlayer;

      _applyVolumeProtection(updatedPlayer, allPlayers);

      stateChanged = true;

      // Handle external sources (Spotify Connect, TV optical, etc.)
      // These players are "playing" from MA's perspective but not MA content
      if (updatedPlayer.isExternalSource) {
        if (_currentTrack != null) {
          _currentTrack = null;
          _cacheService.setCachedTrackForPlayer(updatedPlayer.playerId, null);
          stateChanged = true;
          _persistPlaybackState();
        }
        if (_currentAudiobook != null) {
          _logger.log('📚 External source active, clearing audiobook context');
          _currentAudiobook = null;
          stateChanged = true;
        }
        if (_currentPodcastName != null) {
          _logger.log('🎙️ External source active, clearing podcast context');
          _currentPodcastName = null;
          stateChanged = true;
        }
        // Clear notification for external source
        audioHandler.clearRemotePlaybackState();
        _startIdleServiceTimer();
        if (stateChanged) {
          notifyListeners();
        }
        return;
      }

      // Feed position tracker with server data
      // Log raw values to debug position issues
      final rawElapsedTime = updatedPlayer.elapsedTime;
      final rawTimestamp = updatedPlayer.elapsedTimeLastUpdated;
      if (rawElapsedTime == null) {
        _logger.log('⚠️ Player ${updatedPlayer.name} has null elapsedTime');
      }

      _positionTracker.updateFromServer(
        playerId: updatedPlayer.playerId,
        position: rawElapsedTime ?? 0.0,
        isPlaying: updatedPlayer.state == 'playing',
        duration: _currentTrack?.duration,
        serverTimestamp: rawTimestamp,
      );

      final isPlayingOrPaused = _selectedPlayer!.state == 'playing' || _selectedPlayer!.state == 'paused';
      final isIdleWithContent = _selectedPlayer!.state == 'idle' && _selectedPlayer!.powered;
      final shouldShowTrack = _selectedPlayer!.available && (isPlayingOrPaused || isIdleWithContent);

      if (!shouldShowTrack) {
        if (_currentTrack != null) {
          _currentTrack = null;
          stateChanged = true;
          // Persist cleared track state
          _persistPlaybackState();
        }
        // Clear audiobook context when playback stops
        if (_currentAudiobook != null) {
          _logger.log('📚 Playback stopped, clearing audiobook context');
          _currentAudiobook = null;
          stateChanged = true;
        }
        // Clear podcast context when playback stops
        if (_currentPodcastName != null) {
          _logger.log('🎙️ Playback stopped, clearing podcast context');
          _currentPodcastName = null;
          stateChanged = true;
        }

        if (stateChanged) {
          notifyListeners();
        }
        return;
      }

      final queue = await getQueue(_selectedPlayer!.playerId);

      // Check for stale operation - player may have changed during async call
      if (_selectedPlayer?.playerId != operationPlayerId) {
        _logger.log('⚠️ _updatePlayerState: Player changed during getQueue, aborting');
        return;
      }

      if (queue != null && queue.currentItem != null) {
        final queueTrack = queue.currentItem!.track;
        final trackChanged = _currentTrack == null ||
            _currentTrack!.uri != queueTrack.uri ||
            _currentTrack!.name != queueTrack.name;

        if (trackChanged) {
          // Check "end of track" sleep timer - previous track just ended
          if (_currentTrack != null) {
            checkEndOfTrackSleepTimer();
          }

          // Check if cached track has better metadata (images, proper artist info)
          // This prevents losing album art and artist data when resuming the app
          // For grouped child players, this gets the leader's cached track
          final cachedTrack = getCachedTrackForPlayer(_selectedPlayer!.playerId);
          final cachedHasImage = cachedTrack?.metadata?['images'] != null;
          final queueHasImage = queueTrack.metadata?['images'] != null;
          // Also check for malformed artist names (e.g., "Artist - Title" format in name)
          final cachedHasProperArtist = cachedTrack?.artistsString.isNotEmpty == true &&
              cachedTrack?.artistsString != 'Unknown Artist' &&
              !cachedTrack!.name.contains(' - '); // Proper track doesn't have artist in name
          final queueHasProperArtist = queueTrack.artistsString.isNotEmpty &&
              queueTrack.artistsString != 'Unknown Artist' &&
              !queueTrack.name.contains(' - ');

          // Also check if _currentTrack (set from cache in selectPlayer) has good data
          final currentHasImage = _currentTrack?.metadata?['images'] != null;
          final currentHasProperArtist = _currentTrack?.artistsString.isNotEmpty == true &&
              _currentTrack?.artistsString != 'Unknown Artist' &&
              !(_currentTrack?.name.contains(' - ') ?? false);

          // Match by URI - name might differ if queue has malformed data
          final isSameTrackAsCached = cachedTrack?.uri == queueTrack.uri;
          final cachedHasBetterData = (cachedHasImage && !queueHasImage) ||
              (cachedHasProperArtist && !queueHasProperArtist);

          // Queue track has bad metadata if it lacks image AND lacks proper artist
          final queueHasBadMetadata = !queueHasImage && !queueHasProperArtist;
          // Current track (from cache at selectPlayer) has good metadata
          final currentHasGoodMetadata = currentHasImage || currentHasProperArtist;

          if (isSameTrackAsCached && cachedHasBetterData) {
            // Use cached track which has better metadata
            _currentTrack = cachedTrack;
            _logger.log('🎵 Using cached track with better metadata for ${cachedTrack!.name}');
          } else if (queueHasBadMetadata && currentHasGoodMetadata) {
            // Queue has bad data, but _currentTrack (set from cache) is good - keep it
            _logger.log('🎵 Keeping currentTrack - queue has bad metadata but current is good');
            // Don't change _currentTrack, keep the good data
          } else {
            _currentTrack = queueTrack;
            // Update cache if queue track has good metadata
            if (queueHasImage || queueHasProperArtist) {
              _cacheService.setCachedTrackForPlayer(_selectedPlayer!.playerId, queueTrack);

              // Dual-cache for Cast<->Sendspin players
              final sendspinId = _castToSendspinIdMap[_selectedPlayer!.playerId];
              if (sendspinId != null) {
                _cacheService.setCachedTrackForPlayer(sendspinId, queueTrack);
              } else if (_selectedPlayer!.provider == 'chromecast' && _selectedPlayer!.playerId.length >= 8) {
                final computedSendspinId = 'cast-${_selectedPlayer!.playerId.substring(0, 8)}';
                _cacheService.setCachedTrackForPlayer(computedSendspinId, queueTrack);
              }
            }
          }
          stateChanged = true;

          // Persist the updated playback state to database for instant restore on next launch
          _persistPlaybackState();

          // Clear audiobook context if switched to a different media item
          // Check if the new track is from the same audiobook (by comparing URIs)
          if (_currentAudiobook != null) {
            final currentUri = _currentTrack!.uri ?? '';
            final audiobookUri = _currentAudiobook!.uri ?? 'library://audiobook/${_currentAudiobook!.itemId}';
            // The audiobook chapter URIs should contain the audiobook URI pattern
            if (!currentUri.contains(_currentAudiobook!.itemId) &&
                !currentUri.contains(audiobookUri)) {
              _logger.log('📚 Track changed to non-audiobook, clearing context');
              _currentAudiobook = null;
            }
          }
        }

        // Update notification for ALL players
        final track = _currentTrack!;
        final artworkUrl = _api?.getImageUrl(track, size: 512);
        final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
        final isBuiltinPlayer = builtinPlayerId != null && _selectedPlayer!.playerId == builtinPlayerId;

        if (isBuiltinPlayer) {
          // Local playback - use local mode notification (keeps pause working)
          final artistWithPlayer = track.artistsString.isNotEmpty
              ? '${track.artistsString} • ${_selectedPlayer!.name}'
              : _selectedPlayer!.name;
          final mediaItem = audio_service.MediaItem(
            id: track.uri ?? track.itemId,
            title: track.name,
            artist: artistWithPlayer,
            album: track.album?.name ?? '',
            duration: track.duration,
            artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
          );
          // Position comes from actual player in updateLocalModeNotification
          audioHandler.updateLocalModeNotification(
            item: mediaItem,
            playing: _selectedPlayer!.state == 'playing',
            duration: track.duration,
          );
        } else {
          // Remote MA player - show notification via remote mode
          // Include player name in artist line: "Artist • Player Name"
          final artistWithPlayer = track.artistsString.isNotEmpty
              ? '${track.artistsString} • ${_selectedPlayer!.name}'
              : _selectedPlayer!.name;
          final mediaItem = audio_service.MediaItem(
            id: track.uri ?? track.itemId,
            title: track.name,
            artist: artistWithPlayer,
            album: track.album?.name ?? '',
            duration: track.duration,
            artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
          );
          // Use position tracker for consistent position (single source of truth)
          final position = _positionTracker.currentPosition;
          _cancelIdleServiceTimer();
          audioHandler.setRemotePlaybackState(
            item: mediaItem,
            playing: _selectedPlayer!.state == 'playing',
            position: position,
            duration: track.duration,
          );
        }
      } else {
        // No queue data available from API
        final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
        final isBuiltinPlayer = builtinPlayerId != null && _selectedPlayer!.playerId == builtinPlayerId;

        // For builtin player, try to preserve cached track data since queue API doesn't return it
        // The cached track was set in selectPlayer() and contains valid data
        if (isBuiltinPlayer && _currentTrack == null) {
          final cachedTrack = getCachedTrackForPlayer(_selectedPlayer!.playerId);
          if (cachedTrack != null) {
            _currentTrack = cachedTrack;
            stateChanged = true;
            _logger.log('🎵 Restored cached track for builtin player: ${cachedTrack.name}');
          }
        }

        // Only clear track if we have no cached data to fall back on
        // Don't clear for builtin player - it maintains its own playback state
        if (_currentTrack != null && !isBuiltinPlayer) {
          _currentTrack = null;
          stateChanged = true;
          // Persist cleared track state
          _persistPlaybackState();
        }

        // Show player name placeholder only if we have no track data
        if (_currentTrack == null && (_selectedPlayer!.state == 'playing' || _selectedPlayer!.state == 'paused')) {
          final mediaItem = audio_service.MediaItem(
            id: 'player_${_selectedPlayer!.playerId}',
            title: _selectedPlayer!.name,
            artist: 'No track info',
          );
          if (isBuiltinPlayer) {
            // Position comes from actual player in updateLocalModeNotification
            audioHandler.updateLocalModeNotification(
              item: mediaItem,
              playing: _selectedPlayer!.state == 'playing',
            );
          } else {
            final position = _positionTracker.currentPosition;
            _cancelIdleServiceTimer();
            audioHandler.setRemotePlaybackState(
              item: mediaItem,
              playing: _selectedPlayer!.state == 'playing',
              position: position,
              duration: Duration.zero,
            );
          }
        } else if (_currentTrack != null && isBuiltinPlayer) {
          // Builtin player has track data - update notification with it
          final track = _currentTrack!;
          final mediaItem = audio_service.MediaItem(
            id: track.uri ?? track.itemId,
            title: track.name,
            artist: track.artistsString,
            album: track.album?.name,
            artUri: _api != null ? Uri.tryParse(_api!.getImageUrl(track, size: 512) ?? '') : null,
            duration: track.duration,
          );
          audioHandler.updateLocalModeNotification(
            item: mediaItem,
            playing: _selectedPlayer!.state == 'playing',
          );
        } else if (_selectedPlayer!.state != 'playing' && _selectedPlayer!.state != 'paused') {
          audioHandler.clearRemotePlaybackState();
          _startIdleServiceTimer();
          _positionTracker.clear();
        }
      }

      // Manage notification position timer based on current player state
      _manageNotificationPositionTimer();

      if (stateChanged) {
        notifyListeners();
      }
    } catch (e) {
      _logger.log('❌ Error updating player state: $e');
    }
  }

  Future<void> playPauseSelectedPlayer() async {
    if (_selectedPlayer == null) return;

    final wasPlaying = _selectedPlayer!.isPlaying;

    if (wasPlaying) {
      await pausePlayer(_selectedPlayer!.playerId);
      // For pause: Don't refresh - we already did optimistic UI update
      // The player_updated event from MA will handle final state sync
    } else {
      await resumePlayer(_selectedPlayer!.playerId);
      // For resume: Refresh in background to get updated track info
      unawaited(refreshPlayers());
    }
  }

  Future<void> nextTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await nextTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await _updatePlayerState();
  }

  Future<void> previousTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await previousTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await _updatePlayerState();
  }

  Future<void> refreshPlayers() async {
    final previousState = _selectedPlayer?.state;
    final previousVolume = _selectedPlayer?.volumeLevel;

    await _loadAndSelectPlayers(forceRefresh: true);

    bool stateChanged = false;
    if (_selectedPlayer != null && _availablePlayers.isNotEmpty) {
      try {
        final updatedPlayer = _availablePlayers.firstWhere(
          (p) => p.playerId == _selectedPlayer!.playerId,
        );

        if (updatedPlayer.state != previousState ||
            updatedPlayer.volumeLevel != previousVolume) {
          stateChanged = true;
        }

        _selectedPlayer = updatedPlayer;

        _applyVolumeProtection(updatedPlayer, _availablePlayers);
      } catch (e) {
        stateChanged = true;
      }
    }

    if (stateChanged) {
      notifyListeners();
    }
  }

  // ============================================================================
  // LIBRARY DATA
  // ============================================================================

  Future<void> loadLibrary() async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;

      // Load from database cache first (instant)
      final syncService = SyncService.instance;
      if (syncService.hasCache) {
        _albums = syncService.cachedAlbums;
        _artists = syncService.cachedArtists;
        _logger.log('📦 Loaded ${_albums.length} albums, ${_artists.length} artists from cache');
        _syncLibraryStatusToService();
        notifyListeners();
      }

      // Fetch tracks from API (not cached - too many items)
      if (_api != null) {
        try {
          _tracks = await _api!.getTracks(
            limit: LibraryConstants.maxLibraryItems,
            providerInstanceIds: providerIdsForApiCalls,
          );
          _logger.log('📥 Fetched ${_tracks.length} tracks from MA');
        } catch (e) {
          _logger.log('⚠️ Failed to fetch tracks: $e');
        }
      }

      _isLoading = false;
      _syncLibraryStatusToService();
      notifyListeners();

      // Trigger background sync (non-blocking)
      if (_api != null) {
        _syncLibraryInBackground();
      }
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load library');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sync library data in background without blocking UI
  Future<void> _syncLibraryInBackground() async {
    if (_api == null) return;

    final syncService = SyncService.instance;

    // Listen for sync completion to update our lists
    void onSyncComplete() {
      if (syncService.status == SyncStatus.completed) {
        _albums = syncService.cachedAlbums;
        _artists = syncService.cachedArtists;
        _logger.log('🔄 Updated library from background sync: ${_albums.length} albums, ${_artists.length} artists');
        _syncLibraryStatusToService();
        notifyListeners();
      }
      syncService.removeListener(onSyncComplete);
    }

    syncService.addListener(onSyncComplete);
    await syncService.syncFromApi(_api!, providerInstanceIds: providerIdsForApiCalls);
  }

  /// Load radio stations from the library
  Future<void> loadRadioStations({String? orderBy}) async {
    if (!isConnected || _api == null) return;

    try {
      _isLoadingRadio = true;
      notifyListeners();

      _radioStations = await _api!.getRadioStations(limit: 100, orderBy: orderBy);
      _isLoadingRadio = false;
      notifyListeners();
    } catch (e) {
      _logger.log('⚠️ Failed to load radio stations: $e');
      _isLoadingRadio = false;
      notifyListeners();
    }
  }

  Future<void> loadPodcasts({String? orderBy}) async {
    if (!isConnected || _api == null) return;

    try {
      _isLoadingPodcasts = true;
      notifyListeners();

      _podcasts = await _api!.getPodcasts(limit: 100, orderBy: orderBy);

      _logger.log('🎙️ Loaded ${_podcasts.length} podcasts');
      _isLoadingPodcasts = false;
      notifyListeners();

      // Fetch episode covers in background for podcasts with low-res images
      _loadPodcastCoversInBackground();
    } catch (e) {
      _logger.log('⚠️ Failed to load podcasts: $e');
      _isLoadingPodcasts = false;
      notifyListeners();
    }
  }

  /// Load high-resolution podcast covers from iTunes in background
  /// iTunes provides 800x800 artwork for most podcasts (reduced from 1400 for efficiency)
  Future<void> _loadPodcastCoversInBackground() async {
    if (_api == null) return;

    for (final podcast in _podcasts) {
      try {
        // Skip if already cached (either in memory or loaded from persistence)
        if (_podcastCoverCache.containsKey(podcast.itemId)) continue;

        // Try iTunes for high-res artwork
        final itunesArtwork = await _api!.getITunesPodcastArtwork(podcast.name);

        if (itunesArtwork != null) {
          _podcastCoverCache[podcast.itemId] = itunesArtwork;
          _logger.log('🎙️ Cached iTunes artwork for ${podcast.name}');

          // Persist to storage for instant display on next launch
          SettingsService.addPodcastCoverToCache(podcast.itemId, itunesArtwork);

          notifyListeners();
        }
      } catch (e) {
        _logger.log('⚠️ Failed to load cover for ${podcast.name}: $e');
      }
    }
  }

  Future<void> loadArtists({int? limit, int? offset, String? search, String? orderBy}) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _artists = await _api!.getArtists(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
        albumArtistsOnly: false, // Show ALL library artists, not just those with albums
        orderBy: orderBy,
      );

      // Update SyncService cache with sorted data so UI sees the new order
      SyncService.instance.updateCachedArtists(_artists);

      _isLoading = false;
      _syncLibraryStatusToService();
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
    String? orderBy,
  }) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _albums = await _api!.getAlbums(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
        artistId: artistId,
        orderBy: orderBy,
      );

      // Update SyncService cache with sorted data so UI sees the new order
      SyncService.instance.updateCachedAlbums(_albums);

      _isLoading = false;
      _syncLibraryStatusToService();
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
      final results = await _api!.search(query, libraryOnly: libraryOnly);
      return results;
    } catch (e) {
      ErrorHandler.logError('Search', e);
      return {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  /// Get playlists with provider filtering applied
  Future<List<Playlist>> getPlaylists({int? limit, bool? favoriteOnly, String? orderBy}) async {
    if (_api == null) return [];
    try {
      final playlists = await _api!.getPlaylists(limit: limit, favoriteOnly: favoriteOnly, orderBy: orderBy);
      return filterByProvider(playlists);
    } catch (e) {
      _logger.log('❌ Failed to fetch playlists: $e');
      return [];
    }
  }

  /// Get audiobooks with provider filtering applied
  Future<List<Audiobook>> getAudiobooks({int? limit, bool? favoriteOnly}) async {
    if (_api == null) return [];
    try {
      final audiobooks = await _api!.getAudiobooks(limit: limit, favoriteOnly: favoriteOnly ?? false);
      return filterByProvider(audiobooks);
    } catch (e) {
      _logger.log('❌ Failed to fetch audiobooks: $e');
      return [];
    }
  }

  String getStreamUrl(String provider, String itemId, {String? uri, List<ProviderMapping>? providerMappings}) {
    return _api?.getStreamUrl(provider, itemId, uri: uri, providerMappings: providerMappings) ?? '';
  }

  String? getImageUrl(MediaItem item, {int size = 256}) {
    return _api?.getImageUrl(item, size: size);
  }

  /// Get best available podcast cover URL
  /// Returns cached iTunes URL (800x800) if available, otherwise falls back to MA imageproxy
  /// The cache is persisted to storage and loaded on app start for instant high-res display
  String? getPodcastImageUrl(MediaItem podcast, {int size = 256}) {
    // Return cached iTunes URL if available (persisted across app launches)
    final cachedUrl = _podcastCoverCache[podcast.itemId];
    if (cachedUrl != null) {
      return cachedUrl;
    }
    // Fall back to MA imageproxy (will be replaced once iTunes fetch completes)
    return _api?.getImageUrl(podcast, size: size);
  }

  /// Get artist image URL with fallback to external sources (Deezer, Fanart.tv)
  /// Returns a Future since fallback requires async API calls
  Future<String?> getArtistImageUrlWithFallback(Artist artist, {int size = 256}) async {
    // Try Music Assistant first
    final maUrl = _api?.getImageUrl(artist, size: size);
    if (maUrl != null) {
      return maUrl;
    }

    // Fall back to external sources (Deezer, Fanart.tv, etc.)
    return MetadataService.getArtistImageUrl(artist.name);
  }

  // ============================================================================
  // PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  Future<List<Player>> getPlayers() async {
    return await _api?.getPlayers() ?? [];
  }

  Future<PlayerQueue?> getQueue(String playerId) async {
    // If this player is a group child, fetch the leader's queue instead
    // This ensures grouped players show the same queue as their leader
    String effectivePlayerId = playerId;
    final player = _availablePlayers.firstWhere(
      (p) => p.playerId == playerId,
      orElse: () => Player(
        playerId: playerId,
        name: '',
        available: false,
        powered: false,
        state: 'idle',
      ),
    );

    if (player.isGroupChild && player.syncedTo != null) {
      _logger.log('🔗 Player $playerId is grouped, fetching leader queue: ${player.syncedTo}');
      effectivePlayerId = player.syncedTo!;
    }

    // Translate Sendspin ID to Cast UUID for queue fetch
    // MA stores queues under the Cast UUID, not the Sendspin ID
    if (effectivePlayerId.startsWith('cast-') && effectivePlayerId.length >= 13) {
      // Sendspin ID format: cast-7df484e3 -> need Cast UUID starting with 7df484e3
      final prefix = effectivePlayerId.substring(5); // Remove "cast-"
      // Reverse lookup in the map
      for (final entry in _castToSendspinIdMap.entries) {
        if (entry.value == effectivePlayerId) {
          _logger.log('🔗 Translated Sendspin ID $effectivePlayerId to Cast UUID ${entry.key} for queue fetch');
          effectivePlayerId = entry.key;
          break;
        }
      }
      // If not in map, try to find in available players
      if (effectivePlayerId.startsWith('cast-')) {
        for (final p in _availablePlayers) {
          if (p.provider == 'chromecast' && p.playerId.startsWith(prefix)) {
            _logger.log('🔗 Found Cast UUID ${p.playerId} for Sendspin ID $effectivePlayerId via player lookup');
            effectivePlayerId = p.playerId;
            break;
          }
        }
      }
    }

    final queue = await _api?.getQueue(effectivePlayerId);

    // Persist queue to database for instant display on app resume
    if (queue != null) {
      _persistQueueToDatabase(playerId, queue);
    }

    return queue;
  }

  /// Get cached queue for instant display (before API refresh)
  Future<PlayerQueue?> getCachedQueue(String playerId) async {
    try {
      if (!DatabaseService.instance.isInitialized) return null;

      final cachedItems = await DatabaseService.instance.getCachedQueue(playerId);
      if (cachedItems.isEmpty) return null;

      final items = <QueueItem>[];
      for (final cached in cachedItems) {
        try {
          final itemData = jsonDecode(cached.itemJson) as Map<String, dynamic>;
          items.add(QueueItem.fromJson(itemData));
        } catch (e) {
          _logger.log('⚠️ Error parsing cached queue item: $e');
        }
      }

      if (items.isEmpty) return null;

      return PlayerQueue(
        playerId: playerId,
        items: items,
        currentIndex: 0, // Will be updated from fresh data
      );
    } catch (e) {
      _logger.log('⚠️ Error loading cached queue: $e');
      return null;
    }
  }

  /// Persist queue to database for app restart persistence
  void _persistQueueToDatabase(String playerId, PlayerQueue queue) {
    () async {
      try {
        if (!DatabaseService.instance.isInitialized) return;

        final itemJsonList = queue.items.map((item) => jsonEncode(item.toJson())).toList();
        await DatabaseService.instance.saveQueue(playerId, itemJsonList);
        _logger.log('💾 Persisted ${queue.items.length} queue items to database');
      } catch (e) {
        _logger.log('⚠️ Error persisting queue to database: $e');
      }
    }();
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

  Future<void> addTrackToQueue(String playerId, Track track) async {
    try {
      await _api?.addTrackToQueue(playerId, track);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Add to queue');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Add to queue', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addTracksToQueue(String playerId, List<Track> tracks, {int startIndex = 0}) async {
    try {
      await _api?.addTracksToQueue(playerId, tracks, startIndex: startIndex);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Add tracks to queue');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Add tracks to queue', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex, bool clearQueue = true}) async {
    try {
      await _api?.playTracks(playerId, tracks, startIndex: startIndex, clearQueue: clearQueue);

      final trackIndex = startIndex ?? 0;
      if (tracks.isNotEmpty && trackIndex < tracks.length) {
        _currentTrack = tracks[trackIndex];
        notifyListeners();
      }
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

  Future<void> playArtistRadio(String playerId, Artist artist) async {
    try {
      await _api?.playArtistRadio(playerId, artist);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play artist radio');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play artist radio', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<String?> getCurrentStreamUrl(String playerId) async {
    return await _api?.getCurrentStreamUrl(playerId);
  }

  Future<void> pausePlayer(String playerId) async {
    try {
      // Get builtin player ID - this is cached so should be fast
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();

      if (builtinPlayerId != null && playerId == builtinPlayerId && _sendspinConnected) {
        _logger.log('⏸️ Non-blocking local pause for builtin player');

        // CRITICAL: Don't await these - they can block the UI thread
        // Use unawaited to make them fire-and-forget, but log errors
        unawaited((_pcmAudioPlayer?.pause() ?? Future.value()).catchError(
          (e) => _logger.log('⚠️ PCM pause error (non-blocking): $e'),
        ));

        // Don't pause just_audio for Sendspin mode - it's not being used for audio output
        // and calling pause() on it can cause blocking issues
        // unawaited(_localPlayer.pause());

        // Report state to MA immediately (fire and forget)
        _sendspinService?.reportState(playing: false, paused: true);

        // Update local player state optimistically for UI responsiveness
        if (_selectedPlayer != null) {
          _selectedPlayer = _selectedPlayer!.copyWith(state: 'paused');
          notifyListeners();
        }
      }

      // Send command to MA for proper state sync - don't await, but log errors
      unawaited((_api?.pausePlayer(playerId) ?? Future.value()).catchError(
        (e) => _logger.log('⚠️ MA pause command error (non-blocking): $e'),
      ));
    } catch (e) {
      ErrorHandler.logError('Pause player', e);
      // Don't rethrow - we want pause to be resilient
    }
  }

  Future<void> resumePlayer(String playerId) async {
    try {
      // For resume, we let MA handle it since it needs to restart the stream
      // The stream_start event will trigger local playback
      await _api?.resumePlayer(playerId);
    } catch (e) {
      // Check if this is a "No playable item" error - means server queue is empty
      final errorStr = e.toString();
      if (errorStr.contains('No playable item')) {
        _logger.log('⚠️ Server queue empty - attempting to restore from cached queue...');

        // Try to restore queue from cached data
        final restored = await _restoreQueueFromCache(playerId);
        if (restored) {
          _logger.log('✅ Queue restored from cache - playback started');
          return; // Successfully restored and playing
        }
        _logger.log('❌ Could not restore queue from cache');
      }

      ErrorHandler.logError('Resume player', e);
      rethrow;
    }
  }

  /// Attempt to restore the queue from cached data and start playback
  Future<bool> _restoreQueueFromCache(String playerId) async {
    try {
      final cachedQueue = await getCachedQueue(playerId);
      if (cachedQueue == null || cachedQueue.items.isEmpty) {
        _logger.log('⚠️ No cached queue to restore');
        return false;
      }

      // Extract tracks from queue items
      // playTracks needs either: providerMappings with available entries, OR provider+itemId
      final tracks = cachedQueue.items
          .map((item) => item.track)
          .where((track) {
            // Check for providerMappings with at least one available entry
            if (track.providerMappings != null && track.providerMappings!.isNotEmpty) {
              return track.providerMappings!.any((m) => m.available);
            }
            // Fallback: provider + itemId can be used to construct URI
            return track.provider.isNotEmpty && track.itemId.isNotEmpty;
          })
          .toList();

      if (tracks.isEmpty) {
        _logger.log('⚠️ Cached queue has no valid tracks');
        return false;
      }

      _logger.log('🔄 Restoring ${tracks.length} tracks from cached queue');

      // Re-queue all tracks and start playback
      await playTracks(playerId, tracks, startIndex: 0);

      return true;
    } catch (e) {
      _logger.log('❌ Error restoring queue from cache: $e');
      return false;
    }
  }

  Future<void> nextTrack(String playerId) async {
    try {
      // Optimistic local stop for builtin player on skip - non-blocking
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId != null && playerId == builtinPlayerId && _sendspinConnected) {
        _logger.log('⏭️ Non-blocking local stop for skip on builtin player');
        // Stop current audio immediately - fire and forget, but log errors
        unawaited((_pcmAudioPlayer?.pause() ?? Future.value()).catchError(
          (e) => _logger.log('⚠️ PCM pause error on next (non-blocking): $e'),
        ));
        // Don't stop just_audio - not used for Sendspin audio output
      }
      await _api?.nextTrack(playerId);
    } catch (e) {
      ErrorHandler.logError('Next track', e);
      rethrow;
    }
  }

  Future<void> previousTrack(String playerId) async {
    try {
      // Optimistic local stop for builtin player on previous - non-blocking
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId != null && playerId == builtinPlayerId && _sendspinConnected) {
        _logger.log('⏮️ Non-blocking local stop for previous on builtin player');
        // Stop current audio immediately - fire and forget, but log errors
        unawaited((_pcmAudioPlayer?.pause() ?? Future.value()).catchError(
          (e) => _logger.log('⚠️ PCM pause error on previous (non-blocking): $e'),
        ));
        // Don't stop just_audio - not used for Sendspin audio output
      }
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

  // ============================================================================
  // SLEEP TIMER
  // ============================================================================

  /// Set sleep timer. Pass null to turn off, -1 for end of track, or minutes.
  void setSleepTimer(int? minutes) {
    // Cancel any existing timer
    _cancelSleepTimerInternal();

    _sleepTimerMinutes = minutes;

    if (minutes == null) {
      // Timer off
      _logger.log('😴 Sleep timer: OFF');
      notifyListeners();
      return;
    }

    if (minutes == -1) {
      // End of track - handled in player state updates
      _sleepTimerEndTime = null; // No fixed end time
      _logger.log('😴 Sleep timer: End of track');
      notifyListeners();
      return;
    }

    // Set timer for specified minutes
    _sleepTimerEndTime = DateTime.now().add(Duration(minutes: minutes));
    _logger.log('😴 Sleep timer: $minutes minutes (until $_sleepTimerEndTime)');

    // Create the actual timer
    _sleepTimer = Timer(Duration(minutes: minutes), _onSleepTimerExpired);

    // Start display update timer (every second for countdown)
    _sleepTimerDisplayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners(); // Update UI with remaining time
    });

    notifyListeners();
  }

  /// Cancel sleep timer
  void cancelSleepTimer() {
    _cancelSleepTimerInternal();
    _sleepTimerMinutes = null;
    _sleepTimerEndTime = null;
    _logger.log('😴 Sleep timer: Cancelled');
    notifyListeners();
  }

  void _cancelSleepTimerInternal() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerDisplayTimer?.cancel();
    _sleepTimerDisplayTimer = null;
  }

  void _onSleepTimerExpired() {
    _logger.log('😴 Sleep timer expired - pausing playback');
    _cancelSleepTimerInternal();
    _sleepTimerMinutes = null;
    _sleepTimerEndTime = null;

    // Pause the current player
    final playerId = _selectedPlayer?.playerId;
    if (playerId != null) {
      pausePlayer(playerId);
    }

    notifyListeners();
  }

  /// Called when track ends - checks if "end of track" sleep timer is active
  void checkEndOfTrackSleepTimer() {
    if (_sleepTimerMinutes == -1) {
      _logger.log('😴 End of track sleep timer triggered');
      _sleepTimerMinutes = null;

      // Pause the current player
      final playerId = _selectedPlayer?.playerId;
      if (playerId != null) {
        pausePlayer(playerId);
      }

      notifyListeners();
    }
  }

  /// Sync a player to the currently selected player (temporary group)
  /// The target player will play the same audio as the selected player
  Future<void> syncPlayerToSelected(String targetPlayerId) async {
    try {
      final leaderPlayer = _selectedPlayer;
      _logger.log('🔗 syncPlayerToSelected: target=$targetPlayerId, leader=${leaderPlayer?.playerId}');

      if (leaderPlayer == null) {
        _logger.log('❌ Cannot sync: no player selected');
        return;
      }

      if (targetPlayerId == leaderPlayer.playerId) {
        _logger.log('❌ Cannot sync player to itself');
        return;
      }

      if (_api == null) {
        _logger.log('❌ Cannot sync: API is null');
        return;
      }

      // Translate Cast player IDs to Sendspin IDs for group commands
      // Cast players don't support group commands - only their Sendspin counterparts do
      // We need to translate BOTH target and leader IDs
      //
      // The mapping comes from _castToSendspinIdMap which contains:
      // 1. Currently discovered mappings (from available Sendspin players)
      // 2. Persisted mappings from database (survives when Sendspin player is unavailable)
      String translateToSendspinId(String playerId, Player? player) {
        if (_castToSendspinIdMap.containsKey(playerId)) {
          _logger.log('🔗 Found Sendspin mapping: $playerId -> ${_castToSendspinIdMap[playerId]}');
          return _castToSendspinIdMap[playerId]!;
        }
        // No Sendspin counterpart known - use original ID
        return playerId;
      }

      // Find target player to check its provider
      final targetPlayer = _availablePlayers.where((p) => p.playerId == targetPlayerId).firstOrNull;

      // Translate BOTH target AND leader to Sendspin IDs
      // Only Sendspin players support the SET_MEMBERS feature required for grouping
      // Cast players will return "Player X does not support group commands"
      final actualTargetId = translateToSendspinId(targetPlayerId, targetPlayer);
      String actualLeaderId = leaderPlayer.playerId;

      // If leader is a Cast player, translate to its Sendspin counterpart
      if (_castToSendspinIdMap.containsKey(leaderPlayer.playerId)) {
        actualLeaderId = _castToSendspinIdMap[leaderPlayer.playerId]!;
        _logger.log('🔗 Translated leader Cast ID to Sendspin ID: ${leaderPlayer.playerId} -> $actualLeaderId');
      }

      if (actualTargetId != targetPlayerId) {
        _logger.log('🔗 Translated target Cast ID to Sendspin ID: $targetPlayerId -> $actualTargetId');
      }

      _logger.log('🔗 Calling API syncPlayerToLeader($actualTargetId, $actualLeaderId)');
      await _api!.syncPlayerToLeader(actualTargetId, actualLeaderId);
      _logger.log('✅ API sync call completed');

      // Refresh players to get updated group state
      _logger.log('🔄 Refreshing players after sync...');
      await refreshPlayers();
      _logger.log('✅ Players refreshed');
    } catch (e) {
      _logger.log('❌ syncPlayerToSelected error: $e');
      ErrorHandler.logError('Sync player to selected', e);
      rethrow;
    }
  }

  /// Remove a player from its sync group
  Future<void> unsyncPlayer(String playerId) async {
    try {
      _logger.log('🔓 Unsyncing player: $playerId');

      // Find the player to check if it's a child
      final player = _availablePlayers.firstWhere(
        (p) => p.playerId == playerId,
        orElse: () => Player(
          playerId: playerId,
          name: '',
          available: false,
          powered: false,
          state: 'idle',
        ),
      );

      // Determine the effective player ID to unsync
      // For children, we unsync the child directly (not the leader!)
      // Unsyncing the leader would dissolve the entire group
      String effectivePlayerId = playerId;
      String? leaderId = player.syncedTo;

      if (leaderId != null) {
        _logger.log('🔓 Player is a child synced to $leaderId, unsyncing child directly');
      }

      // Try to unsync the player directly
      try {
        await _api?.unsyncPlayer(effectivePlayerId);
      } catch (e) {
        // Some players (like pure Sendspin CLI players) don't support set_members
        // In this case, we need to unsync via the leader instead
        if (e.toString().contains('set_members') && leaderId != null) {
          _logger.log('🔓 Child unsync failed (set_members not supported), unsyncing via leader');

          // Try to find the Sendspin ID for the leader if it's a Cast UUID
          String leaderToUnsync = leaderId;
          if (_castToSendspinIdMap.containsKey(leaderId)) {
            leaderToUnsync = _castToSendspinIdMap[leaderId]!;
            _logger.log('🔓 Translated leader to Sendspin ID: $leaderToUnsync');
          }

          await _api?.unsyncPlayer(leaderToUnsync);
          _logger.log('⚠️ Dissolved entire group (pure Sendspin player limitation)');
        } else {
          rethrow;
        }
      }

      // Refresh players to get updated group state
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Unsync player', e);
      rethrow;
    }
  }

  /// Toggle sync state: if player is synced, unsync it; otherwise sync to selected
  /// For Cast/Sendspin players that are powered off, powers on first then syncs
  Future<void> togglePlayerSync(String playerId) async {
    _logger.log('🔗 togglePlayerSync called for: $playerId');

    try {
      final player = _availablePlayers.firstWhere(
        (p) => p.playerId == playerId,
        orElse: () => throw Exception('Player not found'),
      );

      _logger.log('🔗 Player found: ${player.name}, isGrouped: ${player.isGrouped}');
      _logger.log('🔗 groupMembers: ${player.groupMembers}, syncedTo: ${player.syncedTo}');
      _logger.log('🔗 powered: ${player.powered}, available: ${player.available}');

      if (player.isGrouped) {
        _logger.log('🔓 Player is grouped, unsyncing...');
        await unsyncPlayer(playerId);
      } else {
        // Check if this is a Cast player with a Sendspin counterpart that's powered off
        final hasSendspinCounterpart = _castToSendspinIdMap.containsKey(playerId);

        if (hasSendspinCounterpart && !player.powered) {
          _logger.log('🔌 Cast/Sendspin player is off, powering on first...');

          // Power on the Cast player
          await _api?.setPower(playerId, true);

          // Wait for the player to power on and Sendspin to become ready
          _logger.log('🔗 Waiting for player to power on...');

          // Poll for up to 10 seconds for the player to be powered and available
          const maxAttempts = 20;
          const pollInterval = Duration(milliseconds: 500);

          for (var attempt = 0; attempt < maxAttempts; attempt++) {
            await Future.delayed(pollInterval);
            await refreshPlayers();

            // Check if the Cast player is now powered on
            final updatedPlayer = _availablePlayers.where(
              (p) => p.playerId == playerId
            ).firstOrNull;

            if (updatedPlayer != null && updatedPlayer.powered && updatedPlayer.available) {
              _logger.log('✅ Player powered on, syncing...');
              await syncPlayerToSelected(playerId);
              return;
            }

            _logger.log('⏳ Attempt ${attempt + 1}/$maxAttempts - waiting for power on...');
          }

          _logger.log('⚠️ Timeout waiting for power on, attempting sync anyway...');
          await syncPlayerToSelected(playerId);
        } else {
          _logger.log('🔗 Player not grouped, syncing to selected...');
          await syncPlayerToSelected(playerId);
        }
      }
    } catch (e) {
      _logger.log('❌ togglePlayerSync error: $e');
      rethrow;
    }
  }

  Future<void> togglePower(String playerId) async {
    try {
      _logger.log('🔋 togglePower called for playerId: $playerId');

      final localPlayerId = await SettingsService.getBuiltinPlayerId();
      final isLocalPlayer = localPlayerId != null && playerId == localPlayerId;

      _logger.log('🔋 Is local builtin player: $isLocalPlayer');

      if (isLocalPlayer) {
        _logger.log('🔋 Handling power toggle LOCALLY for builtin player');

        _isLocalPlayerPowered = !_isLocalPlayerPowered;
        _logger.log('🔋 Local player power set to: $_isLocalPlayerPowered');

        if (!_isLocalPlayerPowered) {
          _logger.log('🔋 Stopping playback because powered off');
          await _localPlayer.stop();
        }

        await _reportLocalPlayerState();
        await refreshPlayers();
      } else {
        _logger.log('🔋 Sending power command to server for regular player');

        final player = _availablePlayers.firstWhere(
          (p) => p.playerId == playerId,
          orElse: () => _selectedPlayer != null && _selectedPlayer!.playerId == playerId
              ? _selectedPlayer!
              : throw Exception("Player not found"),
        );

        _logger.log('🔋 Current power state: ${player.powered}, will set to: ${!player.powered}');

        await _api?.setPower(playerId, !player.powered);

        _logger.log('🔋 setPower command sent successfully');

        await refreshPlayers();
      }
    } catch (e) {
      _logger.log('🔋 ERROR in togglePower: $e');
      ErrorHandler.logError('Toggle power', e);
    }
  }

  Future<void> setVolume(String playerId, int volumeLevel) async {
    try {
      // Optimistically update the selected player's volume BEFORE any async calls.
      // This prevents slider snapback: without this, clearing _pendingVolume on drag
      // end causes the slider to read the stale player.volume until player_updated arrives.
      if (_selectedPlayer != null && _selectedPlayer!.playerId == playerId) {
        _selectedPlayer = _selectedPlayer!.copyWith(volumeLevel: volumeLevel);
        notifyListeners();
      }

      // Cache pending volume for ALL players to protect optimistic updates
      // from being overwritten by stale API data in _updatePlayerState()/refreshPlayers().
      _pendingVolumes[playerId] = volumeLevel;
      _pendingVolumeTimestamps[playerId] = DateTime.now().millisecondsSinceEpoch;

      // Also cache for group players in GroupVolumeManager
      // (MA API returns null for group player volume_level)
      final player = _availablePlayers.where((p) => p.playerId == playerId).firstOrNull;
      if (player != null && _groupVolumeManager.isGroupPlayer(player)) {
        _groupVolumeManager.onVolumeSet(playerId, volumeLevel);
      }

      // Proportional volume propagation for in-app sync group leaders.
      // When a user creates a group via long-press (players/cmd/group), the leader
      // retains its own non-null volumeLevel and isGroupPlayer() returns false.
      // We detect this via isGroupLeader and propagate volume changes to all
      // members proportionally, preserving relative volume balance.
      if (player != null &&
          player.isGroupLeader &&
          !_groupVolumeManager.isGroupPlayer(player)) {
        final currentVol = player.volumeLevel;
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final memberId in player.groupMembers!) {
          if (memberId == playerId) continue; // Skip the leader itself
          final idx = _availablePlayers.indexWhere((p) => p.playerId == memberId);
          if (idx == -1) continue;
          final member = _availablePlayers[idx];
          if (member.volumeLevel == null) continue;

          final int memberNewVol;
          if (currentVol != null && currentVol > 0) {
            // Ratio-based: maintain relative balance between members
            memberNewVol = (member.volumeLevel! * volumeLevel / currentVol)
                .round()
                .clamp(0, 100);
          } else {
            // Can't ratio from 0 — set all to the new absolute value
            memberNewVol = volumeLevel;
          }

          // Protect from snap-back and update optimistically
          _pendingVolumes[memberId] = memberNewVol;
          _pendingVolumeTimestamps[memberId] = now;
          _availablePlayers[idx] = member.copyWith(volumeLevel: memberNewVol);
          // Fire-and-forget — don't await, send in parallel
          _api?.setVolume(memberId, memberNewVol);
        }
      }

      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId != null && playerId == builtinPlayerId) {
        _localPlayerVolume = volumeLevel;
        await FlutterVolumeController.setVolume(volumeLevel / 100.0);
      }
      await _api?.setVolume(playerId, volumeLevel);
    } catch (e) {
      ErrorHandler.logError('Set volume', e);
      rethrow;
    }
  }

  Future<void> setMute(String playerId, bool muted) async {
    try {
      await _api?.setMute(playerId, muted);
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Set mute', e);
      rethrow;
    }
  }

  Future<void> seek(String playerId, int position) async {
    try {
      // Immediately update position tracker for responsive UI
      _positionTracker.onSeek(position.toDouble());
      // Immediately update notification position to stay in sync with app
      // Use forceUpdate since seek can happen while paused
      _updateNotificationPosition(forceUpdate: true);
      await _api?.seek(playerId, position);
    } catch (e) {
      ErrorHandler.logError('Seek', e);
      rethrow;
    }
  }

  /// Seek relative to current position (e.g., +30 or -30 seconds)
  Future<void> seekRelative(String playerId, int deltaSeconds) async {
    try {
      final currentPosition = _positionTracker.currentPosition.inSeconds;
      final totalDuration = _currentTrack?.duration?.inSeconds ?? 0;
      final newPosition = (currentPosition + deltaSeconds).clamp(0, totalDuration);
      await seek(playerId, newPosition);
    } catch (e) {
      ErrorHandler.logError('Seek relative', e);
      rethrow;
    }
  }

  // ============================================================================
  // AUDIOBOOK CONTEXT
  // ============================================================================

  /// Set the currently playing audiobook context (with chapters)
  void setCurrentAudiobook(Audiobook audiobook) {
    _currentAudiobook = audiobook;
    _logger.log('📚 Set current audiobook: ${audiobook.name}, chapters: ${audiobook.chapters?.length ?? 0}');
    notifyListeners();
  }

  /// Clear the audiobook context
  void clearCurrentAudiobook() {
    if (_currentAudiobook != null) {
      _logger.log('📚 Cleared audiobook context');
      _currentAudiobook = null;
      notifyListeners();
    }
  }

  /// Get the current chapter based on playback position
  Chapter? getCurrentChapter() {
    if (_currentAudiobook == null || _currentAudiobook!.chapters == null) return null;
    final chapters = _currentAudiobook!.chapters!;
    if (chapters.isEmpty) return null;

    final currentPositionMs = _positionTracker.currentPosition.inMilliseconds;

    // Find the chapter that contains the current position
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (currentPositionMs >= chapters[i].positionMs) {
        return chapters[i];
      }
    }
    return chapters.first;
  }

  /// Get the index of the current chapter
  int getCurrentChapterIndex() {
    if (_currentAudiobook == null || _currentAudiobook!.chapters == null) return -1;
    final chapters = _currentAudiobook!.chapters!;
    if (chapters.isEmpty) return -1;

    final currentPositionMs = _positionTracker.currentPosition.inMilliseconds;

    for (int i = chapters.length - 1; i >= 0; i--) {
      if (currentPositionMs >= chapters[i].positionMs) {
        return i;
      }
    }
    return 0;
  }

  /// Seek to the next chapter
  Future<void> seekToNextChapter(String playerId) async {
    if (_currentAudiobook == null || _currentAudiobook!.chapters == null) return;
    final chapters = _currentAudiobook!.chapters!;
    if (chapters.isEmpty) return;

    final currentIndex = getCurrentChapterIndex();
    if (currentIndex < chapters.length - 1) {
      final nextChapter = chapters[currentIndex + 1];
      final positionSeconds = nextChapter.positionMs ~/ 1000;
      await seek(playerId, positionSeconds);
      _logger.log('📚 Jumped to next chapter: ${nextChapter.title}');
    }
  }

  /// Seek to the previous chapter (or start of current chapter if > 3 seconds in)
  Future<void> seekToPreviousChapter(String playerId) async {
    if (_currentAudiobook == null || _currentAudiobook!.chapters == null) return;
    final chapters = _currentAudiobook!.chapters!;
    if (chapters.isEmpty) return;

    final currentIndex = getCurrentChapterIndex();
    if (currentIndex < 0) return;

    final currentChapter = chapters[currentIndex];
    final currentPositionMs = _positionTracker.currentPosition.inMilliseconds;
    final chapterProgressMs = currentPositionMs - currentChapter.positionMs;

    // If more than 3 seconds into current chapter, go to start of current chapter
    // Otherwise, go to previous chapter
    if (chapterProgressMs > 3000 || currentIndex == 0) {
      final positionSeconds = currentChapter.positionMs ~/ 1000;
      await seek(playerId, positionSeconds);
      _logger.log('📚 Jumped to start of chapter: ${currentChapter.title}');
    } else {
      final previousChapter = chapters[currentIndex - 1];
      final positionSeconds = previousChapter.positionMs ~/ 1000;
      await seek(playerId, positionSeconds);
      _logger.log('📚 Jumped to previous chapter: ${previousChapter.title}');
    }
  }

  Future<void> toggleShuffle(String queueId, bool shuffleEnabled) async {
    _logger.log('🔀 toggleShuffle called: queueId=$queueId, shuffleEnabled=$shuffleEnabled');
    try {
      await _api?.toggleShuffle(queueId, shuffleEnabled);
      _logger.log('🔀 toggleShuffle: API call completed');
    } catch (e) {
      _logger.log('🔀 toggleShuffle ERROR: $e');
      ErrorHandler.logError('Toggle shuffle', e);
      rethrow;
    }
  }

  Future<void> setRepeatMode(String queueId, String mode) async {
    try {
      await _api?.setRepeatMode(queueId, mode);
    } catch (e) {
      ErrorHandler.logError('Set repeat mode', e);
      rethrow;
    }
  }

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

  @override
  void dispose() {
    _playerStateTimer?.cancel();
    _notificationPositionTimer?.cancel();
    _localPlayerStateReportTimer?.cancel();
    _sleepTimer?.cancel();
    _sleepTimerDisplayTimer?.cancel();
    _idleServiceTimer?.cancel();
    _connectionStateSubscription?.cancel();
    _localPlayerEventSubscription?.cancel();
    _playerUpdatedEventSubscription?.cancel();
    _playerAddedEventSubscription?.cancel();
    _mediaItemAddedEventSubscription?.cancel();
    _mediaItemDeletedEventSubscription?.cancel();
    _positionTracker.dispose();
    _pcmAudioPlayer?.dispose();
    _sendspinService?.dispose();
    _api?.dispose();
    super.dispose();
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Check if a hostname is a local/private network address
  bool _isLocalNetworkHost(String host) {
    return host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.16.') ||
        host.startsWith('172.17.') ||
        host.startsWith('172.18.') ||
        host.startsWith('172.19.') ||
        host.startsWith('172.2') ||
        host.startsWith('172.30.') ||
        host.startsWith('172.31.') ||
        host == 'localhost' ||
        host.startsWith('127.') ||
        host.endsWith('.local') ||
        host.endsWith('.ts.net'); // Tailscale - treat as local since it's a VPN
  }
}
