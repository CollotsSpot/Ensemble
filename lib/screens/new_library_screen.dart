import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/navigation_provider.dart';
import '../models/media_item.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/album_card.dart';
import '../widgets/artist_avatar.dart';
import '../utils/page_transitions.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/common/disconnected_state.dart';
import '../widgets/letter_scrollbar.dart';
import '../services/settings_service.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import '../services/sync_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/design_tokens.dart';
import 'album_details_screen.dart';
import 'artist_details_screen.dart';
import 'playlist_details_screen.dart';
import 'settings_screen.dart';
import 'audiobook_author_screen.dart';
import 'audiobook_detail_screen.dart';
import 'audiobook_series_screen.dart';
import 'podcast_detail_screen.dart';

/// Media type for the library
enum LibraryMediaType { music, books, podcasts, radio }

class NewLibraryScreen extends StatefulWidget {
  const NewLibraryScreen({super.key});

  @override
  State<NewLibraryScreen> createState() => _NewLibraryScreenState();
}

class _NewLibraryScreenState extends State<NewLibraryScreen>
    with RestorationMixin {
  late PageController _pageController;
  final _menuButtonKey = GlobalKey();
  List<Playlist> _playlists = [];
  List<Track> _favoriteTracks = [];
  List<Audiobook> _audiobooks = [];
  bool _isLoadingPlaylists = true;
  bool _isLoadingTracks = false;
  bool _isLoadingAudiobooks = false;
  bool _showFavoritesOnly = false;
  bool _isChangingMediaType = false; // Flag to ignore onPageChanged during media type transitions
  bool _showOnlyArtistsWithAlbums = false; // Filter artists tab to only show those with albums
  bool _isSyncingArtists = false; // Show progress while re-syncing artists

  // All tracks with lazy loading
  List<Track> _allTracks = [];
  List<Track> _sortedAllTracks = [];
  List<String> _trackNames = [];
  bool _isLoadingMoreTracks = false;
  bool _hasMoreTracks = true;
  int _tracksOffset = 0;
  static const int _tracksPageSize = 100;
  static const int _tracksInitialLoad = 200;

  // PERF: Pre-sorted lists - computed once on data load, not on every build
  List<Playlist> _sortedPlaylists = [];
  List<String> _playlistNames = [];
  List<Track> _sortedFavoriteTracks = [];
  List<Audiobook> _sortedAudiobooks = [];
  List<String> _audiobookNames = [];
  List<String> _sortedAuthorNames = [];
  Map<String, List<Audiobook>> _groupedAudiobooksByAuthor = {};
  List<AudiobookSeries> _sortedSeries = [];
  List<String> _seriesNames = [];

  // Media type selection (Music, Books, Podcasts)
  LibraryMediaType _selectedMediaType = LibraryMediaType.music;

  // Track overscroll for switching between media types
  double _horizontalOverscroll = 0;
  static const double _overscrollThreshold = 80; // Pixels to trigger switch

  // Track horizontal drag for single-category types (where PageView doesn't overscroll)
  double _horizontalDragStart = 0;
  double _horizontalDragDelta = 0;

  // View mode settings
  String _artistsViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _albumsViewMode = 'grid2'; // 'grid2', 'grid3', 'list'
  String _playlistsViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _audiobooksViewMode = 'grid2'; // 'grid2', 'grid3', 'list'
  String _authorsViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _seriesViewMode = 'grid2'; // 'grid2', 'grid3'
  String _radioViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _podcastsViewMode = 'grid2'; // 'grid2', 'grid3', 'list'
  String _audiobooksSortOrder = 'alpha'; // 'alpha', 'year'

  // Sort orders for all categories
  // MA API sort values: name, name_desc, sort_name, sort_name_desc, timestamp_added, timestamp_added_desc,
  // last_played, last_played_desc, play_count, play_count_desc, year, year_desc, artist_name, artist_name_desc,
  // duration, duration_desc, timestamp_modified, timestamp_modified_desc
  String _artistsSortOrder = 'name';
  String _albumsSortOrder = 'name';
  String _tracksSortOrder = 'name';
  String _playlistsSortOrder = 'name';
  String _authorsSortOrder = 'alpha'; // Books use client-side sorting
  String _seriesSortOrder = 'alpha'; // Books use client-side sorting
  String _radioSortOrder = 'name';
  String _podcastsSortOrder = 'name';

  // Author image cache
  final Map<String, String?> _authorImages = {};

  // Series state
  List<AudiobookSeries> _series = [];
  bool _isLoadingSeries = false;

  // Series book covers cache: seriesId -> list of book thumbnail URLs
  final Map<String, List<String>> _seriesBookCovers = {};
  final Set<String> _seriesCoversLoading = {};
  // Series extracted colors cache: seriesId -> list of colors from book covers
  final Map<String, List<Color>> _seriesExtractedColors = {};
  // Series book counts cache: seriesId -> number of books
  final Map<String, int> _seriesBookCounts = {};
  bool _seriesLoaded = false;
  // Pre-cache flag for podcast images (smooth hero animations)
  bool _hasPrecachedPodcasts = false;
  // PERF: Debounce color extraction to avoid blocking UI during scroll
  Timer? _colorExtractionDebounce;
  final Map<String, List<String>> _pendingColorExtractions = {};

  // Restoration: Remember selected tab across app restarts
  final RestorableInt _selectedTabIndex = RestorableInt(0);
  // PERF: Separate ValueNotifier for efficient UI updates (RestorableInt doesn't implement ValueListenable)
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);

  // Scroll-to-hide filter bars
  bool _isFilterBarVisible = true;
  double _lastScrollOffset = 0;
  static const double _scrollThreshold = 10.0;
  bool _isLetterScrollbarDragging = false; // Disable scroll-to-hide while dragging

  // Options menu overlay - stored to close on navigation
  OverlayEntry? _optionsMenuOverlay;

  // Scroll controllers for letter scrollbar
  final ScrollController _artistsScrollController = ScrollController();
  final ScrollController _albumsScrollController = ScrollController();
  final ScrollController _playlistsScrollController = ScrollController();
  final ScrollController _tracksScrollController = ScrollController();
  final ScrollController _authorsScrollController = ScrollController();
  final ScrollController _audiobooksScrollController = ScrollController();
  final ScrollController _seriesScrollController = ScrollController();
  final ScrollController _podcastsScrollController = ScrollController();
  final ScrollController _radioScrollController = ScrollController();

  int get _tabCount => _getTabCountForType(_selectedMediaType);

  int _getTabCountForType(LibraryMediaType type) {
    switch (type) {
      case LibraryMediaType.music:
        return 4; // Artists, Albums, Tracks, Playlists (always 4)
      case LibraryMediaType.books:
        return 3; // Authors, All Books, Series
      case LibraryMediaType.podcasts:
        return 1; // Coming soon placeholder
      case LibraryMediaType.radio:
        return 1; // Radio stations
    }
  }

  @override
  String? get restorationId => 'new_library_screen';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_selectedTabIndex, 'selected_tab_index');
    // Sync ValueNotifier with restored value
    _tabIndexNotifier.value = _selectedTabIndex.value;
    // Apply restored tab index after PageController is created
    if (_selectedTabIndex.value < _tabCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_selectedTabIndex.value);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadPlaylists();
    _loadViewPreferences();
    _loadAllTracks(); // Load tracks for the permanent Tracks tab

    // Add scroll listener for lazy loading tracks
    _tracksScrollController.addListener(_onTracksScroll);

    // Close options menu when navigating away from Library
    navigationProvider.addListener(_onNavigationChanged);
  }

  void _onNavigationChanged() {
    // Library is index 1, close menu when navigating to another tab
    if (navigationProvider.selectedIndex != 1) {
      _closeOptionsMenu();
    }
  }

  /// Close the options menu overlay if open
  void _closeOptionsMenu() {
    _optionsMenuOverlay?.remove();
    _optionsMenuOverlay = null;
  }

  void _onTracksScroll() {
    if (_tracksScrollController.position.pixels >=
        _tracksScrollController.position.maxScrollExtent - 500) {
      _loadMoreTracks();
    }
  }

  Future<void> _loadViewPreferences() async {
    // View modes
    final artistsMode = await SettingsService.getLibraryArtistsViewMode();
    final albumsMode = await SettingsService.getLibraryAlbumsViewMode();
    final playlistsMode = await SettingsService.getLibraryPlaylistsViewMode();
    final authorsMode = await SettingsService.getLibraryAuthorsViewMode();
    final audiobooksMode = await SettingsService.getLibraryAudiobooksViewMode();
    final audiobooksSortOrder = await SettingsService.getLibraryAudiobooksSortOrder();
    final seriesMode = await SettingsService.getLibrarySeriesViewMode();
    final radioMode = await SettingsService.getLibraryRadioViewMode();
    final podcastsMode = await SettingsService.getLibraryPodcastsViewMode();

    // Sort orders
    final artistsSort = await SettingsService.getLibraryArtistsSortOrder();
    final albumsSort = await SettingsService.getLibraryAlbumsSortOrder();
    final tracksSort = await SettingsService.getLibraryTracksSortOrder();
    final playlistsSort = await SettingsService.getLibraryPlaylistsSortOrder();
    final authorsSort = await SettingsService.getLibraryAuthorsSortOrder();
    final seriesSort = await SettingsService.getLibrarySeriesSortOrder();
    final radioSort = await SettingsService.getLibraryRadioSortOrder();
    final podcastsSort = await SettingsService.getLibraryPodcastsSortOrder();

    // Artists filter setting
    final showOnlyArtistsWithAlbums = await SettingsService.getShowOnlyArtistsWithAlbums();

    if (mounted) {
      setState(() {
        // View modes
        _artistsViewMode = artistsMode;
        _albumsViewMode = albumsMode;
        _playlistsViewMode = playlistsMode;
        _authorsViewMode = authorsMode;
        _audiobooksViewMode = audiobooksMode;
        _audiobooksSortOrder = audiobooksSortOrder;
        _seriesViewMode = seriesMode;
        _radioViewMode = radioMode;
        _podcastsViewMode = podcastsMode;

        // Sort orders (migrate legacy values)
        _artistsSortOrder = _migrateSortOrder(artistsSort);
        _albumsSortOrder = _migrateSortOrder(albumsSort);
        _tracksSortOrder = _migrateSortOrder(tracksSort);
        _playlistsSortOrder = _migrateSortOrder(playlistsSort);
        _authorsSortOrder = authorsSort; // Books keep legacy sort
        _seriesSortOrder = seriesSort; // Books keep legacy sort
        _radioSortOrder = _migrateSortOrder(radioSort);
        _podcastsSortOrder = _migrateSortOrder(podcastsSort);

        // Artists filter
        _showOnlyArtistsWithAlbums = showOnlyArtistsWithAlbums;
      });
    }
  }

  /// Migrate legacy sort values to new MA-compatible values
  String _migrateSortOrder(String order) {
    switch (order) {
      case 'alpha':
        return 'name';
      case 'alpha_desc':
        return 'name_desc';
      case 'artist':
        return 'artist_name';
      case 'album':
        // For tracks sorted by album, use timestamp_added as fallback since MA doesn't have album sort
        return 'timestamp_added_desc';
      default:
        return order;
    }
  }

  /// Sort audiobooks based on current sort order
  void _sortAudiobooks() {
    final sorted = List<Audiobook>.from(_audiobooks);
    if (_audiobooksSortOrder == 'year') {
      sorted.sort((a, b) {
        if (a.year == null && b.year == null) return a.name.compareTo(b.name);
        if (a.year == null) return 1;
        if (b.year == null) return -1;
        return a.year!.compareTo(b.year!);
      });
    } else {
      sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    _sortedAudiobooks = sorted;
    _audiobookNames = sorted.map((a) => a.name).toList();
  }

  String _getCurrentViewMode() {
    // Return the view mode for the currently selected tab
    final tabIndex = _selectedTabIndex.value;

    // Handle books media type
    if (_selectedMediaType == LibraryMediaType.books) {
      switch (tabIndex) {
        case 0:
          return _authorsViewMode;
        case 1:
          return _audiobooksViewMode;
        case 2:
          return _seriesViewMode;
        default:
          return 'list';
      }
    }

    // Handle radio media type
    if (_selectedMediaType == LibraryMediaType.radio) {
      return _radioViewMode;
    }

    // Handle podcasts media type
    if (_selectedMediaType == LibraryMediaType.podcasts) {
      return _podcastsViewMode;
    }

    // Handle music media type
    if (_showFavoritesOnly) {
      // Artists, Albums, Tracks, Playlists
      switch (tabIndex) {
        case 0:
          return _artistsViewMode;
        case 1:
          return _albumsViewMode;
        case 2:
          return 'list'; // Tracks always list
        case 3:
          return _playlistsViewMode;
        default:
          return 'list';
      }
    } else {
      // Artists, Albums, Playlists
      switch (tabIndex) {
        case 0:
          return _artistsViewMode;
        case 1:
          return _albumsViewMode;
        case 2:
          return _playlistsViewMode;
        default:
          return 'list';
      }
    }
  }

  void _resetCategoryIndex() {
    // Reset to first category when media type changes
    if (_selectedTabIndex.value >= _tabCount) {
      _selectedTabIndex.value = 0;
      _tabIndexNotifier.value = 0;
    }
    // Jump to the selected category without animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_selectedTabIndex.value);
      }
    });
  }

  /// Get the color for a media type - muted colors based on primaryContainer tone
  Color _getMediaTypeColor(ColorScheme colorScheme, LibraryMediaType type) {
    final baseColor = colorScheme.primaryContainer;
    final baseHsl = HSLColor.fromColor(baseColor);

    double hueShift;
    switch (type) {
      case LibraryMediaType.music:
        hueShift = 0; // Keep primary hue (purple-ish)
      case LibraryMediaType.books:
        hueShift = 35; // Shift toward orange
      case LibraryMediaType.podcasts:
        hueShift = 160; // Shift toward teal
      case LibraryMediaType.radio:
        hueShift = -30; // Shift toward pink
    }

    return baseHsl.withHue((baseHsl.hue + hueShift) % 360).toColor();
  }

  void _changeMediaType(LibraryMediaType type, {bool goToLastTab = false}) {
    _logger.log('📚 _changeMediaType called: $type (current: $_selectedMediaType, goToLastTab: $goToLastTab)');
    if (_selectedMediaType == type) {
      _logger.log('📚 Same type, skipping');
      return;
    }

    // Set flag to ignore onPageChanged during transition
    _isChangingMediaType = true;

    setState(() {
      _selectedMediaType = type;
    });

    // Calculate the target tab index based on direction
    final targetIndex = goToLastTab ? _getTabCountForType(type) - 1 : 0;
    _selectedTabIndex.value = targetIndex;
    _tabIndexNotifier.value = targetIndex;

    // Jump to the target page and clear flag after
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetIndex);
      }
      // Clear flag after a short delay to ensure all page change events have fired
      Future.delayed(const Duration(milliseconds: 50), () {
        _isChangingMediaType = false;
      });
    });
    // Load audiobooks when switching to books tab
    if (type == LibraryMediaType.books) {
      _logger.log('📚 Switched to Books, _audiobooks.isEmpty=${_audiobooks.isEmpty}');
      if (_audiobooks.isEmpty) {
        _loadAudiobooks(favoriteOnly: _showFavoritesOnly ? true : null);
      }
      // Load series from Music Assistant
      if (!_seriesLoaded) {
        _loadSeries();
      }
    }
    // Load radio stations when switching to radio tab
    if (type == LibraryMediaType.radio) {
      final maProvider = context.read<MusicAssistantProvider>();
      if (maProvider.radioStations.isEmpty) {
        maProvider.loadRadioStations();
      }
    }
    // Load podcasts when switching to podcasts tab
    if (type == LibraryMediaType.podcasts) {
      final maProvider = context.read<MusicAssistantProvider>();
      if (maProvider.podcasts.isEmpty) {
        maProvider.loadPodcasts();
      }
    }
  }

  void _onPageChanged(int index) {
    // Ignore page changes during media type transitions to avoid race conditions
    if (_isChangingMediaType) return;

    // Update both: RestorableInt for persistence, ValueNotifier for UI
    // No setState needed - ValueListenableBuilder will rebuild only the filter chips
    _selectedTabIndex.value = index;
    _tabIndexNotifier.value = index;
  }

  /// Handle horizontal overscroll to switch between media types
  bool _handleHorizontalOverscroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) {
      return false;
    }

    if (notification is OverscrollNotification) {
      _horizontalOverscroll += notification.overscroll;

      // Check if we've overscrolled enough to switch
      // Positive overscroll = swiping left at the end = go to NEXT type
      // Negative overscroll = swiping right at the start = go to PREVIOUS type
      if (_horizontalOverscroll > _overscrollThreshold) {
        _horizontalOverscroll = 0;
        _switchToNextMediaType();
        return true;
      } else if (_horizontalOverscroll < -_overscrollThreshold) {
        _horizontalOverscroll = 0;
        _switchToPreviousMediaType();
        return true;
      }
    } else if (notification is ScrollEndNotification) {
      // Reset overscroll accumulation when scroll ends
      _horizontalOverscroll = 0;
    }

    return false;
  }

  void _switchToNextMediaType() {
    final types = LibraryMediaType.values;
    final currentIndex = types.indexOf(_selectedMediaType);
    final nextIndex = (currentIndex + 1) % types.length;
    _changeMediaType(types[nextIndex], goToLastTab: false);
  }

  void _switchToPreviousMediaType() {
    final types = LibraryMediaType.values;
    final currentIndex = types.indexOf(_selectedMediaType);
    final prevIndex = (currentIndex - 1 + types.length) % types.length;
    _changeMediaType(types[prevIndex], goToLastTab: true);
  }

  // Drag handlers for single-category types
  void _onHorizontalDragStart(DragStartDetails details) {
    _horizontalDragStart = details.globalPosition.dx;
    _horizontalDragDelta = 0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _horizontalDragDelta = details.globalPosition.dx - _horizontalDragStart;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    // Swipe right (positive delta) = go to previous type
    // Swipe left (negative delta) = go to next type
    if (_horizontalDragDelta > _overscrollThreshold) {
      _switchToPreviousMediaType();
    } else if (_horizontalDragDelta < -_overscrollThreshold) {
      _switchToNextMediaType();
    }
    _horizontalDragDelta = 0;
  }

  /// Handle scroll notifications to hide/show filter bars
  bool _handleScrollNotification(ScrollNotification notification) {
    // Don't hide while dragging letter scrollbar
    if (_isLetterScrollbarDragging) {
      return false;
    }

    // Only respond to vertical scroll (not horizontal PageView swipe)
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final currentOffset = notification.metrics.pixels;
      final delta = currentOffset - _lastScrollOffset;

      if (delta.abs() > _scrollThreshold) {
        final shouldShow = delta < 0 || currentOffset <= 0;
        if (shouldShow != _isFilterBarVisible) {
          setState(() {
            _isFilterBarVisible = shouldShow;
          });
        }
        _lastScrollOffset = currentOffset;
      }
    }
    return false;
  }

  void _onLetterScrollbarDragChanged(bool isDragging) {
    setState(() {
      _isLetterScrollbarDragging = isDragging;
      // Show the filter bar when starting to drag
      if (isDragging) {
        _isFilterBarVisible = true;
      }
    });
  }

  void _animateToCategory(int index) {
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    // Update both for persistence and UI
    _selectedTabIndex.value = index;
    _tabIndexNotifier.value = index;
  }

  @override
  void dispose() {
    _colorExtractionDebounce?.cancel();
    _closeOptionsMenu();
    navigationProvider.removeListener(_onNavigationChanged);
    _pageController.dispose();
    _selectedTabIndex.dispose();
    _tabIndexNotifier.dispose();
    _artistsScrollController.dispose();
    _albumsScrollController.dispose();
    _playlistsScrollController.dispose();
    _tracksScrollController.removeListener(_onTracksScroll);
    _tracksScrollController.dispose();
    _authorsScrollController.dispose();
    _audiobooksScrollController.dispose();
    _seriesScrollController.dispose();
    _podcastsScrollController.dispose();
    _radioScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaylists({bool? favoriteOnly}) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final playlists = await maProvider.getPlaylists(
      limit: 100,
      favoriteOnly: favoriteOnly,
      orderBy: _playlistsSortOrder,
    );
    if (mounted) {
      setState(() {
        _playlists = playlists;
        // Server returns pre-sorted data, but keep client sort for fallback
        _sortPlaylists();
        _isLoadingPlaylists = false;
      });
    }
  }

  /// Update sorted playlists list from server-sorted data
  /// Server handles: name, name_desc, timestamp_added, timestamp_added_desc,
  /// timestamp_modified, timestamp_modified_desc, last_played, last_played_desc, play_count, play_count_desc
  void _sortPlaylists() {
    // Trust server-side sorting - don't re-sort client-side
    _sortedPlaylists = _playlists;
    _playlistNames = _playlists.map((p) => p.name ?? '').toList();
  }

  Future<void> _loadFavoriteTracks() async {
    if (_isLoadingTracks) return;

    setState(() {
      _isLoadingTracks = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final tracks = await maProvider.api!.getTracks(
        limit: 500,
        favoriteOnly: true,
      );
      if (mounted) {
        // PERF: Pre-sort once on load, not on every build
        final sorted = List<Track>.from(tracks)
          ..sort((a, b) {
            final artistCompare = a.artistsString.compareTo(b.artistsString);
            if (artistCompare != 0) return artistCompare;
            return a.name.compareTo(b.name);
          });
        setState(() {
          _favoriteTracks = tracks;
          _sortedFavoriteTracks = sorted;
          _isLoadingTracks = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingTracks = false;
        });
      }
    }
  }

  /// Load all tracks with lazy loading (initial batch)
  Future<void> _loadAllTracks() async {
    if (_isLoadingTracks) return;

    setState(() {
      _isLoadingTracks = true;
      _tracksOffset = 0;
      _hasMoreTracks = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final tracks = await maProvider.api!.getTracks(
        limit: _tracksInitialLoad,
        offset: 0,
        orderBy: _tracksSortOrder,
      );
      if (mounted) {
        setState(() {
          _allTracks = tracks;
          // Server returns pre-sorted data, but keep client sort for fallback
          _sortAllTracks();
          _tracksOffset = tracks.length;
          _hasMoreTracks = tracks.length >= _tracksInitialLoad;
          _isLoadingTracks = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingTracks = false;
        });
      }
    }
  }

  /// Load more tracks when scrolling near bottom
  Future<void> _loadMoreTracks() async {
    if (_isLoadingMoreTracks || !_hasMoreTracks) return;

    setState(() {
      _isLoadingMoreTracks = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final tracks = await maProvider.api!.getTracks(
        limit: _tracksPageSize,
        offset: _tracksOffset,
        orderBy: _tracksSortOrder,
      );
      if (mounted) {
        setState(() {
          _allTracks.addAll(tracks);
          // Server returns pre-sorted data, but keep client sort for fallback
          _sortAllTracks();
          _tracksOffset += tracks.length;
          _hasMoreTracks = tracks.length >= _tracksPageSize;
          _isLoadingMoreTracks = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingMoreTracks = false;
        });
      }
    }
  }

  /// Update sorted tracks list from server-sorted data
  /// Server handles: name, name_desc, duration, duration_desc, timestamp_added, timestamp_added_desc,
  /// last_played, last_played_desc, play_count, play_count_desc
  void _sortAllTracks() {
    // Trust server-side sorting - don't re-sort client-side
    _sortedAllTracks = _allTracks;
    _trackNames = _allTracks.map((t) => t.name).toList();
  }

  final _logger = DebugLogger();

  Future<void> _loadAudiobooks({bool? favoriteOnly}) async {
    _logger.log('📚 _loadAudiobooks called, favoriteOnly=$favoriteOnly');
    if (_isLoadingAudiobooks) {
      _logger.log('📚 Already loading, skipping');
      return;
    }

    setState(() {
      _isLoadingAudiobooks = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    _logger.log('📚 Calling getAudiobooks...');
    final audiobooks = await maProvider.getAudiobooks(
      limit: 10000,  // Large limit to get all audiobooks
      favoriteOnly: favoriteOnly,
    );
    _logger.log('📚 Returned ${audiobooks.length} audiobooks');
    if (audiobooks.isNotEmpty) {
      _logger.log('📚 First audiobook: ${audiobooks.first.name} by ${audiobooks.first.authorsString}');
    }
    if (mounted) {
      // Group audiobooks by author
      final authorMap = <String, List<Audiobook>>{};
      for (final book in audiobooks) {
        final authorName = book.authorsString;
        authorMap.putIfAbsent(authorName, () => []).add(book);
      }
      final sortedAuthors = authorMap.keys.toList()..sort();

      setState(() {
        _audiobooks = audiobooks;
        _groupedAudiobooksByAuthor = authorMap;
        _sortedAuthorNames = sortedAuthors;
        _isLoadingAudiobooks = false;
        // Apply current sort order (respects _audiobooksSortOrder)
        _sortAudiobooks();
      });
      _logger.log('📚 State updated, _audiobooks.length = ${_audiobooks.length}');
      // Fetch author images in background
      _fetchAuthorImages(audiobooks);
    }
  }

  Future<void> _fetchAuthorImages(List<Audiobook> audiobooks) async {
    // Get unique author display strings and their primary author for image lookup
    final authorEntries = <String, String>{}; // displayName -> primaryAuthorName
    for (final book in audiobooks) {
      final displayName = book.authorsString;
      if (!authorEntries.containsKey(displayName)) {
        // Use first author's name for image lookup (API search works better with single names)
        final primaryAuthor = book.authors?.isNotEmpty == true
            ? book.authors!.first.name
            : displayName;
        authorEntries[displayName] = primaryAuthor;
      }
    }

    // Fetch images for authors not already cached
    for (final entry in authorEntries.entries) {
      final displayName = entry.key;
      final lookupName = entry.value;
      if (!_authorImages.containsKey(displayName)) {
        // Mark as loading to avoid duplicate requests
        _authorImages[displayName] = null;
        // Fetch in background using primary author name
        MetadataService.getAuthorImageUrl(lookupName).then((imageUrl) {
          if (mounted && imageUrl != null) {
            setState(() {
              _authorImages[displayName] = imageUrl;
            });
          }
        });
      }
    }
  }

  /// Load audiobook series from Music Assistant
  Future<void> _loadSeries() async {
    if (_isLoadingSeries) return;

    setState(() {
      _isLoadingSeries = true;
    });

    try {
      final maProvider = context.read<MusicAssistantProvider>();
      if (maProvider.api != null) {
        final series = await maProvider.api!.getAudiobookSeries();
        _logger.log('📚 Loaded ${series.length} series');

        if (mounted) {
          // PERF: Pre-sort once on load, not on every build
          final sorted = List<AudiobookSeries>.from(series)
            ..sort((a, b) => a.name.compareTo(b.name));
          setState(() {
            _series = series;
            _sortedSeries = sorted;
            _seriesNames = sorted.map((s) => s.name).toList();
            _isLoadingSeries = false;
            _seriesLoaded = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingSeries = false;
          });
        }
      }
    } catch (e) {
      _logger.log('📚 Error loading series: $e');
      if (mounted) {
        setState(() {
          _isLoadingSeries = false;
        });
      }
    }
  }

  /// Fetch book covers for a series (for 3x3 grid display)
  Future<void> _loadSeriesCovers(String seriesId, MusicAssistantProvider maProvider) async {
    // Already cached or loading
    if (_seriesBookCovers.containsKey(seriesId) || _seriesCoversLoading.contains(seriesId)) {
      return;
    }

    _seriesCoversLoading.add(seriesId);

    try {
      if (maProvider.api != null) {
        final books = await maProvider.api!.getSeriesAudiobooks(seriesId);
        final covers = <String>[];

        for (final book in books.take(9)) {
          final imageUrl = maProvider.getImageUrl(book);
          if (imageUrl != null) {
            covers.add(imageUrl);
          }
        }

        if (mounted) {
          setState(() {
            _seriesBookCovers[seriesId] = covers;
            _seriesBookCounts[seriesId] = books.length;
            _seriesCoversLoading.remove(seriesId);
          });

          // Precache images for smooth hero animations
          _precacheSeriesCovers(covers);

          // PERF: Queue color extraction with debounce to avoid blocking UI during scroll
          _queueColorExtraction(seriesId, covers);
        }
      }
    } catch (e) {
      _logger.log('📚 Error loading series covers for $seriesId: $e');
      _seriesCoversLoading.remove(seriesId);
    }
  }

  /// Precache series cover images for smooth hero animations
  void _precacheSeriesCovers(List<String> covers) {
    if (!mounted) return;
    for (final url in covers) {
      precacheImage(
        CachedNetworkImageProvider(url),
        context,
      ).catchError((_) => false);
    }
  }

  /// PERF: Queue color extraction requests - processed after scroll settles
  void _queueColorExtraction(String seriesId, List<String> coverUrls) {
    if (coverUrls.isEmpty) return;

    // Add to pending queue
    _pendingColorExtractions[seriesId] = coverUrls;

    // Cancel existing timer and start a new one
    _colorExtractionDebounce?.cancel();
    _colorExtractionDebounce = Timer(const Duration(milliseconds: 300), () {
      _processQueuedColorExtractions();
    });
  }

  /// PERF: Process all queued color extractions in batch after scroll settles
  Future<void> _processQueuedColorExtractions() async {
    if (_pendingColorExtractions.isEmpty || !mounted) return;

    // Copy and clear the queue to avoid processing new items added during extraction
    final toProcess = Map<String, List<String>>.from(_pendingColorExtractions);
    _pendingColorExtractions.clear();

    // Process each series sequentially to avoid overwhelming the UI thread
    for (final entry in toProcess.entries) {
      if (!mounted) break;
      await _extractSeriesColors(entry.key, entry.value);
      // Small yield between extractions to keep UI responsive
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Extract dominant colors from series book covers for empty cell backgrounds
  Future<void> _extractSeriesColors(String seriesId, List<String> coverUrls) async {
    if (coverUrls.isEmpty || !mounted) return;

    final extractedColors = <Color>[];

    // Extract colors from first few covers (limit to avoid too much processing)
    for (final url in coverUrls.take(4)) {
      if (!mounted) break;
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          CachedNetworkImageProvider(url),
          maximumColorCount: 8,
        );

        // Get dark muted colors for grid squares (matches the aesthetic)
        if (palette.darkMutedColor != null) {
          extractedColors.add(palette.darkMutedColor!.color);
        }
        if (palette.mutedColor != null) {
          extractedColors.add(palette.mutedColor!.color);
        }
        if (palette.darkVibrantColor != null) {
          extractedColors.add(palette.darkVibrantColor!.color);
        }
        if (palette.dominantColor != null) {
          // Darken the dominant color for better appearance
          final hsl = HSLColor.fromColor(palette.dominantColor!.color);
          extractedColors.add(hsl.withLightness((hsl.lightness * 0.4).clamp(0.1, 0.3)).toColor());
        }
      } catch (e) {
        _logger.log('📚 Error extracting colors from $url: $e');
      }
    }

    if (extractedColors.isNotEmpty && mounted) {
      setState(() {
        _seriesExtractedColors[seriesId] = extractedColors;
      });
    }
  }

  void _toggleFavoritesMode(bool value) {
    setState(() {
      _showFavoritesOnly = value;
    });
    _resetCategoryIndex();
    if (value) {
      _loadPlaylists(favoriteOnly: true);
      _loadFavoriteTracks();
      _loadAudiobooks(favoriteOnly: true);
    } else {
      _loadPlaylists();
      _loadAudiobooks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context)!;

    // Use Selector for targeted rebuilds - only rebuild when connection state changes
    return Selector<MusicAssistantProvider, bool>(
      selector: (_, provider) => provider.isConnected,
      builder: (context, isConnected, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final syncService = SyncService.instance;

        // Show cached data even when not connected (if we have cache)
        // Only show disconnected state if we have no cached data at all
        if (!isConnected && !syncService.hasCache) {
          return Scaffold(
            backgroundColor: colorScheme.background,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(
                l10n.library,
                style: textTheme.titleLarge?.copyWith(
                  color: colorScheme.onBackground,
                  fontWeight: FontWeight.w300,
                ),
              ),
              centerTitle: true,
            ),
            body: DisconnectedState.withSettingsAction(
              context: context,
              onSettings: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: colorScheme.background,
          body: SafeArea(
            child: Column(
              children: [
                // Two-row filter: Row 1 = Media types (hides on scroll), Row 2 = Sub-categories (always visible)
                _buildFilterRows(colorScheme, l10n, showLibraryTypeRow: _isFilterBarVisible),
                // Connecting banner when showing cached data
                // Hide when we have cached players - UI is functional during background reconnect
                if (!isConnected && syncService.hasCache && !context.read<MusicAssistantProvider>().hasCachedPlayers)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: colorScheme.primaryContainer.withOpacity(0.5),
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
                          l10n.connecting,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      // Main scrollable content
                      // For single-category types, wrap with GestureDetector for swipe detection
                      // (PageView with 1 item doesn't generate overscroll)
                      _tabCount == 1
                          ? GestureDetector(
                              onHorizontalDragStart: _onHorizontalDragStart,
                              onHorizontalDragUpdate: _onHorizontalDragUpdate,
                              onHorizontalDragEnd: _onHorizontalDragEnd,
                              child: NotificationListener<ScrollNotification>(
                                onNotification: _handleScrollNotification,
                                child: _buildTabAtIndex(context, l10n, 0),
                              ),
                            )
                          : NotificationListener<ScrollNotification>(
                              onNotification: _handleScrollNotification,
                              // PERF: Use PageView.builder to only build visible tabs
                              // Wrapped with horizontal overscroll detection for media type switching
                              child: NotificationListener<ScrollNotification>(
                                onNotification: _handleHorizontalOverscroll,
                                child: PageView.builder(
                                  controller: _pageController,
                                  onPageChanged: _onPageChanged,
                                  itemCount: _tabCount,
                                  // Faster settling so vertical scroll works sooner after swipe
                                  physics: const _FastPageScrollPhysics(),
                                  itemBuilder: (context, index) => _buildTabAtIndex(context, l10n, index),
                                ),
                              ),
                            ),
                      // Fade gradient at top - content fades as it scrolls under filter bar
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 24,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  colorScheme.background,
                                  colorScheme.background.withOpacity(0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============ FILTER ROWS ============
  // Consistent height for filter rows
  static const double _filterRowHeight = 36.0;

  Widget _buildFilterRows(ColorScheme colorScheme, S l10n, {required bool showLibraryTypeRow}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: Media type chips (hides when scrolling)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: showLibraryTypeRow ? _filterRowHeight : 0,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildMediaTypeChips(colorScheme, l10n),
          ),
        ),
        if (showLibraryTypeRow) const SizedBox(height: 12), // Space between rows
        // Row 2: Sub-category chips (left) + action buttons (right) - always visible
        SizedBox(
          height: _filterRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: category chips - wrapped in ValueListenableBuilder for efficient rebuilds
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _tabIndexNotifier,
                      builder: (context, selectedIndex, _) {
                        return _buildCategoryChips(colorScheme, l10n, selectedIndex);
                      },
                    ),
                  ),
                ),
                // Right: options menu
                _buildLibraryOptionsMenu(colorScheme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaTypeChips(ColorScheme colorScheme, S l10n) {
    String getMediaTypeLabel(LibraryMediaType type) {
      switch (type) {
        case LibraryMediaType.music:
          return l10n.music;
        case LibraryMediaType.books:
          return l10n.audiobooks;
        case LibraryMediaType.podcasts:
          return l10n.podcasts;
        case LibraryMediaType.radio:
          return l10n.radio;
      }
    }

    IconData getMediaTypeIcon(LibraryMediaType type) {
      switch (type) {
        case LibraryMediaType.music:
          return MdiIcons.musicNote;
        case LibraryMediaType.books:
          return MdiIcons.bookOpenPageVariant;
        case LibraryMediaType.podcasts:
          return MdiIcons.podcast;
        case LibraryMediaType.radio:
          return MdiIcons.radio;
      }
    }

    final types = LibraryMediaType.values;

    // Calculate flex values based on label length
    // Longer labels get more space to avoid clipping
    // Base flex of 10 for icon + padding, plus label length
    int getFlexForType(LibraryMediaType type) {
      final label = getMediaTypeLabel(type);
      // Base space for icon/padding + proportional text space
      return 10 + label.length;
    }

    // Pre-calculate flex values and total
    final flexValues = types.map((t) => getFlexForType(t)).toList();
    final totalFlex = flexValues.reduce((a, b) => a + b);
    final selectedIndex = types.indexOf(_selectedMediaType);

    // Horizontal inset for the pill highlight (gap between adjacent tabs)
    const double hInset = 2.0;
    final isFirstTab = selectedIndex == 0;
    final isLastTab = selectedIndex == types.length - 1;

    // Animated sliding highlight with pill shape
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        // Calculate left position for a given tab index
        double getLeftPosition(int index) {
          double left = 0;
          for (int i = 0; i < index; i++) {
            left += (flexValues[i] / totalFlex) * totalWidth;
          }
          return left;
        }

        // Calculate width for a given tab index
        double getTabWidth(int index) {
          return (flexValues[index] / totalFlex) * totalWidth;
        }

        // Calculate highlight position and size based on whether it's at the edge
        // First tab: flush with left edge, gap on right
        // Last tab: gap on left, flush with right edge
        // Middle tabs: gap on both sides
        final leftInset = isFirstTab ? 0.0 : hInset;
        final rightInset = isLastTab ? 0.0 : hInset;
        final highlightLeft = getLeftPosition(selectedIndex) + leftInset;
        final highlightWidth = getTabWidth(selectedIndex) - leftInset - rightInset;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              // Animated sliding highlight (pill shape with full border radius)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: highlightLeft,
                width: highlightWidth,
                top: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: _getMediaTypeColor(colorScheme, _selectedMediaType),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              // Tab buttons row (transparent, on top of highlight)
              Row(
                children: types.asMap().entries.map((entry) {
                  final index = entry.key;
                  final type = entry.value;
                  final isSelected = _selectedMediaType == type;

                  return Expanded(
                    flex: flexValues[index],
                    child: GestureDetector(
                      onTap: () => _changeMediaType(type),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              getMediaTypeIcon(type),
                              size: 18,
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface.withOpacity(0.6),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                getMediaTypeLabel(type),
                                style: TextStyle(
                                  color: isSelected
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurface.withOpacity(0.7),
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============ SORT FUNCTIONALITY ============

  /// Get current sort order based on media type and tab index
  String _getCurrentSortOrder() {
    final tabIndex = _selectedTabIndex.value;
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        switch (tabIndex) {
          case 0: return _artistsSortOrder;
          case 1: return _albumsSortOrder;
          case 2: return _tracksSortOrder;
          case 3: return _playlistsSortOrder;
          default: return 'alpha';
        }
      case LibraryMediaType.books:
        switch (tabIndex) {
          case 0: return _authorsSortOrder;
          case 1: return _audiobooksSortOrder;
          case 2: return _seriesSortOrder;
          default: return 'alpha';
        }
      case LibraryMediaType.radio:
        return _radioSortOrder;
      case LibraryMediaType.podcasts:
        return _podcastsSortOrder;
    }
  }

  /// Set sort order and persist to settings
  Future<void> _setSortOrder(String order) async {
    final tabIndex = _selectedTabIndex.value;
    final maProvider = context.read<MusicAssistantProvider>();

    setState(() {
      switch (_selectedMediaType) {
        case LibraryMediaType.music:
          switch (tabIndex) {
            case 0:
              _artistsSortOrder = order;
              // Artists use server-side sorting - reload will happen below
              break;
            case 1:
              _albumsSortOrder = order;
              // Albums use server-side sorting - reload will happen below
              break;
            case 2:
              _tracksSortOrder = order;
              // Tracks use server-side sorting - reload will happen below
              break;
            case 3:
              _playlistsSortOrder = order;
              // Playlists use server-side sorting - reload will happen below
              break;
          }
          break;
        case LibraryMediaType.books:
          switch (tabIndex) {
            case 0:
              _authorsSortOrder = order;
              // Authors sorted inline in tab builder - setState triggers rebuild
              break;
            case 1:
              _audiobooksSortOrder = order;
              _sortAudiobooks();
              break;
            case 2:
              _seriesSortOrder = order;
              // Series sorted inline in tab builder - setState triggers rebuild
              break;
          }
          break;
        case LibraryMediaType.radio:
          _radioSortOrder = order;
          // Radio uses server-side sorting - reload will happen below
          break;
        case LibraryMediaType.podcasts:
          _podcastsSortOrder = order;
          // Podcasts use server-side sorting - reload will happen below
          break;
      }
    });

    // Trigger server-side reload for sorts that need it
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        switch (tabIndex) {
          case 0: // Artists
            maProvider.loadArtists(orderBy: order);
            break;
          case 1: // Albums
            maProvider.loadAlbums(orderBy: order);
            break;
          case 2: // Tracks
            _loadAllTracks();
            break;
          case 3: // Playlists
            _loadPlaylists(favoriteOnly: _showFavoritesOnly ? true : null);
            break;
        }
        break;
      case LibraryMediaType.radio:
        maProvider.loadRadioStations(orderBy: order);
        break;
      case LibraryMediaType.podcasts:
        maProvider.loadPodcasts(orderBy: order);
        break;
      case LibraryMediaType.books:
        // Books use client-side sorting (no server-side support)
        break;
    }

    // Persist to settings
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        switch (tabIndex) {
          case 0: await SettingsService.setLibraryArtistsSortOrder(order); break;
          case 1: await SettingsService.setLibraryAlbumsSortOrder(order); break;
          case 2: await SettingsService.setLibraryTracksSortOrder(order); break;
          case 3: await SettingsService.setLibraryPlaylistsSortOrder(order); break;
        }
        break;
      case LibraryMediaType.books:
        switch (tabIndex) {
          case 0: await SettingsService.setLibraryAuthorsSortOrder(order); break;
          case 1: await SettingsService.setLibraryAudiobooksSortOrder(order); break;
          case 2: await SettingsService.setLibrarySeriesSortOrder(order); break;
        }
        break;
      case LibraryMediaType.radio:
        await SettingsService.setLibraryRadioSortOrder(order);
        break;
      case LibraryMediaType.podcasts:
        await SettingsService.setLibraryPodcastsSortOrder(order);
        break;
    }
  }

  // Single options menu combining sort, view mode, and favorites filter
  Widget _buildLibraryOptionsMenu(ColorScheme colorScheme) {
    final fadedCircleColor = colorScheme.surfaceVariant.withOpacity(0.6);

    // Touch target meets Material Design 48x48 minimum
    const double buttonSize = ButtonSizes.xl;
    const double iconSize = ButtonSizes.iconXl;

    return SizedBox(
      key: _menuButtonKey,
      width: buttonSize,
      height: buttonSize,
      child: Material(
        color: _showFavoritesOnly ? StatusColors.favorite : fadedCircleColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _showOptionsMenu(colorScheme),
          // Show spinner on button while syncing artists filter
          child: _isSyncingArtists
              ? Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _showFavoritesOnly ? Colors.white : colorScheme.onSurface,
                    ),
                  ),
                )
              : Icon(
                  Icons.more_vert,
                  size: iconSize,
                  color: _showFavoritesOnly ? Colors.white : colorScheme.onSurface,
                ),
        ),
      ),
    );
  }

  /// Show options menu that stays open on sort selection
  void _showOptionsMenu(ColorScheme colorScheme) {
    // Close any existing overlay first
    _closeOptionsMenu();

    final RenderBox? button = _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;

    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero, ancestor: overlay);

    _optionsMenuOverlay = OverlayEntry(
      builder: (context) => _OptionsMenuOverlay(
        position: position,
        buttonSize: button.size,
        colorScheme: colorScheme,
        currentSort: _getCurrentSortOrder(),
        currentViewMode: _getCurrentViewMode(),
        hasViewModes: _currentTabHasViewModes(),
        showFavoritesOnly: _showFavoritesOnly,
        showOnlyArtistsWithAlbums: _showOnlyArtistsWithAlbums,
        selectedMediaType: _selectedMediaType,
        tabIndex: _selectedTabIndex.value,
        sortFields: _getSortFieldsForCurrentTab(),
        parseSortOrder: _parseSortOrder,
        buildSortOrder: _buildSortOrder,
        onSortChanged: (sort) {
          _setSortOrder(sort);
        },
        onViewModeChanged: (mode) {
          _setViewMode(mode);
        },
        onFavoritesToggled: () {
          _toggleFavoritesMode(!_showFavoritesOnly);
        },
        onArtistsFilterToggled: () {
          _toggleArtistsWithAlbumsFilter(!_showOnlyArtistsWithAlbums);
        },
        onDismiss: _closeOptionsMenu,
      ),
    );

    Navigator.of(context).overlay!.insert(_optionsMenuOverlay!);
  }

  /// Toggle the "show only artists with albums" filter
  Future<void> _toggleArtistsWithAlbumsFilter(bool value) async {
    setState(() {
      _showOnlyArtistsWithAlbums = value;
      _isSyncingArtists = true;
    });

    await SettingsService.setShowOnlyArtistsWithAlbums(value);

    // Force sync library to apply the new filter at API level
    if (mounted) {
      await context.read<MusicAssistantProvider>().forceLibrarySync();
      if (mounted) {
        setState(() => _isSyncingArtists = false);
      }
    }
  }

  /// Set view mode directly (instead of cycling)
  Future<void> _setViewMode(String mode) async {
    final tabIndex = _selectedTabIndex.value;

    setState(() {
      switch (_selectedMediaType) {
        case LibraryMediaType.music:
          switch (tabIndex) {
            case 0:
              _artistsViewMode = mode;
              break;
            case 1:
              _albumsViewMode = mode;
              break;
            case 2:
              // Tracks - no view mode
              break;
            case 3:
              _playlistsViewMode = mode;
              break;
          }
          break;
        case LibraryMediaType.books:
          switch (tabIndex) {
            case 0:
              _authorsViewMode = mode;
              break;
            case 1:
              _audiobooksViewMode = mode;
              break;
            case 2:
              _seriesViewMode = mode;
              break;
          }
          break;
        case LibraryMediaType.radio:
          _radioViewMode = mode;
          break;
        case LibraryMediaType.podcasts:
          _podcastsViewMode = mode;
          break;
      }
    });

    // Persist to settings
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        switch (tabIndex) {
          case 0: await SettingsService.setLibraryArtistsViewMode(mode); break;
          case 1: await SettingsService.setLibraryAlbumsViewMode(mode); break;
          case 2: break; // Tracks - no view mode
          case 3: await SettingsService.setLibraryPlaylistsViewMode(mode); break;
        }
        break;
      case LibraryMediaType.books:
        switch (tabIndex) {
          case 0: await SettingsService.setLibraryAuthorsViewMode(mode); break;
          case 1: await SettingsService.setLibraryAudiobooksViewMode(mode); break;
          case 2: await SettingsService.setLibrarySeriesViewMode(mode); break;
        }
        break;
      case LibraryMediaType.radio:
        await SettingsService.setLibraryRadioViewMode(mode);
        break;
      case LibraryMediaType.podcasts:
        await SettingsService.setLibraryPodcastsViewMode(mode);
        break;
    }
  }

  /// Check if current tab supports multiple view modes
  bool _currentTabHasViewModes() {
    // Tracks tab (Music index 2) only has list view
    if (_selectedMediaType == LibraryMediaType.music && _selectedTabIndex.value == 2) {
      return false;
    }
    return true;
  }

  /// Parse a sort order into base field and direction
  /// e.g., "name_desc" -> ("name", true), "name" -> ("name", false)
  (String baseField, bool isDescending) _parseSortOrder(String sortOrder) {
    if (sortOrder.endsWith('_desc')) {
      return (sortOrder.substring(0, sortOrder.length - 5), true);
    }
    return (sortOrder, false);
  }

  /// Build a sort order string from base field and direction
  String _buildSortOrder(String baseField, bool descending) {
    return descending ? '${baseField}_desc' : baseField;
  }

  /// Get sort field configurations for the current tab
  /// Returns list of (baseField, label, icon, defaultDescending)
  List<(String, String, IconData, bool)> _getSortFieldsForCurrentTab() {
    final tabIndex = _selectedTabIndex.value;

    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        switch (tabIndex) {
          case 0: // Artists
            return [
              ('name', 'Name', Icons.sort_by_alpha, false),
              ('timestamp_added', 'Date Added', Icons.schedule, true),
              ('last_played', 'Last Played', Icons.play_circle_outline, true),
              ('play_count', 'Play Count', Icons.trending_up, true),
            ];
          case 1: // Albums
            return [
              ('name', 'Name', Icons.sort_by_alpha, false),
              ('year', 'Year', Icons.calendar_today, true),
              ('artist_name', 'Artist', Icons.person, false),
              ('timestamp_added', 'Date Added', Icons.schedule, true),
              ('last_played', 'Last Played', Icons.play_circle_outline, true),
              ('play_count', 'Play Count', Icons.trending_up, true),
            ];
          case 2: // Tracks
            return [
              ('name', 'Name', Icons.sort_by_alpha, false),
              ('duration', 'Duration', Icons.timer, false),
              ('timestamp_added', 'Date Added', Icons.schedule, true),
              ('last_played', 'Last Played', Icons.play_circle_outline, true),
              ('play_count', 'Play Count', Icons.trending_up, true),
            ];
          case 3: // Playlists
            return [
              ('name', 'Name', Icons.sort_by_alpha, false),
              ('timestamp_added', 'Date Added', Icons.schedule, true),
              ('timestamp_modified', 'Modified', Icons.edit, true),
              ('last_played', 'Last Played', Icons.play_circle_outline, true),
              ('play_count', 'Play Count', Icons.trending_up, true),
            ];
          default:
            return [];
        }
      case LibraryMediaType.books:
        switch (tabIndex) {
          case 0: // Authors
            return [
              ('alpha', 'Name', Icons.sort_by_alpha, false),
              ('books', 'Book Count', Icons.format_list_numbered, true),
            ];
          case 1: // All Books
            return [
              ('alpha', 'Name', Icons.sort_by_alpha, false),
              ('year', 'Year', Icons.calendar_today, true),
            ];
          case 2: // Series
            return [
              ('alpha', 'Name', Icons.sort_by_alpha, false),
              ('books', 'Book Count', Icons.format_list_numbered, true),
            ];
          default:
            return [];
        }
      case LibraryMediaType.radio:
        return [
          ('name', 'Name', Icons.sort_by_alpha, false),
          ('timestamp_added', 'Date Added', Icons.schedule, true),
          ('last_played', 'Last Played', Icons.play_circle_outline, true),
          ('play_count', 'Play Count', Icons.trending_up, true),
        ];
      case LibraryMediaType.podcasts:
        return [
          ('name', 'Name', Icons.sort_by_alpha, false),
          ('timestamp_added', 'Date Added', Icons.schedule, true),
          ('last_played', 'Last Played', Icons.play_circle_outline, true),
          ('play_count', 'Play Count', Icons.trending_up, true),
        ];
    }
  }

  Widget _buildCategoryChips(ColorScheme colorScheme, S l10n, int selectedIndex) {
    final categories = _getCategoryLabels(l10n);

    // Fixed horizontal padding around each label (consistent spacing)
    const double hPadding = 12.0;
    const double hInset = 2.0;

    // Measure actual text widths using TextPainter
    final textStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    final labelWidths = categories.map((label) {
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      return textPainter.width + (hPadding * 2); // text width + padding on both sides
    }).toList();
    final totalWidth = labelWidths.reduce((a, b) => a + b);

    // Calculate left position for a given index
    double getLeftPosition(int index) {
      double left = 0;
      for (int i = 0; i < index; i++) {
        left += labelWidths[i];
      }
      return left;
    }

    final isFirstTab = selectedIndex == 0;
    final isLastTab = selectedIndex == categories.length - 1;
    final leftInset = isFirstTab ? 0.0 : hInset;
    final rightInset = isLastTab ? 0.0 : hInset;
    final highlightLeft = getLeftPosition(selectedIndex) + leftInset;
    final highlightWidth = labelWidths[selectedIndex] - leftInset - rightInset;

    return Container(
      width: totalWidth,
      height: _filterRowHeight,
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // Animated sliding highlight
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            left: highlightLeft,
            width: highlightWidth,
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: _getMediaTypeColor(colorScheme, _selectedMediaType),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          // Labels row
          Row(
            children: categories.asMap().entries.map((entry) {
              final index = entry.key;
              final label = entry.value;
              final isSelected = selectedIndex == index;

              return SizedBox(
                width: labelWidths[index],
                child: GestureDetector(
                  onTap: () => _animateToCategory(index),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant.withOpacity(0.8),
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  List<String> _getCategoryLabels(S l10n) {
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        return [
          l10n.artists,
          l10n.albums,
          l10n.tracks, // Always visible now
          l10n.playlists,
        ];
      case LibraryMediaType.books:
        return [
          l10n.authors,
          l10n.books,
          l10n.series,
        ];
      case LibraryMediaType.podcasts:
        return [l10n.shows];
      case LibraryMediaType.radio:
        return [l10n.stations];
    }
  }

  // ============ PAGE VIEWS ============
  /// PERF: Build only the requested tab (for PageView.builder)
  Widget _buildTabAtIndex(BuildContext context, S l10n, int index) {
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        // Always 4 tabs: Artists, Albums, Tracks, Playlists
        switch (index) {
          case 0: return _buildArtistsTab(context, l10n);
          case 1: return _buildAlbumsTab(context, l10n);
          case 2: return _buildTracksTab(context, l10n);
          case 3: return _buildPlaylistsTab(context, l10n);
          default: return const SizedBox();
        }
      case LibraryMediaType.books:
        switch (index) {
          case 0: return _buildBooksAuthorsTab(context, l10n);
          case 1: return _buildAllBooksTab(context, l10n);
          case 2: return _buildSeriesTab(context, l10n);
          default: return const SizedBox();
        }
      case LibraryMediaType.podcasts:
        return _buildPodcastsTab(context, l10n);
      case LibraryMediaType.radio:
        return _buildRadioStationsTab(context, l10n);
    }
  }

  // ============ BOOKS TABS ============
  Widget _buildBooksAuthorsTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingAudiobooks) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    // Filter by favorites if enabled
    final audiobooks = _showFavoritesOnly
        ? _audiobooks.where((a) => a.favorite == true).toList()
        : _audiobooks;

    if (audiobooks.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          context: context,
          icon: Icons.favorite_border,
          title: l10n.noFavoriteAudiobooks,
          subtitle: l10n.tapHeartAudiobook,
        );
      }
      return EmptyState.custom(
        context: context,
        icon: MdiIcons.bookOutline,
        title: l10n.noAudiobooks,
        subtitle: l10n.addAudiobooksHint,
        onRefresh: () => _loadAudiobooks(),
      );
    }

    // Sort authors based on current sort order
    final sortedAuthorNames = List<String>.from(_sortedAuthorNames);
    switch (_authorsSortOrder) {
      case 'alpha':
        sortedAuthorNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        break;
      case 'alpha_desc':
        sortedAuthorNames.sort((a, b) => b.toLowerCase().compareTo(a.toLowerCase()));
        break;
      case 'books':
        sortedAuthorNames.sort((a, b) {
          final aCount = _groupedAudiobooksByAuthor[a]?.length ?? 0;
          final bCount = _groupedAudiobooksByAuthor[b]?.length ?? 0;
          if (bCount != aCount) return bCount.compareTo(aCount);
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
        break;
    }

    // Match music artists tab layout - no header, direct list/grid
    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.background,
      onRefresh: () => _loadAudiobooks(favoriteOnly: _showFavoritesOnly ? true : null),
      child: LetterScrollbar(
        controller: _authorsScrollController,
        items: sortedAuthorNames,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        bottomPadding: BottomSpacing.withMiniPlayer,
        child: _authorsViewMode == 'list'
            ? ListView.builder(
                controller: _authorsScrollController,
                key: const PageStorageKey<String>('books_authors_list'),
                cacheExtent: 1000,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                itemCount: sortedAuthorNames.length,
                padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
                itemBuilder: (context, index) {
                  final authorName = sortedAuthorNames[index];
                  return _buildAuthorListTile(authorName, _groupedAudiobooksByAuthor[authorName]!, l10n);
                },
              )
            : GridView.builder(
                controller: _authorsScrollController,
                key: const PageStorageKey<String>('books_authors_grid'),
                cacheExtent: 1000,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _authorsViewMode == 'grid3' ? 3 : 2,
                  childAspectRatio: _authorsViewMode == 'grid3' ? 0.75 : 0.80, // Match music artists
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: sortedAuthorNames.length,
                itemBuilder: (context, index) {
                  final authorName = sortedAuthorNames[index];
                  return _buildAuthorCard(authorName, _groupedAudiobooksByAuthor[authorName]!, l10n);
                },
              ),
      ),
    );
  }

  Widget _buildAuthorListTile(String authorName, List<Audiobook> books, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final authorImageUrl = _authorImages[authorName];
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Hero(
        tag: HeroTags.authorImage + authorName + '_library$heroSuffix',
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Icon always present underneath
              Icon(
                Icons.person_rounded,
                color: colorScheme.onPrimaryContainer,
                size: 28,
              ),
              // Image covers icon when loaded
              if (authorImageUrl != null)
                ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: authorImageUrl,
                    fit: BoxFit.cover,
                    width: 48,
                    height: 48,
                    // Only set width - height scales proportionally to preserve aspect ratio
                    memCacheWidth: 128,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    // Transparent placeholder - icon shows through
                    placeholder: (_, __) => const SizedBox.shrink(),
                    // On error, shrink to show icon underneath
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      ),
      title: Text(
        authorName,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${books.length} ${books.length == 1 ? l10n.audiobookSingular : l10n.audiobooks}',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      onTap: () => _navigateToAuthor(authorName, books, heroTagSuffix: 'library$heroSuffix', initialAuthorImageUrl: authorImageUrl),
    );
  }

  Widget _buildAuthorCard(String authorName, List<Audiobook> books, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final authorImageUrl = _authorImages[authorName];
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';
    final iconSize = _authorsViewMode == 'grid3' ? 36.0 : 48.0;

    // Match music artist card layout
    return GestureDetector(
      onTap: () => _navigateToAuthor(authorName, books, heroTagSuffix: 'library$heroSuffix', initialAuthorImageUrl: authorImageUrl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Use LayoutBuilder to ensure proper circle (like music artists)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Use the smaller dimension to ensure a circle
                final size = constraints.maxWidth < constraints.maxHeight
                    ? constraints.maxWidth
                    : constraints.maxHeight;
                return Center(
                  child: Hero(
                    tag: HeroTags.authorImage + authorName + '_library$heroSuffix',
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Icon always present underneath
                          Icon(
                            Icons.person_rounded,
                            color: colorScheme.onPrimaryContainer,
                            size: iconSize,
                          ),
                          // Image covers icon when loaded
                          if (authorImageUrl != null)
                            SizedBox(
                              width: size,
                              height: size,
                              child: ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: authorImageUrl,
                                  fit: BoxFit.cover,
                                  width: size,
                                  height: size,
                                  // Only set width - height scales proportionally to preserve aspect ratio
                                  memCacheWidth: 256,
                                  fadeInDuration: Duration.zero,
                                  fadeOutDuration: Duration.zero,
                                  // Transparent placeholder - icon shows through
                                  placeholder: (_, __) => const SizedBox.shrink(),
                                  // On error, shrink to show icon underneath
                                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Spacing.vGap8,
          Text(
            authorName,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _navigateToAuthor(String authorName, List<Audiobook> books, {String? heroTagSuffix, String? initialAuthorImageUrl}) {
    updateAdaptiveColorsFromImage(context, initialAuthorImageUrl);
    Navigator.push(
      context,
      FadeSlidePageRoute(
        child: AudiobookAuthorScreen(
          authorName: authorName,
          audiobooks: books,
          heroTagSuffix: heroTagSuffix,
          initialAuthorImageUrl: initialAuthorImageUrl,
        ),
      ),
    );
  }

  Widget _buildAudiobookListTile(BuildContext context, Audiobook book, MusicAssistantProvider maProvider) {
    final imageUrl = maProvider.getImageUrl(book, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Hero(
        tag: HeroTags.audiobookCover + (book.uri ?? book.itemId) + '_library$heroSuffix',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 56,
            height: 56,
            color: colorScheme.surfaceContainerHighest,
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 256,
                    memCacheHeight: 256,
                    placeholder: (_, __) => const SizedBox(),
                    errorWidget: (_, __, ___) => Icon(
                      MdiIcons.bookOutline,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    MdiIcons.bookOutline,
                    color: colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      ),
      title: Hero(
        tag: HeroTags.audiobookTitle + (book.uri ?? book.itemId) + '_library$heroSuffix',
        child: Material(
          color: Colors.transparent,
          child: Text(
            book.name,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      subtitle: Text(
        book.authorsString,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: book.progress > 0
          ? SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: book.progress,
                strokeWidth: 3,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
            )
          : null,
      onTap: () => _navigateToAudiobook(book, heroTagSuffix: 'library$heroSuffix', initialImageUrl: imageUrl),
    );
  }

  void _navigateToAudiobook(Audiobook book, {String? heroTagSuffix, String? initialImageUrl}) {
    updateAdaptiveColorsFromImage(context, initialImageUrl);
    Navigator.push(
      context,
      FadeSlidePageRoute(
        child: AudiobookDetailScreen(
          audiobook: book,
          heroTagSuffix: heroTagSuffix,
          initialImageUrl: initialImageUrl,
        ),
      ),
    );
  }

  Widget _buildAllBooksTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final maProvider = context.read<MusicAssistantProvider>();

    if (_isLoadingAudiobooks) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    // Filter by favorites if enabled
    var audiobooks = _showFavoritesOnly
        ? _audiobooks.where((a) => a.favorite == true).toList()
        : List<Audiobook>.from(_audiobooks);

    if (audiobooks.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          context: context,
          icon: Icons.favorite_border,
          title: l10n.noFavoriteAudiobooks,
          subtitle: l10n.tapHeartAudiobook,
        );
      }
      return EmptyState.custom(
        context: context,
        icon: MdiIcons.bookOutline,
        title: l10n.noAudiobooks,
        subtitle: l10n.addAudiobooksHint,
        onRefresh: () => _loadAudiobooks(),
      );
    }

    // PERF: Use pre-sorted list (sorted once on load or when sort order changes)
    // Match music albums tab layout - no header, direct list/grid
    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.background,
      onRefresh: () => _loadAudiobooks(favoriteOnly: _showFavoritesOnly ? true : null),
      child: LetterScrollbar(
        controller: _audiobooksScrollController,
        items: _audiobookNames,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        bottomPadding: BottomSpacing.withMiniPlayer,
        child: _audiobooksViewMode == 'list'
            ? ListView.builder(
                controller: _audiobooksScrollController,
                key: PageStorageKey<String>('all_books_list_${_showFavoritesOnly ? 'fav' : 'all'}'),
                cacheExtent: 1000,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                itemCount: _sortedAudiobooks.length,
                padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
                itemBuilder: (context, index) {
                  return _buildAudiobookListTile(context, _sortedAudiobooks[index], maProvider);
                },
              )
            : GridView.builder(
                controller: _audiobooksScrollController,
                key: PageStorageKey<String>('all_books_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_audiobooksViewMode'),
                cacheExtent: 1000,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _audiobooksViewMode == 'grid3' ? 3 : 2,
                  childAspectRatio: _audiobooksViewMode == 'grid3' ? 0.70 : 0.75, // Match music albums
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _sortedAudiobooks.length,
                itemBuilder: (context, index) {
                  return _buildAudiobookCard(context, _sortedAudiobooks[index], maProvider);
                },
              ),
      ),
    );
  }

  Widget _buildAudiobookCard(BuildContext context, Audiobook book, MusicAssistantProvider maProvider) {
    final imageUrl = maProvider.getImageUrl(book, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    return GestureDetector(
      onTap: () => _navigateToAudiobook(book, heroTagSuffix: 'library$heroSuffix', initialImageUrl: imageUrl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Square artwork with progress inside
          AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              children: [
                Hero(
                  tag: HeroTags.audiobookCover + (book.uri ?? book.itemId) + '_library$heroSuffix',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: colorScheme.surfaceVariant,
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 512,
                              memCacheHeight: 512,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, __) => const SizedBox(),
                              errorWidget: (_, __, ___) => Center(
                                child: Icon(
                                  MdiIcons.bookOutline,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                MdiIcons.bookOutline,
                                size: 48,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                ),
                // Progress indicator overlay inside artwork
                if (book.progress > 0)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: book.progress,
                        backgroundColor: Colors.black38,
                        color: colorScheme.primary,
                        minHeight: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Spacing.vGap8,
          Hero(
            tag: HeroTags.audiobookTitle + (book.uri ?? book.itemId) + '_library$heroSuffix',
            child: Material(
              color: Colors.transparent,
              child: Text(
                book.name,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            book.authorsString,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();

    // Loading state
    if (_isLoadingSeries) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.loading,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Empty state
    if (_series.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadSeries,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.collections_bookmark_rounded,
                        size: 64,
                        color: colorScheme.primary.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.noSeriesFound,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Spacing.vGap8,
                      Text(
                        _seriesLoaded
                            ? l10n.noSeriesAvailable
                            : l10n.pullToLoadSeries,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.tonal(
                        onPressed: _loadSeries,
                        child: Text(l10n.loadSeries),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Sort series based on current sort order
    final sortedSeries = List<AudiobookSeries>.from(_sortedSeries);
    switch (_seriesSortOrder) {
      case 'alpha':
        sortedSeries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'alpha_desc':
        sortedSeries.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case 'books':
        sortedSeries.sort((a, b) {
          // Use cached book count if available, fallback to model's bookCount
          final aCount = _seriesBookCounts[a.id] ?? a.bookCount ?? 0;
          final bCount = _seriesBookCounts[b.id] ?? b.bookCount ?? 0;
          if (bCount != aCount) return bCount.compareTo(aCount);
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
    }
    final seriesNames = sortedSeries.map((s) => s.name).toList();

    // Series view - supports grid2, grid3, and list modes
    return RefreshIndicator(
      onRefresh: _loadSeries,
      child: LetterScrollbar(
        controller: _seriesScrollController,
        items: seriesNames,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        bottomPadding: BottomSpacing.withMiniPlayer,
        child: _seriesViewMode == 'list'
            ? ListView.builder(
                controller: _seriesScrollController,
                key: const PageStorageKey<String>('series_list'),
                cacheExtent: 1000,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                itemCount: sortedSeries.length,
                padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
                itemBuilder: (context, index) {
                  return _buildSeriesListTile(context, sortedSeries[index], maProvider, l10n);
                },
              )
            : GridView.builder(
                controller: _seriesScrollController,
                key: PageStorageKey<String>('series_grid_$_seriesViewMode'),
                padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _seriesViewMode == 'grid3' ? 3 : 2,
                  childAspectRatio: _seriesViewMode == 'grid3' ? 0.70 : 0.75,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: sortedSeries.length,
                itemBuilder: (context, index) {
                  final series = sortedSeries[index];
                  return _buildSeriesCard(context, series, maProvider, l10n, maxCoverGridSize: _seriesViewMode == 'grid3' ? 2 : 3);
                },
              ),
      ),
    );
  }

  Widget _buildSeriesListTile(BuildContext context, AudiobookSeries series, MusicAssistantProvider maProvider, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Trigger loading of series covers if not cached
    if (!_seriesBookCovers.containsKey(series.id) && !_seriesCoversLoading.contains(series.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSeriesCovers(series.id, maProvider);
      });
    }

    final covers = _seriesBookCovers[series.id];
    final firstCover = covers != null && covers.isNotEmpty ? covers.first : null;
    final heroTag = 'series_cover_${series.id}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 56,
            height: 56,
            color: colorScheme.surfaceContainerHighest,
            child: firstCover != null
                ? CachedNetworkImage(
                    imageUrl: firstCover,
                    fit: BoxFit.cover,
                    memCacheWidth: 256,
                    memCacheHeight: 256,
                    placeholder: (_, __) => Icon(
                      Icons.collections_bookmark_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    errorWidget: (_, __, ___) => Icon(
                      Icons.collections_bookmark_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    Icons.collections_bookmark_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      ),
      title: Text(
        series.name,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Builder(
        builder: (context) {
          final count = series.bookCount ?? _seriesBookCounts[series.id];
          if (count == null) return const SizedBox.shrink();
          return Text(
            '$count ${count == 1 ? l10n.book : l10n.books}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          );
        },
      ),
      onTap: () {
        _logger.log('📚 Tapped series: ${series.name}, path: ${series.id}');
        updateAdaptiveColorsFromImage(context, firstCover);
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: AudiobookSeriesScreen(
              series: series,
              heroTag: heroTag,
              initialCovers: covers,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeriesCard(BuildContext context, AudiobookSeries series, MusicAssistantProvider maProvider, S l10n, {int maxCoverGridSize = 3}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Trigger loading of series covers if not cached
    if (!_seriesBookCovers.containsKey(series.id) && !_seriesCoversLoading.contains(series.id)) {
      // Use addPostFrameCallback to avoid calling setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSeriesCovers(series.id, maProvider);
      });
    }

    // Matches books tab style - square artwork with text below
    final heroTag = 'series_cover_${series.id}';
    final cachedCovers = _seriesBookCovers[series.id];
    return GestureDetector(
      onTap: () {
        _logger.log('📚 Tapped series: ${series.name}, path: ${series.id}');
        updateAdaptiveColorsFromImage(context, cachedCovers?.firstOrNull);
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: AudiobookSeriesScreen(
              series: series,
              heroTag: heroTag,
              initialCovers: cachedCovers,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Square cover grid with Hero animation
          Hero(
            tag: heroTag,
            // RepaintBoundary caches the rendered grid for smooth animation
            child: RepaintBoundary(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12), // Match detail screen
                  child: Container(
                    color: colorScheme.surfaceVariant,
                    child: _buildSeriesCoverGrid(series, colorScheme, maProvider, maxGridSize: maxCoverGridSize),
                  ),
                ),
              ),
            ),
          ),
          Spacing.vGap8,
          Text(
            series.name,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Builder(
            builder: (context) {
              final count = series.bookCount ?? _seriesBookCounts[series.id];
              if (count == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '$count ${count == 1 ? l10n.book : l10n.books}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesCoverGrid(AudiobookSeries series, ColorScheme colorScheme, MusicAssistantProvider maProvider, {int maxGridSize = 3}) {
    final covers = _seriesBookCovers[series.id];
    final isLoading = _seriesCoversLoading.contains(series.id);

    // If we have covers, show the grid
    if (covers != null && covers.isNotEmpty) {
      // Determine grid size based on number of covers
      // 1 cover = 1x1, 2-4 covers = 2x2, 5+ covers = 3x3
      int gridSize;
      if (covers.length == 1) {
        gridSize = 1;
      } else if (covers.length <= 4) {
        gridSize = 2;
      } else {
        gridSize = 3;
      }
      // Respect maxGridSize parameter (for smaller displays like 3-column grid)
      gridSize = gridSize.clamp(1, maxGridSize);
      final displayCovers = covers.take(gridSize * gridSize).toList();

      // Use extracted colors from book covers if available, otherwise fall back to static palette
      final extractedColors = _seriesExtractedColors[series.id];
      const fallbackColors = [
        Color(0xFF2D3436), // Dark slate
        Color(0xFF34495E), // Dark blue-grey
        Color(0xFF4A3728), // Dark brown
        Color(0xFF2C3E50), // Midnight blue
        Color(0xFF3D3D3D), // Charcoal
        Color(0xFF4A4458), // Dark purple-grey
        Color(0xFF3E4A47), // Dark teal-grey
        Color(0xFF4A3F35), // Dark warm grey
      ];
      final emptyColors = (extractedColors != null && extractedColors.isNotEmpty)
          ? extractedColors
          : fallbackColors;

      // Use series ID to pick consistent colors for this series
      final colorSeed = series.id.hashCode;

      // Use simple Column/Row layout instead of GridView to avoid scroll-related animations
      // No margins between cells for seamless appearance
      return Column(
        children: List.generate(gridSize, (row) {
          return Expanded(
            child: Row(
              children: List.generate(gridSize, (col) {
                final index = row * gridSize + col;
                if (index >= displayCovers.length) {
                  // Empty cell - use nested grid pattern
                  return Expanded(
                    child: _buildEmptyCell(colorSeed, index, emptyColors),
                  );
                }
                return Expanded(
                  child: CachedNetworkImage(
                    imageUrl: displayCovers[index],
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, __) => Container(
                      color: colorScheme.surfaceContainerHighest,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.book,
                        color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                        size: 20,
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      );
    }

    // Show loading shimmer or placeholder
    if (isLoading) {
      return _buildSeriesLoadingGrid(colorScheme);
    }

    // Fallback placeholder
    return _buildSeriesPlaceholder(colorScheme);
  }

  Widget _buildSeriesLoadingGrid(ColorScheme colorScheme) {
    // Static placeholder grid using Column/Row - no animations, no grid lines
    return Container(
      color: colorScheme.surfaceContainerHighest,
    );
  }

  Widget _buildSeriesPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.collections_bookmark_rounded,
        size: 48,
        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
      ),
    );
  }

  /// Builds an empty cell with either a solid color or a nested grid
  /// The pattern is deterministic based on series ID and cell index
  Widget _buildEmptyCell(int colorSeed, int cellIndex, List<Color> emptyColors) {
    // Tone down colors - reduce saturation and darken
    final colors = emptyColors.map((c) {
      final hsl = HSLColor.fromColor(c);
      return hsl
          .withSaturation((hsl.saturation * 0.5).clamp(0.05, 0.25))
          .withLightness((hsl.lightness * 0.7).clamp(0.08, 0.20))
          .toColor();
    }).toList();

    // Use combined seed for deterministic but varied patterns
    final seed = colorSeed + cellIndex * 17; // Prime multiplier for better distribution

    // Determine nested grid size: 1 (solid), 2 (2x2), or 3 (3x3)
    // Distribution: ~50% solid, ~30% 2x2, ~20% 3x3
    final sizeRoll = seed.abs() % 100;
    int nestedSize;
    if (sizeRoll < 50) {
      nestedSize = 1; // Solid color
    } else if (sizeRoll < 80) {
      nestedSize = 2; // 2x2 grid
    } else {
      nestedSize = 3; // 3x3 grid
    }

    if (nestedSize == 1) {
      // Solid color
      final colorIndex = seed.abs() % colors.length;
      return Container(color: colors[colorIndex]);
    }

    // Build nested grid (no margins - seamless)
    return Column(
      children: List.generate(nestedSize, (row) {
        return Expanded(
          child: Row(
            children: List.generate(nestedSize, (col) {
              final nestedIndex = row * nestedSize + col;
              // Use different seed for each nested cell
              final nestedSeed = seed + nestedIndex * 7;
              final colorIndex = nestedSeed.abs() % colors.length;
              return Expanded(
                child: Container(color: colors[colorIndex]),
              );
            }),
          ),
        );
      }),
    );
  }

  // ============ PODCASTS TAB ============
  Widget _buildPodcastsTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // PERF: Use select() to only rebuild when podcasts or loading state changes
    final (allPodcasts, isLoading) = context.select<MusicAssistantProvider, (List<MediaItem>, bool)>(
      (p) => (p.podcasts, p.isLoadingPodcasts),
    );
    // Use read() for methods that don't need reactive updates
    final maProvider = context.read<MusicAssistantProvider>();

    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    // Filter by favorites if enabled
    final podcasts = _showFavoritesOnly
        ? allPodcasts.where((p) => p.favorite == true).toList()
        : allPodcasts;

    if (podcasts.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          context: context,
          icon: Icons.favorite_border,
          title: l10n.noFavoritePodcasts,
          subtitle: l10n.longPressPodcastHint,
        );
      }
      return EmptyState.custom(
        context: context,
        icon: MdiIcons.podcast,
        title: l10n.noPodcasts,
        subtitle: l10n.addPodcastsHint,
        onRefresh: () => maProvider.loadPodcasts(),
      );
    }

    // Trust server-side sorting - don't re-sort client-side
    // Server handles: name, name_desc, timestamp_added_desc, last_played_desc, play_count_desc
    final sortedPodcasts = podcasts;

    // Pre-cache podcast images for smooth hero animations
    _precachePodcastImages(sortedPodcasts, maProvider);

    // PERF: Request larger images from API but decode at appropriate size for memory
    // Use consistent 256 for all views to improve hero animation smoothness (matches detail screen)
    const cacheSize = 256;

    // Generate podcast names for letter scrollbar
    final podcastNames = sortedPodcasts.map((p) => p.name).toList();

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.background,
      onRefresh: () => maProvider.loadPodcasts(),
      child: LetterScrollbar(
        controller: _podcastsScrollController,
        items: podcastNames,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        bottomPadding: BottomSpacing.withMiniPlayer,
        child: _podcastsViewMode == 'list'
          ? ListView.builder(
              controller: _podcastsScrollController,
              key: const PageStorageKey<String>('podcasts_list'),
              cacheExtent: 1000,
              padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
              itemCount: sortedPodcasts.length,
              itemBuilder: (context, index) {
                final podcast = sortedPodcasts[index];
                // iTunes URL from persisted cache (loaded on app start for instant high-res)
                final imageUrl = maProvider.getPodcastImageUrl(podcast);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Hero(
                    tag: HeroTags.podcastCover + (podcast.uri ?? podcast.itemId) + '_library',
                    // Match detail screen: ClipRRect(16) → Container → CachedNetworkImage
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 56,
                        height: 56,
                        color: colorScheme.surfaceContainerHighest,
                        child: imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                // FIXED: Add memCacheWidth to ensure consistent decode size for smooth Hero
                                memCacheWidth: 256,
                                memCacheHeight: 256,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, __) => const SizedBox(),
                                errorWidget: (_, __, ___) => Icon(
                                  MdiIcons.podcast,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              )
                            : Icon(
                                MdiIcons.podcast,
                                color: colorScheme.onSurfaceVariant,
                              ),
                      ),
                    ),
                  ),
                  title: Text(
                    podcast.name,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: podcast.metadata?['author'] != null
                      ? Text(
                          podcast.metadata!['author'] as String,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () => _openPodcastDetails(podcast, maProvider, imageUrl),
                );
              },
            )
          : GridView.builder(
              controller: _podcastsScrollController,
              key: PageStorageKey<String>('podcasts_grid_$_podcastsViewMode'),
              cacheExtent: 1000,
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _podcastsViewMode == 'grid3' ? 3 : 2,
                childAspectRatio: _podcastsViewMode == 'grid3' ? 0.75 : 0.80,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: sortedPodcasts.length,
              itemBuilder: (context, index) {
                final podcast = sortedPodcasts[index];
                return _buildPodcastCard(podcast, maProvider, cacheSize);
              },
            ),
      ),
    );
  }

  Widget _buildPodcastCard(MediaItem podcast, MusicAssistantProvider maProvider, int cacheSize) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // iTunes URL from persisted cache (loaded on app start for instant high-res)
    final imageUrl = maProvider.getPodcastImageUrl(podcast);

    return GestureDetector(
      onTap: () => _openPodcastDetails(podcast, maProvider, imageUrl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Hero(
              tag: HeroTags.podcastCover + (podcast.uri ?? podcast.itemId) + '_library',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                // Match detail screen structure exactly
                child: Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          // FIXED: Add memCacheWidth to ensure consistent decode size for smooth Hero
                          memCacheWidth: 256,
                          memCacheHeight: 256,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholder: (_, __) => const SizedBox(),
                          errorWidget: (_, __, ___) => Center(
                            child: Icon(
                              MdiIcons.podcast,
                              size: 48,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            MdiIcons.podcast,
                            size: 48,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
            ),
          ),
          Spacing.vGap8,
          Text(
            podcast.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  void _openPodcastDetails(MediaItem podcast, MusicAssistantProvider maProvider, String? imageUrl) {
    updateAdaptiveColorsFromImage(context, imageUrl);
    Navigator.push(
      context,
      FadeSlidePageRoute(
        child: PodcastDetailScreen(
          podcast: podcast,
          heroTagSuffix: 'library',
          initialImageUrl: imageUrl,
        ),
      ),
    );
  }

  /// Pre-cache podcast images so hero animations are smooth on first tap
  void _precachePodcastImages(List<MediaItem> podcasts, MusicAssistantProvider maProvider) {
    if (!mounted || _hasPrecachedPodcasts) return;
    _hasPrecachedPodcasts = true;

    // Only precache first ~10 visible items to avoid excessive network/memory use
    final podcastsToCache = podcasts.take(10);

    for (final podcast in podcastsToCache) {
      // iTunes URL from persisted cache
      final imageUrl = maProvider.getPodcastImageUrl(podcast);
      if (imageUrl != null) {
        // Use CachedNetworkImageProvider to warm the cache
        precacheImage(
          CachedNetworkImageProvider(imageUrl),
          context,
        ).catchError((_) {
          // Silently ignore precache errors
          return false;
        });
      }
    }
  }

  // ============ RADIO TAB ============
  Widget _buildRadioStationsTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // PERF: Use select() to only rebuild when radio stations or loading state changes
    final (allRadioStations, isLoading) = context.select<MusicAssistantProvider, (List<MediaItem>, bool)>(
      (p) => (p.radioStations, p.isLoadingRadio),
    );
    // Use read() for methods that don't need reactive updates
    final maProvider = context.read<MusicAssistantProvider>();

    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    // Filter by favorites if enabled
    final radioStations = _showFavoritesOnly
        ? allRadioStations.where((s) => s.favorite == true).toList()
        : allRadioStations;

    if (radioStations.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          context: context,
          icon: Icons.favorite_border,
          title: l10n.noFavoriteRadioStations,
          subtitle: l10n.longPressRadioHint,
        );
      }
      return EmptyState.custom(
        context: context,
        icon: MdiIcons.radio,
        title: l10n.noRadioStations,
        subtitle: l10n.addRadioStationsHint,
        onRefresh: () => maProvider.loadRadioStations(),
      );
    }

    // PERF: Use appropriate cache size based on view mode
    final cacheSize = _radioViewMode == 'grid3' ? 200 : 256;

    // Trust server-side sorting - don't re-sort client-side
    // Server handles: name, name_desc, timestamp_added_desc, last_played_desc, play_count_desc
    final sortedRadioStations = radioStations;

    // Generate radio station names for letter scrollbar
    final radioNames = sortedRadioStations.map((s) => s.name).toList();

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.background,
      onRefresh: () => maProvider.loadRadioStations(),
      child: LetterScrollbar(
        controller: _radioScrollController,
        items: radioNames,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        bottomPadding: BottomSpacing.withMiniPlayer,
        child: _radioViewMode == 'list'
          ? ListView.builder(
              controller: _radioScrollController,
              key: const PageStorageKey<String>('radio_stations_list'),
              cacheExtent: 1000,
              padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
              itemCount: sortedRadioStations.length,
              itemBuilder: (context, index) {
                final station = sortedRadioStations[index];
                final imageUrl = maProvider.getImageUrl(station, size: cacheSize);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            memCacheWidth: cacheSize,
                            memCacheHeight: cacheSize,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (context, url) => Container(
                              width: 56,
                              height: 56,
                              color: colorScheme.surfaceVariant,
                              child: Icon(MdiIcons.radio, color: colorScheme.onSurfaceVariant),
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 56,
                              height: 56,
                              color: colorScheme.surfaceVariant,
                              child: Icon(MdiIcons.radio, color: colorScheme.onSurfaceVariant),
                            ),
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            color: colorScheme.surfaceVariant,
                            child: Icon(MdiIcons.radio, color: colorScheme.onSurfaceVariant),
                          ),
                  ),
                  title: Text(
                    station.name,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: station.metadata?['description'] != null
                      ? Text(
                          station.metadata!['description'] as String,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () => _playRadioStation(maProvider, station),
                );
              },
            )
          : GridView.builder(
              controller: _radioScrollController,
              key: PageStorageKey<String>('radio_stations_grid_$_radioViewMode'),
              cacheExtent: 1000,
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _radioViewMode == 'grid3' ? 3 : 2,
                childAspectRatio: _radioViewMode == 'grid3' ? 0.75 : 0.80,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: sortedRadioStations.length,
              itemBuilder: (context, index) {
                final station = sortedRadioStations[index];
                return _buildRadioCard(station, maProvider, cacheSize);
              },
            ),
      ),
    );
  }

  Widget _buildRadioCard(MediaItem station, MusicAssistantProvider maProvider, int cacheSize) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final imageUrl = maProvider.getImageUrl(station, size: cacheSize);

    return GestureDetector(
      onTap: () => _playRadioStation(maProvider, station),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: colorScheme.surfaceVariant,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: cacheSize,
                        memCacheHeight: cacheSize,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (context, url) => const SizedBox(),
                        errorWidget: (context, url, error) => Center(
                          child: Icon(
                            MdiIcons.radio,
                            size: 48,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          MdiIcons.radio,
                          size: 48,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),
          Spacing.vGap8,
          Text(
            station.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  void _playRadioStation(MusicAssistantProvider maProvider, MediaItem station) {
    final selectedPlayer = maProvider.selectedPlayer;
    if (selectedPlayer != null) {
      maProvider.api?.playRadioStation(selectedPlayer.playerId, station);
    }
  }

  // ============ ARTISTS TAB ============
  Widget _buildArtistsTab(BuildContext context, S l10n) {
    // Use Selector for targeted rebuilds - only rebuild when artists or loading state changes
    // Artist filtering (albumArtistsOnly) is done at API level
    return Selector<MusicAssistantProvider, (List<Artist>, bool)>(
      selector: (_, provider) => (provider.artists, provider.isLoading),
      builder: (context, data, _) {
            final (allArtists, isLoading) = data;
            final colorScheme = Theme.of(context).colorScheme;

            if (isLoading) {
              return Center(child: CircularProgressIndicator(color: colorScheme.primary));
            }

            // Filter by favorites if enabled (artist filter is done at API level)
            final artists = _showFavoritesOnly
                ? allArtists.where((a) => a.favorite == true).toList()
                : allArtists;

            if (artists.isEmpty) {
              if (_showFavoritesOnly) {
                return EmptyState.custom(
                  context: context,
                  icon: Icons.favorite_border,
                  title: l10n.noFavoriteArtists,
                  subtitle: l10n.tapHeartArtist,
                );
              }
              return EmptyState.artists(
                context: context,
                onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
              );
            }

            // Trust server-side sorting - don't re-sort client-side
            // Server handles: name, name_desc, timestamp_added, timestamp_added_desc,
            // last_played, last_played_desc, play_count, play_count_desc
            final sortedArtists = artists;
            final artistNames = sortedArtists.map((a) => a.name ?? '').toList();

            return RefreshIndicator(
              color: colorScheme.primary,
              backgroundColor: colorScheme.background,
              onRefresh: () async => context.read<MusicAssistantProvider>().loadLibrary(),
              child: LetterScrollbar(
                controller: _artistsScrollController,
                items: artistNames,
                onDragStateChanged: _onLetterScrollbarDragChanged,
                bottomPadding: BottomSpacing.withMiniPlayer,
                child: _artistsViewMode == 'list'
                    ? ListView.builder(
                        controller: _artistsScrollController,
                        key: PageStorageKey<String>('library_artists_list_${_showFavoritesOnly ? 'fav' : 'all'}_$_artistsViewMode'),
                        cacheExtent: 1000,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: false,
                        itemCount: sortedArtists.length,
                        padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
                        itemBuilder: (context, index) {
                          final artist = sortedArtists[index];
                          return _buildArtistTile(
                            context,
                            artist,
                            key: ValueKey(artist.uri ?? artist.itemId),
                          );
                        },
                      )
                    : GridView.builder(
                        controller: _artistsScrollController,
                        key: PageStorageKey<String>('library_artists_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_artistsViewMode'),
                        cacheExtent: 1000,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: false,
                        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _artistsViewMode == 'grid3' ? 3 : 2,
                          childAspectRatio: _artistsViewMode == 'grid3' ? 0.75 : 0.80,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: sortedArtists.length,
                        itemBuilder: (context, index) {
                          final artist = sortedArtists[index];
                          return _buildArtistGridCard(context, artist);
                        },
                      ),
              ),
            );
          },
    );
  }

  Widget _buildArtistTile(
    BuildContext context,
    Artist artist, {
    Key? key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();
    final suffix = '_library';
    // Get image URL for hero animation
    final imageUrl = maProvider.getImageUrl(artist, size: 256);

    return RepaintBoundary(
      child: ListTile(
        key: key,
        leading: ArtistAvatar(
          artist: artist,
          radius: 24,
          imageSize: 128,
          heroTag: HeroTags.artistImage + (artist.uri ?? artist.itemId) + suffix,
        ),
      title: Hero(
        tag: HeroTags.artistName + (artist.uri ?? artist.itemId) + suffix,
        child: Material(
          color: Colors.transparent,
          child: Text(
            artist.name,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
        onTap: () {
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: ArtistDetailsScreen(
                artist: artist,
                heroTagSuffix: 'library',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildArtistGridCard(BuildContext context, Artist artist) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(artist, size: 256);

    return GestureDetector(
      onTap: () {
        updateAdaptiveColorsFromImage(context, imageUrl);
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: ArtistDetailsScreen(
              artist: artist,
              heroTagSuffix: 'library_grid',
              initialImageUrl: imageUrl,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Use LayoutBuilder to get available width for proper circle sizing
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Use the smaller dimension to ensure a circle
                final size = constraints.maxWidth < constraints.maxHeight
                    ? constraints.maxWidth
                    : constraints.maxHeight;
                // PERF: Use appropriate cache size based on grid columns
                final cacheSize = _artistsViewMode == 'grid3' ? 200 : 300;
                return Center(
                  child: ArtistAvatar(
                    artist: artist,
                    radius: size / 2,
                    imageSize: cacheSize,
                    heroTag: HeroTags.artistImage + (artist.uri ?? artist.itemId) + '_library_grid',
                  ),
                );
              },
            ),
          ),
          Spacing.vGap8,
          Text(
            artist.name,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ============ ALBUMS TAB ============
  Widget _buildAlbumsTab(BuildContext context, S l10n) {
    // Use Selector for targeted rebuilds - only rebuild when albums or loading state changes
    return Selector<MusicAssistantProvider, (List<Album>, bool)>(
      selector: (_, provider) => (provider.albums, provider.isLoading),
      builder: (context, data, _) {
        final (allAlbums, isLoading) = data;
        final colorScheme = Theme.of(context).colorScheme;

        if (isLoading) {
          return Center(child: CircularProgressIndicator(color: colorScheme.primary));
        }

        // Filter by favorites if enabled
        final albums = _showFavoritesOnly
            ? allAlbums.where((a) => a.favorite == true).toList()
            : allAlbums;

        if (albums.isEmpty) {
          if (_showFavoritesOnly) {
            return EmptyState.custom(
              context: context,
              icon: Icons.favorite_border,
              title: l10n.noFavoriteAlbums,
              subtitle: l10n.tapHeartAlbum,
            );
          }
          return EmptyState.albums(
            context: context,
            onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
          );
        }

        // Trust server-side sorting - don't re-sort client-side
        // Server handles: name, name_desc, year, year_desc, artist_name, artist_name_desc,
        // timestamp_added, timestamp_added_desc, last_played, last_played_desc, play_count, play_count_desc
        final sortedAlbums = albums;
        final albumNames = sortedAlbums.map((a) => a.name ?? '').toList();

        return RefreshIndicator(
          color: colorScheme.primary,
          backgroundColor: colorScheme.background,
          onRefresh: () async => context.read<MusicAssistantProvider>().loadLibrary(),
          child: LetterScrollbar(
            controller: _albumsScrollController,
            items: albumNames,
            onDragStateChanged: _onLetterScrollbarDragChanged,
            bottomPadding: BottomSpacing.withMiniPlayer,
            child: _albumsViewMode == 'list'
                ? ListView.builder(
                    controller: _albumsScrollController,
                    key: PageStorageKey<String>('library_albums_list_${_showFavoritesOnly ? 'fav' : 'all'}_$_albumsViewMode'),
                    cacheExtent: 1000,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
                    itemCount: sortedAlbums.length,
                    itemBuilder: (context, index) {
                      final album = sortedAlbums[index];
                      return _buildAlbumListTile(context, album);
                    },
                  )
                : GridView.builder(
                    controller: _albumsScrollController,
                    key: PageStorageKey<String>('library_albums_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_albumsViewMode'),
                    cacheExtent: 1000,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _albumsViewMode == 'grid3' ? 3 : 2,
                      childAspectRatio: _albumsViewMode == 'grid3' ? 0.70 : 0.75,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: sortedAlbums.length,
                    itemBuilder: (context, index) {
                      final album = sortedAlbums[index];
                      return AlbumCard(
                        key: ValueKey(album.uri ?? album.itemId),
                        album: album,
                        heroTagSuffix: 'library_grid',
                        // Use 256 to match detail screen for smooth Hero animation
                        imageCacheSize: 256,
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumListTile(BuildContext context, Album album) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(album, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 56,
          height: 56,
          color: colorScheme.surfaceVariant,
          child: imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 256,
                  memCacheHeight: 256,
                  placeholder: (_, __) => const SizedBox(),
                  errorWidget: (_, __, ___) => Icon(
                    Icons.album_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              : Icon(
                  Icons.album_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
        ),
      ),
      title: Text(
        album.nameWithYear,
        style: textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        album.artistsString,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        updateAdaptiveColorsFromImage(context, imageUrl);
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: AlbumDetailsScreen(
              album: album,
              initialImageUrl: imageUrl,
            ),
          ),
        );
      },
    );
  }

  // ============ PLAYLISTS TAB ============
  Widget _buildPlaylistsTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingPlaylists) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_playlists.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          context: context,
          icon: Icons.favorite_border,
          title: l10n.noFavoritePlaylists,
          subtitle: l10n.tapHeartPlaylist,
        );
      }
      return EmptyState.playlists(context: context, onRefresh: () => _loadPlaylists());
    }

    // PERF: Use pre-sorted lists (sorted once on load)
    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.background,
      onRefresh: () => _loadPlaylists(favoriteOnly: _showFavoritesOnly ? true : null),
      child: LetterScrollbar(
        controller: _playlistsScrollController,
        items: _playlistNames,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        bottomPadding: BottomSpacing.withMiniPlayer,
        child: _playlistsViewMode == 'list'
            ? ListView.builder(
                controller: _playlistsScrollController,
                key: PageStorageKey<String>('library_playlists_list_${_showFavoritesOnly ? 'fav' : 'all'}_$_playlistsViewMode'),
                cacheExtent: 1000,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                itemCount: _sortedPlaylists.length,
                padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
                itemBuilder: (context, index) {
                  final playlist = _sortedPlaylists[index];
                  return _buildPlaylistTile(context, playlist, l10n);
                },
              )
            : GridView.builder(
                controller: _playlistsScrollController,
                key: PageStorageKey<String>('library_playlists_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_playlistsViewMode'),
                cacheExtent: 1000,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _playlistsViewMode == 'grid3' ? 3 : 2,
                  childAspectRatio: _playlistsViewMode == 'grid3' ? 0.75 : 0.80,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _sortedPlaylists.length,
                itemBuilder: (context, index) {
                  final playlist = _sortedPlaylists[index];
                  return _buildPlaylistGridCard(context, playlist, l10n);
                },
              ),
      ),
    );
  }

  Widget _buildPlaylistTile(BuildContext context, Playlist playlist, S l10n) {
    final provider = context.read<MusicAssistantProvider>();
    final imageUrl = provider.api?.getImageUrl(playlist, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Unique suffix for list view context
    const heroSuffix = '_library_list';

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(playlist.itemId),
        leading: Hero(
          tag: HeroTags.playlistCover + (playlist.uri ?? playlist.itemId) + heroSuffix,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              color: colorScheme.surfaceContainerHighest,
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 96,
                      memCacheHeight: 96,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, __) => const SizedBox(),
                      errorWidget: (_, __, ___) => Icon(
                        Icons.playlist_play_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Icon(
                      Icons.playlist_play_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
            ),
          ),
        ),
        title: Hero(
          tag: HeroTags.playlistTitle + (playlist.uri ?? playlist.itemId) + heroSuffix,
          child: Material(
            color: Colors.transparent,
            child: Text(
              playlist.name,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        subtitle: Text(
          playlist.trackCount != null
              ? '${playlist.trackCount} ${l10n.tracks}'
              : playlist.owner ?? l10n.playlist,
          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: playlist.favorite == true
            ? const Icon(Icons.favorite, color: StatusColors.favorite, size: 20)
            : null,
        onTap: () {
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: PlaylistDetailsScreen(
                playlist: playlist,
                heroTagSuffix: 'library_list',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistGridCard(BuildContext context, Playlist playlist, S l10n) {
    final provider = context.read<MusicAssistantProvider>();
    final imageUrl = provider.api?.getImageUrl(playlist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Unique suffix for grid view context
    const heroSuffix = '_library_grid';

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: PlaylistDetailsScreen(
                playlist: playlist,
                heroTagSuffix: 'library_grid',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Hero(
                tag: HeroTags.playlistCover + (playlist.uri ?? playlist.itemId) + heroSuffix,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            memCacheWidth: 256,
                            memCacheHeight: 256,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (_, __) => const SizedBox(),
                            errorWidget: (_, __, ___) => Center(
                              child: Icon(
                                Icons.playlist_play_rounded,
                                size: 48,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.playlist_play_rounded,
                              size: 48,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            Spacing.vGap8,
            Hero(
              tag: HeroTags.playlistTitle + (playlist.uri ?? playlist.itemId) + heroSuffix,
              child: Material(
                color: Colors.transparent,
                child: Text(
                  playlist.name,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Text(
              playlist.trackCount != null
                  ? '${playlist.trackCount} ${l10n.tracks}'
                  : playlist.owner ?? l10n.playlist,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ============ TRACKS TAB ============
  Widget _buildTracksTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingTracks && _allTracks.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    // Get the appropriate track list based on favorites mode
    final List<Track> displayTracks;
    if (_showFavoritesOnly) {
      // Use the dedicated favorites list that was loaded by _loadFavoriteTracks()
      displayTracks = _sortedFavoriteTracks;
    } else {
      displayTracks = _sortedAllTracks;
    }

    if (displayTracks.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          context: context,
          icon: Icons.favorite_border,
          title: l10n.noFavoriteTracks,
          subtitle: l10n.longPressTrackHint,
        );
      }
      return EmptyState.custom(
        context: context,
        icon: Icons.music_note,
        title: l10n.noTracks,
        subtitle: l10n.addTracksHint,
        onRefresh: _loadAllTracks,
      );
    }

    // Build items list based on current sort order for accurate letter display
    final List<String> trackSortKeys;
    switch (_tracksSortOrder) {
      case 'artist':
      case 'artist_name':
        trackSortKeys = displayTracks.map((t) => t.artistsString).toList();
        break;
      case 'album':
        trackSortKeys = displayTracks.map((t) => t.album?.name ?? t.name).toList();
        break;
      default:
        // For name, duration, timestamp, etc. - use track name for letter scrollbar
        trackSortKeys = displayTracks.map((t) => t.name).toList();
        break;
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.background,
      onRefresh: _loadAllTracks,
      child: LetterScrollbar(
        controller: _tracksScrollController,
        items: trackSortKeys,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        bottomPadding: BottomSpacing.withMiniPlayer,
        child: ListView.builder(
          controller: _tracksScrollController,
          key: PageStorageKey<String>('library_tracks_list_${_showFavoritesOnly ? 'fav' : 'all'}'),
          cacheExtent: 1000,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
          padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
          itemCount: displayTracks.length + (_hasMoreTracks && !_showFavoritesOnly ? 1 : 0),
          itemBuilder: (context, index) {
            // Show loading indicator at the end when loading more
            if (index >= displayTracks.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: _isLoadingMoreTracks
                      ? CircularProgressIndicator(color: colorScheme.primary)
                      : const SizedBox(),
                ),
              );
            }
            final track = displayTracks[index];
            return _buildTrackTile(context, track);
          },
        ),
      ),
    );
  }

  Widget _buildTrackTile(BuildContext context, Track track) {
    final maProvider = context.read<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Get image URL from track itself
    final imageUrl = maProvider.api?.getImageUrl(track, size: 128);

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(track.uri ?? track.itemId),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
          image: imageUrl != null
              ? DecorationImage(
                  image: CachedNetworkImageProvider(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: imageUrl == null
            ? Icon(Icons.music_note, color: colorScheme.onSurfaceVariant, size: 24)
            : null,
      ),
      title: Text(
        track.name,
        style: textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artistsString,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (track.favorite == true)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(
                Icons.favorite,
                color: StatusColors.favorite,
                size: 18,
              ),
            ),
          if (track.duration != null)
            Text(
              _formatTrackDuration(track.duration!),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
        ],
      ),
      onTap: () async {
        final player = maProvider.selectedPlayer;
        if (player == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
          );
          return;
        }

        try {
          // Start radio from this track
          await maProvider.api?.playRadio(player.playerId, track);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to start radio: $e')),
            );
          }
        }
      },
      ),
    );
  }

  String _formatTrackDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Custom PageScrollPhysics with faster spring for quicker settling
/// This allows vertical scrolling to work sooner after a horizontal swipe
class _FastPageScrollPhysics extends PageScrollPhysics {
  const _FastPageScrollPhysics({super.parent});

  @override
  _FastPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _FastPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
    mass: 50,      // Lower mass = faster movement
    stiffness: 500, // Higher stiffness = snappier
    damping: 1.0,   // Critical damping for no overshoot
  );
}

/// Options menu overlay that stays open on sort selection
class _OptionsMenuOverlay extends StatefulWidget {
  final Offset position;
  final Size buttonSize;
  final ColorScheme colorScheme;
  final String currentSort;
  final String currentViewMode;
  final bool hasViewModes;
  final bool showFavoritesOnly;
  final bool showOnlyArtistsWithAlbums;
  final LibraryMediaType selectedMediaType;
  final int tabIndex;
  final List<(String, String, IconData, bool)> sortFields;
  final (String, bool) Function(String) parseSortOrder;
  final String Function(String, bool) buildSortOrder;
  final void Function(String) onSortChanged;
  final void Function(String) onViewModeChanged;
  final VoidCallback onFavoritesToggled;
  final VoidCallback onArtistsFilterToggled;
  final VoidCallback onDismiss;

  const _OptionsMenuOverlay({
    required this.position,
    required this.buttonSize,
    required this.colorScheme,
    required this.currentSort,
    required this.currentViewMode,
    required this.hasViewModes,
    required this.showFavoritesOnly,
    required this.showOnlyArtistsWithAlbums,
    required this.selectedMediaType,
    required this.tabIndex,
    required this.sortFields,
    required this.parseSortOrder,
    required this.buildSortOrder,
    required this.onSortChanged,
    required this.onViewModeChanged,
    required this.onFavoritesToggled,
    required this.onArtistsFilterToggled,
    required this.onDismiss,
  });

  @override
  State<_OptionsMenuOverlay> createState() => _OptionsMenuOverlayState();
}

class _OptionsMenuOverlayState extends State<_OptionsMenuOverlay>
    with SingleTickerProviderStateMixin {
  late String _currentSort;
  late String _currentViewMode;
  late bool _showFavoritesOnly;
  late bool _showOnlyArtistsWithAlbums;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _currentSort = widget.currentSort;
    _currentViewMode = widget.currentViewMode;
    _showFavoritesOnly = widget.showFavoritesOnly;
    _showOnlyArtistsWithAlbums = widget.showOnlyArtistsWithAlbums;

    _animController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_OptionsMenuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSort != widget.currentSort) {
      _currentSort = widget.currentSort;
    }
  }

  void _handleSortTap(String baseField, bool defaultDesc) {
    final (currentBaseField, currentIsDesc) = widget.parseSortOrder(_currentSort);

    String newSort;
    if (baseField == currentBaseField) {
      // Toggle direction
      newSort = widget.buildSortOrder(baseField, !currentIsDesc);
    } else {
      // Select with default direction
      newSort = widget.buildSortOrder(baseField, defaultDesc);
    }

    setState(() {
      _currentSort = newSort;
    });
    widget.onSortChanged(newSort);
  }

  void _handleViewModeTap(String mode) {
    setState(() {
      _currentViewMode = mode;
    });
    widget.onViewModeChanged(mode);
  }

  void _handleFavoritesTap() {
    setState(() {
      _showFavoritesOnly = !_showFavoritesOnly;
    });
    widget.onFavoritesToggled();
  }

  void _handleArtistsFilterTap() {
    setState(() {
      _showOnlyArtistsWithAlbums = !_showOnlyArtistsWithAlbums;
    });
    widget.onArtistsFilterToggled();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final (currentBaseField, currentIsDesc) = widget.parseSortOrder(_currentSort);

    // Position menu below and to the left of the button
    final menuWidth = 220.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final left = (widget.position.dx + widget.buttonSize.width - menuWidth).clamp(8.0, screenWidth - menuWidth - 8);
    final top = widget.position.dy + widget.buttonSize.height + 4;

    return Stack(
      children: [
        // Dismiss on tap outside
        FadeTransition(
          opacity: _fadeAnimation,
          child: ModalBarrier(
            dismissible: true,
            onDismiss: widget.onDismiss,
            color: Colors.black12,
          ),
        ),
        // Menu with scale and fade animation
        Positioned(
          left: left,
          top: top,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              alignment: Alignment.topRight,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: colorScheme.surface,
                child: Container(
                  width: menuWidth,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height - top - 50,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sort section header
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 4),
                      child: Text(
                        'Sort',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                    // Sort options
                    ...widget.sortFields.map((field) {
                      final (baseField, label, icon, defaultDesc) = field;
                      final isSelected = currentBaseField == baseField;
                      final isDesc = isSelected ? currentIsDesc : defaultDesc;

                      return InkWell(
                        onTap: () => _handleSortTap(baseField, defaultDesc),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              // Selection indicator - fixed width
                              SizedBox(
                                width: 24,
                                child: isSelected
                                    ? Icon(Icons.check, size: 18, color: colorScheme.primary)
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                icon,
                                size: 18,
                                color: isSelected ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.7),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              // Direction indicator - fixed position
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? colorScheme.primary.withOpacity(0.1)
                                      : colorScheme.surfaceVariant.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  isDesc ? Icons.arrow_downward : Icons.arrow_upward,
                                  size: 14,
                                  color: isSelected ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    // View section
                    if (widget.hasViewModes) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 4),
                        child: Text(
                          'View',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ),
                      _buildViewModeItem('list', 'List', Icons.view_list, colorScheme),
                      _buildViewModeItem('grid2', '2-Column Grid', Icons.grid_on, colorScheme),
                      _buildViewModeItem('grid3', '3-Column Grid', Icons.grid_view, colorScheme),
                    ],

                    // Filter section
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 4),
                      child: Text(
                        'Filter',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                    // Favorites toggle
                    InkWell(
                      onTap: _handleFavoritesTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            // Checkmark on left - fixed width
                            SizedBox(
                              width: 24,
                              child: _showFavoritesOnly
                                  ? Icon(Icons.check, size: 18, color: StatusColors.favorite)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                              size: 18,
                              color: _showFavoritesOnly ? StatusColors.favorite : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Favorites Only',
                                style: TextStyle(
                                  color: _showFavoritesOnly ? StatusColors.favorite : null,
                                  fontWeight: _showFavoritesOnly ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Artists filter (only show on Artists tab)
                    if (widget.selectedMediaType == LibraryMediaType.music && widget.tabIndex == 0)
                      InkWell(
                        onTap: _handleArtistsFilterTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              // Checkmark on left - fixed width
                              SizedBox(
                                width: 24,
                                child: _showOnlyArtistsWithAlbums
                                    ? Icon(Icons.check, size: 18, color: colorScheme.primary)
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _showOnlyArtistsWithAlbums ? Icons.album : Icons.album_outlined,
                                size: 18,
                                color: _showOnlyArtistsWithAlbums ? colorScheme.primary : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'With Albums Only',
                                  style: TextStyle(
                                    color: _showOnlyArtistsWithAlbums ? colorScheme.primary : null,
                                    fontWeight: _showOnlyArtistsWithAlbums ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildViewModeItem(String mode, String label, IconData icon, ColorScheme colorScheme) {
    final isSelected = _currentViewMode == mode;
    return InkWell(
      onTap: () => _handleViewModeTap(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: isSelected
                  ? Icon(Icons.check, size: 18, color: colorScheme.primary)
                  : null,
            ),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: 18,
              color: isSelected ? colorScheme.primary : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? colorScheme.primary : null,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
