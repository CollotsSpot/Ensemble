import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/music_assistant_provider.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../services/sync_service.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_selector.dart';
import '../widgets/album_row.dart';
import '../widgets/artist_row.dart';
import '../widgets/track_row.dart';
import '../widgets/audiobook_row.dart';
import '../widgets/series_row.dart';
import '../widgets/playlist_row.dart';
import '../widgets/radio_station_row.dart';
import '../widgets/podcast_row.dart';
import '../widgets/common/disconnected_state.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

class NewHomeScreen extends StatefulWidget {
  const NewHomeScreen({super.key});

  @override
  State<NewHomeScreen> createState() => _NewHomeScreenState();
}

class _NewHomeScreenState extends State<NewHomeScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static final _logger = DebugLogger();
  Key _refreshKey = UniqueKey();
  // Main rows (default on)
  bool _showRecentAlbums = true;
  bool _showDiscoverArtists = true;
  bool _showDiscoverAlbums = true;
  // Favorites rows (default off)
  bool _showFavoriteAlbums = false;
  bool _showFavoriteArtists = false;
  bool _showFavoriteTracks = false;
  bool _showFavoritePlaylists = false;
  bool _showFavoriteRadioStations = false;
  bool _showFavoritePodcasts = false;
  // Audiobook rows (default off)
  bool _showContinueListeningAudiobooks = false;
  bool _showDiscoverAudiobooks = false;
  bool _showDiscoverSeries = false;
  // Row order (loaded from settings)
  List<String> _homeRowOrder = List.from(SettingsService.defaultHomeRowOrder);

  @override
  bool get wantKeepAlive => true;

  // Track if we had empty favorites on first load (to know when to refresh)
  bool _hadEmptyFavoritesOnLoad = false;
  SyncStatus? _lastSyncStatus;
  int _lastArtistCount = 0;
  MusicAssistantProvider? _providerListeningTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    // Listen to sync completion to refresh favorite rows when data becomes available
    SyncService.instance.addListener(_onSyncChanged);
    _lastSyncStatus = SyncService.instance.status;
    _checkInitialFavoriteState();
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_onSyncChanged);
    // Clean up provider listener if attached
    _providerListeningTo?.removeListener(_onProviderChanged);
    _providerListeningTo = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Check if favorites are empty on initial load (so we know to refresh after sync)
  void _checkInitialFavoriteState() {
    // Schedule after first frame to ensure provider is accessible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<MusicAssistantProvider>();
      _lastArtistCount = provider.artists.length;
      // Check if artists list is empty - favorites will also be empty
      if (_lastArtistCount == 0) {
        _hadEmptyFavoritesOnLoad = true;
        _logger.log('📋 Home: favorites empty on load, will refresh after sync');
        // Also listen to provider for when cache loads (before sync completes)
        _providerListeningTo = provider;
        provider.addListener(_onProviderChanged);
      }
    });
  }

  /// Called when MusicAssistantProvider changes (for cache load detection)
  void _onProviderChanged() {
    if (!mounted || !_hadEmptyFavoritesOnLoad || _providerListeningTo == null) return;
    final currentCount = _providerListeningTo!.artists.length;
    // If artists went from 0 to non-zero, refresh
    if (_lastArtistCount == 0 && currentCount > 0) {
      _logger.log('🔄 Home: artists loaded from cache ($currentCount), refreshing rows');
      _hadEmptyFavoritesOnLoad = false;
      _providerListeningTo!.removeListener(_onProviderChanged);
      _providerListeningTo = null;
      setState(() {
        _refreshKey = UniqueKey();
      });
    }
    _lastArtistCount = currentCount;
  }

  /// Called when SyncService status changes
  void _onSyncChanged() {
    final newStatus = SyncService.instance.status;
    // When sync completes and we had empty favorites, refresh to show new data
    if (_lastSyncStatus == SyncStatus.syncing &&
        newStatus == SyncStatus.completed &&
        _hadEmptyFavoritesOnLoad) {
      _logger.log('🔄 Home: sync completed, refreshing favorite rows');
      _hadEmptyFavoritesOnLoad = false;
      // Clean up provider listener if still attached
      _providerListeningTo?.removeListener(_onProviderChanged);
      _providerListeningTo = null;
      if (mounted) {
        setState(() {
          _refreshKey = UniqueKey();
        });
      }
    }
    _lastSyncStatus = newStatus;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reload settings when app resumes (coming back from settings)
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final showRecent = await SettingsService.getShowRecentAlbums();
    final showDiscArtists = await SettingsService.getShowDiscoverArtists();
    final showDiscAlbums = await SettingsService.getShowDiscoverAlbums();
    final showFavAlbums = await SettingsService.getShowFavoriteAlbums();
    final showFavArtists = await SettingsService.getShowFavoriteArtists();
    final showFavTracks = await SettingsService.getShowFavoriteTracks();
    final showFavPlaylists = await SettingsService.getShowFavoritePlaylists();
    final showFavRadio = await SettingsService.getShowFavoriteRadioStations();
    final showFavPodcasts = await SettingsService.getShowFavoritePodcasts();
    final showContAudiobooks = await SettingsService.getShowContinueListeningAudiobooks();
    final showDiscAudiobooks = await SettingsService.getShowDiscoverAudiobooks();
    final showDiscSeries = await SettingsService.getShowDiscoverSeries();
    final rowOrder = await SettingsService.getHomeRowOrder();
    if (mounted) {
      setState(() {
        _showRecentAlbums = showRecent;
        _showDiscoverArtists = showDiscArtists;
        _showDiscoverAlbums = showDiscAlbums;
        _showFavoriteAlbums = showFavAlbums;
        _showFavoriteArtists = showFavArtists;
        _showFavoriteTracks = showFavTracks;
        _showFavoritePlaylists = showFavPlaylists;
        _showFavoriteRadioStations = showFavRadio;
        _showFavoritePodcasts = showFavPodcasts;
        _showContinueListeningAudiobooks = showContAudiobooks;
        _showDiscoverAudiobooks = showDiscAudiobooks;
        _showDiscoverSeries = showDiscSeries;
        _homeRowOrder = rowOrder;
      });
    }
  }

  Future<void> _onRefresh() async {
    // Invalidate cache to force fresh data on pull-to-refresh
    final provider = context.read<MusicAssistantProvider>();
    provider.invalidateHomeCache();

    // Force full library sync from MA API
    await provider.forceLibrarySync();

    // Reload settings in case they changed
    await _loadSettings();

    if (mounted) {
      setState(() {
        _refreshKey = UniqueKey();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // Settings are loaded in initState and didChangeAppLifecycleState - no need to reload on every build
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: ColorFiltered(
            colorFilter: Theme.of(context).brightness == Brightness.light
                ? const ColorFilter.matrix(<double>[
                    -1,  0,  0, 0, 255,
                     0, -1,  0, 0, 255,
                     0,  0, -1, 0, 255,
                     0,  0,  0, 1,   0,
                  ])
                : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
            child: Image.asset(
              'assets/images/ensemble_logo.png',
              height: 40,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        titleSpacing: 0,
        centerTitle: false,
        actions: [
          // Copy logs button for debugging
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, size: 20),
            onPressed: () {
              final logs = DebugLogger().entries.map((e) => e.formatted).join('\n');
              Clipboard.setData(ClipboardData(text: logs));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${DebugLogger().entries.length} log entries copied'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Copy logs',
          ),
          // Sync indicator - shows when library is syncing in background
          ListenableBuilder(
            listenable: SyncService.instance,
            builder: (context, _) {
              if (!SyncService.instance.isSyncing) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary.withOpacity(0.7),
                    ),
                  ),
                ),
              );
            },
          ),
          const PlayerSelector(),
        ],
      ),
      body: SafeArea(
        child: Selector<MusicAssistantProvider, bool>(
          selector: (_, p) => p.isConnected,
          builder: (context, isConnected, child) {
            final maProvider = context.read<MusicAssistantProvider>();
            final syncService = SyncService.instance;

            // Show cached data even when not connected (if we have cache)
            // Only show disconnected state if we have no cached data at all
            if (!isConnected && !syncService.hasCache) {
              return DisconnectedState.full(
                context: context,
                onSettings: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                ),
              );
            }

            return Stack(
              children: [
                // Main content
                RefreshIndicator(
                  onRefresh: _onRefresh,
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.background,
                  child: _buildConnectedView(context, maProvider),
                ),
                // Connecting banner overlay (doesn't affect layout)
                // Hide when we have cached players - UI is functional during background reconnect
                if (!isConnected && syncService.hasCache && !maProvider.hasCachedPlayers)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      color: colorScheme.primaryContainer.withOpacity(0.9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            S.of(context)!.connecting,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }


  /// Count how many rows are currently enabled
  int _countEnabledRows() {
    int count = 0;
    for (final rowId in _homeRowOrder) {
      if (_isRowEnabled(rowId)) count++;
    }
    return count;
  }

  /// Check if a specific row is enabled
  bool _isRowEnabled(String rowId) {
    switch (rowId) {
      case 'recent-albums': return _showRecentAlbums;
      case 'discover-artists': return _showDiscoverArtists;
      case 'discover-albums': return _showDiscoverAlbums;
      case 'continue-listening': return _showContinueListeningAudiobooks;
      case 'discover-audiobooks': return _showDiscoverAudiobooks;
      case 'discover-series': return _showDiscoverSeries;
      case 'favorite-albums': return _showFavoriteAlbums;
      case 'favorite-artists': return _showFavoriteArtists;
      case 'favorite-tracks': return _showFavoriteTracks;
      case 'favorite-playlists': return _showFavoritePlaylists;
      case 'favorite-radio-stations': return _showFavoriteRadioStations;
      case 'favorite-podcasts': return _showFavoritePodcasts;
      default: return false;
    }
  }

  Widget _buildConnectedView(
      BuildContext context, MusicAssistantProvider provider) {
    // Use LayoutBuilder to get available screen height
    return LayoutBuilder(
      builder: (context, constraints) {
        // Each row is always 1/3 of screen height
        // 1 row = 1/3, 2 rows = 2/3, 3 rows = full screen, 4+ rows scroll
        final availableHeight = constraints.maxHeight - BottomSpacing.withMiniPlayer;

        // Account for margins between rows (2px each)
        // Only adjust for margins when ≤3 rows (so they fit exactly without scroll)
        // For 4+ rows, use original calculation so 4th row stays hidden (scrollable)
        const marginSize = 2.0;
        final enabledRows = _countEnabledRows();
        final marginsInView = enabledRows > 1 && enabledRows <= 3 ? (enabledRows - 1) * marginSize : 0.0;
        final rowHeight = (availableHeight - marginsInView) / 3;

        // Use Android 12+ stretch overscroll effect
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              _logger.resetFrameStats();
              _logger.perf('SCROLL START', context: 'HomeScreen');
            } else if (notification is ScrollUpdateNotification) {
              _logger.startFrame();
              SchedulerBinding.instance.addPostFrameCallback((_) {
                _logger.endFrame();
              });
            } else if (notification is ScrollEndNotification) {
              _logger.perf('SCROLL END', context: 'HomeScreen');
            }
            return false;
          },
          child: ScrollConfiguration(
            behavior: const _StretchScrollBehavior(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: BottomSpacing.withMiniPlayer),
              child: Column(
                key: _refreshKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildOrderedRows(provider, rowHeight),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build rows in the user's configured order
  List<Widget> _buildOrderedRows(MusicAssistantProvider provider, double rowHeight) {
    final rows = <Widget>[];

    for (final rowId in _homeRowOrder) {
      final widget = _buildRowWidget(rowId, provider, rowHeight);
      if (widget != null) {
        // Add spacing between rows (not before first row)
        if (rows.isNotEmpty) {
          rows.add(const SizedBox(height: 2.0));
        }
        rows.add(widget);
      }
    }

    return rows;
  }

  /// Build a single row widget by ID, returns null if row is disabled
  Widget? _buildRowWidget(String rowId, MusicAssistantProvider provider, double rowHeight) {
    switch (rowId) {
      case 'recent-albums':
        if (!_showRecentAlbums) return null;
        return AlbumRow(
          key: const ValueKey('recent-albums'),
          title: S.of(context)!.recentlyPlayed,
          loadAlbums: () => provider.getRecentAlbumsWithCache(),
          getCachedAlbums: () => provider.getCachedRecentAlbums(),
          rowHeight: rowHeight,
        );
      case 'discover-artists':
        if (!_showDiscoverArtists) return null;
        return ArtistRow(
          key: const ValueKey('discover-artists'),
          title: S.of(context)!.discoverArtists,
          loadArtists: () => provider.getDiscoverArtistsWithCache(),
          getCachedArtists: () => provider.getCachedDiscoverArtists(),
          rowHeight: rowHeight,
        );
      case 'discover-albums':
        if (!_showDiscoverAlbums) return null;
        return AlbumRow(
          key: const ValueKey('discover-albums'),
          title: S.of(context)!.discoverAlbums,
          loadAlbums: () => provider.getDiscoverAlbumsWithCache(),
          getCachedAlbums: () => provider.getCachedDiscoverAlbums(),
          rowHeight: rowHeight,
        );
      case 'continue-listening':
        if (!_showContinueListeningAudiobooks) return null;
        return AudiobookRow(
          key: const ValueKey('continue-listening'),
          title: S.of(context)!.continueListening,
          loadAudiobooks: () => provider.getInProgressAudiobooksWithCache(),
          getCachedAudiobooks: () => provider.getCachedInProgressAudiobooks(),
          rowHeight: rowHeight,
        );
      case 'discover-audiobooks':
        if (!_showDiscoverAudiobooks) return null;
        return AudiobookRow(
          key: const ValueKey('discover-audiobooks'),
          title: S.of(context)!.discoverAudiobooks,
          loadAudiobooks: () => provider.getDiscoverAudiobooksWithCache(),
          getCachedAudiobooks: () => provider.getCachedDiscoverAudiobooks(),
          rowHeight: rowHeight,
        );
      case 'discover-series':
        if (!_showDiscoverSeries) return null;
        return SeriesRow(
          key: const ValueKey('discover-series'),
          title: S.of(context)!.discoverSeries,
          loadSeries: () => provider.getDiscoverSeriesWithCache(),
          getCachedSeries: () => provider.getCachedDiscoverSeries(),
          rowHeight: rowHeight,
        );
      case 'favorite-albums':
        if (!_showFavoriteAlbums) return null;
        return AlbumRow(
          key: const ValueKey('favorite-albums'),
          title: S.of(context)!.favoriteAlbums,
          loadAlbums: () => provider.getFavoriteAlbums(),
          rowHeight: rowHeight,
        );
      case 'favorite-artists':
        if (!_showFavoriteArtists) return null;
        return ArtistRow(
          key: const ValueKey('favorite-artists'),
          title: S.of(context)!.favoriteArtists,
          loadArtists: () => provider.getFavoriteArtists(),
          rowHeight: rowHeight,
        );
      case 'favorite-tracks':
        if (!_showFavoriteTracks) return null;
        return TrackRow(
          key: const ValueKey('favorite-tracks'),
          title: S.of(context)!.favoriteTracks,
          loadTracks: () => provider.getFavoriteTracks(),
          rowHeight: rowHeight,
        );
      case 'favorite-playlists':
        if (!_showFavoritePlaylists) return null;
        return PlaylistRow(
          key: const ValueKey('favorite-playlists'),
          title: S.of(context)!.favoritePlaylists,
          loadPlaylists: () => provider.getFavoritePlaylists(),
          heroTagSuffix: 'home',
          rowHeight: rowHeight,
        );
      case 'favorite-radio-stations':
        if (!_showFavoriteRadioStations) return null;
        return RadioStationRow(
          key: const ValueKey('favorite-radio-stations'),
          title: S.of(context)!.favoriteRadioStations,
          loadRadioStations: () => provider.getFavoriteRadioStations(),
          heroTagSuffix: 'home',
          rowHeight: rowHeight,
        );
      case 'favorite-podcasts':
        if (!_showFavoritePodcasts) return null;
        return PodcastRow(
          key: const ValueKey('favorite-podcasts'),
          title: S.of(context)!.favoritePodcasts,
          loadPodcasts: () => provider.getFavoritePodcasts(),
          heroTagSuffix: 'home',
          rowHeight: rowHeight,
        );
      default:
        return null;
    }
  }
}

/// Custom scroll behavior that uses Android 12+ stretch overscroll effect
class _StretchScrollBehavior extends ScrollBehavior {
  const _StretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}
