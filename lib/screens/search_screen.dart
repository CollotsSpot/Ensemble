import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../constants/timings.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../services/debug_logger.dart';
import '../services/database_service.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/common/disconnected_state.dart';
import '../widgets/artist_avatar.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';
import '../utils/search/search_scoring.dart';
import 'album_details_screen.dart';
import 'artist_details_screen.dart';
import 'playlist_details_screen.dart';
import 'audiobook_detail_screen.dart';
import 'podcast_detail_screen.dart';
import '../l10n/app_localizations.dart';
import '../theme/design_tokens.dart';
import '../widgets/media_context_menu.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

// Helper enum and class for ListView.builder item types
enum _ListItemType { header, artist, album, track, playlist, audiobook, radio, podcast, spacer }

class _ListItem {
  final _ListItemType type;
  final MediaItem? mediaItem;
  final String? headerTitle;
  final int? headerCount;
  final double? relevanceScore; // For unified view sorting

  _ListItem.header(this.headerTitle, this.headerCount)
      : type = _ListItemType.header,
        mediaItem = null,
        relevanceScore = null;

  _ListItem.artist(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.artist,
        headerTitle = null,
        headerCount = null;

  _ListItem.album(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.album,
        headerTitle = null,
        headerCount = null;

  _ListItem.track(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.track,
        headerTitle = null,
        headerCount = null;

  _ListItem.playlist(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.playlist,
        headerTitle = null,
        headerCount = null;

  _ListItem.audiobook(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.audiobook,
        headerTitle = null,
        headerCount = null;

  _ListItem.radio(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.radio,
        headerTitle = null,
        headerCount = null;

  _ListItem.podcast(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.podcast,
        headerTitle = null,
        headerCount = null;

  _ListItem.spacer()
      : type = _ListItemType.spacer,
        mediaItem = null,
        headerTitle = null,
        headerCount = null,
        relevanceScore = null;
}

class SearchScreenState extends State<SearchScreen> {
  final _logger = DebugLogger();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PageController _pageController = PageController();
  final ScrollController _filterScrollController = ScrollController();
  Timer? _debounceTimer;
  Map<String, List<MediaItem>> _searchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
    'playlists': [],
    'audiobooks': [],
    'radios': [],
    'podcasts': [],
  };
  bool _isSearching = false;
  bool _hasSearched = false;
  // Race condition fix: Track the active search request ID
  int _currentSearchId = 0;
  bool _hasPendingSearch = false;
  // PERF: Use ValueNotifier to avoid full screen rebuild on filter change
  final ValueNotifier<String> _activeFilterNotifier = ValueNotifier('all');
  String? _searchError;
  List<String> _recentSearches = [];
  bool _libraryOnly = false;
  bool _hasSearchText = false; // PERF: Track separately to avoid rebuild on every keystroke

  // Track library changes locally since item data doesn't update immediately
  final Set<String> _addedToLibrary = {};
  final Set<String> _removedFromLibrary = {};

  // PERF: Cache list items per filter to avoid rebuilding during PageView animation
  Map<String, List<_ListItem>> _cachedListItems = {};
  // PERF: Cache available filters to avoid recalculating during build
  List<String>? _cachedAvailableFilters;

  // Advanced search scorer with fuzzy matching, stopword removal, etc.
  final SearchScorer _searchScorer = SearchScorer();

  // Scroll-to-hide search bar (vertical scroll only)
  bool _isSearchBarVisible = true;
  double _lastVerticalScrollOffset = 0;
  static const double _scrollThreshold = 10.0;

  // Filter chip position tracking for animated sliding highlight
  final Map<String, GlobalKey> _filterKeys = {};
  final Map<String, double> _filterWidths = {};
  final Map<String, double> _filterPositions = {};
  double _highlightLeft = 0;
  double _highlightWidth = 80; // Default width until measured

  @override
  void initState() {
    super.initState();
    // Don't auto-focus - let user tap to focus
    // This prevents keyboard popup bug when SearchScreen is in widget tree but not visible
    _loadRecentSearches();
  }

  /// Get list of available filters based on current results (cached)
  List<String> _getAvailableFilters() {
    if (_cachedAvailableFilters != null) return _cachedAvailableFilters!;

    final filters = <String>['all'];
    if (_searchResults['artists']?.isNotEmpty == true) filters.add('artists');
    if (_searchResults['albums']?.isNotEmpty == true) filters.add('albums');
    if (_searchResults['tracks']?.isNotEmpty == true) filters.add('tracks');
    if (_searchResults['playlists']?.isNotEmpty == true) filters.add('playlists');
    if (_searchResults['audiobooks']?.isNotEmpty == true) filters.add('audiobooks');
    if (_searchResults['radios']?.isNotEmpty == true) filters.add('radios');
    if (_searchResults['podcasts']?.isNotEmpty == true) filters.add('podcasts');
    _cachedAvailableFilters = filters;
    return filters;
  }

  /// Filter search results by enabled providers (only when in-library mode is on)
  /// Uses the client-side provider toggles from the library screen
  Map<String, List<MediaItem>> _filterByEnabledProviders(
    Map<String, List<MediaItem>> results,
    Set<String> enabledProviders,
  ) {
    if (enabledProviders.isEmpty) return results; // No filter = show all

    bool isItemAllowed(MediaItem item) {
      final mappings = item.providerMappings;
      if (mappings == null || mappings.isEmpty) return true; // No mappings = show
      // Item is allowed if it has inLibrary=true for any enabled provider
      return mappings.any((m) => m.inLibrary && enabledProviders.contains(m.providerInstance));
    }

    return {
      for (final entry in results.entries)
        entry.key: entry.value.where(isItemAllowed).toList(),
    };
  }

  /// Animate to a specific filter
  void _animateToFilter(String filter) {
    final filters = _getAvailableFilters();
    final index = filters.indexOf(filter);
    if (index >= 0 && _pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Handle page change from swipe gesture
  void _onPageChanged(int pageIndex) {
    final filters = _getAvailableFilters();
    if (pageIndex >= 0 && pageIndex < filters.length) {
      // Only update ValueNotifier - no setState needed
      // ValueListenableBuilder will rebuild only the filter chips
      _activeFilterNotifier.value = filters[pageIndex];
      _scrollFilterIntoView(pageIndex);
    }
  }

  /// Measure filter chip positions and update highlight
  void _measureFilterPositions() {
    final filters = _getAvailableFilters();
    double left = 0;

    for (final filter in filters) {
      final key = _filterKeys[filter];
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          _filterWidths[filter] = box.size.width;
          _filterPositions[filter] = left;
          left += box.size.width;
        }
      }
    }
  }

  /// Update highlight position for the active filter
  void _updateHighlightPosition(String activeFilter) {
    _measureFilterPositions();

    final position = _filterPositions[activeFilter];
    final width = _filterWidths[activeFilter];

    if (position != null && width != null) {
      setState(() {
        _highlightLeft = position;
        _highlightWidth = width;
      });
    }
  }

  /// Scroll filter bar to keep active filter visible
  /// Only scrolls when the filter would be obscured (off-screen)
  /// Uses post-frame callback to avoid interfering with PageView animation
  void _scrollFilterIntoView(int filterIndex) {
    if (!_filterScrollController.hasClients) return;

    // Defer scroll calculation to after the frame to avoid layout during animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_filterScrollController.hasClients) return;

      final maxScroll = _filterScrollController.position.maxScrollExtent;

      // If all filters fit on screen, don't scroll at all
      if (maxScroll <= 0) return;

      final filters = _getAvailableFilters();
      if (filterIndex < 0 || filterIndex >= filters.length) return;

      final filter = filters[filterIndex];

      // Update highlight position
      _updateHighlightPosition(filter);

      // Use measured positions if available, fallback to estimate
      final chipLeft = _filterPositions[filter] ?? (filterIndex * 80.0);
      final chipWidth = _filterWidths[filter] ?? 80.0;
      final chipRight = chipLeft + chipWidth;

      final currentScroll = _filterScrollController.offset;
      final viewportWidth = _filterScrollController.position.viewportDimension;

      // Calculate what's currently visible in the viewport
      final visibleLeft = currentScroll;
      final visibleRight = currentScroll + viewportWidth;

      // Only scroll if the chip is actually obscured
      double? targetOffset;

      if (chipRight > visibleRight) {
        // Chip is cut off on the right - scroll right to show it with padding
        targetOffset = chipRight - viewportWidth + 8;
      } else if (chipLeft < visibleLeft) {
        // Chip is cut off on the left - scroll left to show it with padding
        targetOffset = chipLeft - 8;
      }

      // Only animate if we need to scroll
      if (targetOffset != null) {
        final clampedOffset = targetOffset.clamp(0.0, maxScroll);
        _filterScrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _loadRecentSearches() async {
    if (!DatabaseService.instance.isInitialized) return;
    final searches = await DatabaseService.instance.getRecentSearches();
    if (mounted) {
      setState(() {
        _recentSearches = searches;
      });
    }
  }

  void requestFocus() {
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  void removeFocus() {
    if (mounted) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _pageController.dispose();
    _filterScrollController.dispose();
    _activeFilterNotifier.dispose();
    super.dispose();
  }

  /// Handle scroll notifications - only vertical scroll hides search bar
  bool _handleScrollNotification(ScrollNotification notification) {
    // Only respond to vertical scroll (not horizontal PageView swipe)
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final currentOffset = notification.metrics.pixels;
      final delta = currentOffset - _lastVerticalScrollOffset;

      if (delta.abs() > _scrollThreshold) {
        final shouldShow = delta < 0 || currentOffset <= 0;
        if (shouldShow != _isSearchBarVisible) {
          setState(() {
            _isSearchBarVisible = shouldShow;
          });
        }
        _lastVerticalScrollOffset = currentOffset;
      }
    }
    return false;
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Timings.searchDebounce, () {
      // Race condition fix: Check mounted before proceeding
      if (!mounted) return;
      _performSearch(query, keepFocus: true);
    });
  }

  Future<void> _performSearch(String query, {bool keepFocus = false}) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = {'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': [], 'radios': [], 'podcasts': []};
        _hasSearched = false;
        _searchError = null;
        _cachedListItems.clear(); // PERF: Clear cache
        _cachedAvailableFilters = null;
      });
      return;
    }

    // Race condition fix: Generate unique ID for this search
    final searchId = ++_currentSearchId;
    _hasPendingSearch = true;

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final provider = context.read<MusicAssistantProvider>();
      final results = await provider.searchWithCache(query, libraryOnly: _libraryOnly);

      // Search for radios: combine library filtering + global search
      final queryLower = query.toLowerCase();

      // 1. Filter from library radio stations
      final libraryRadios = provider.radioStations
          .where((radio) => radio.name.toLowerCase().contains(queryLower))
          .toList();

      // 2. Also search globally via API (for providers like TuneIn)
      List<MediaItem> globalRadios = [];
      if (!_libraryOnly) {
        try {
          globalRadios = await provider.api?.searchRadioStations(query) ?? [];
        } catch (e) {
          _logger.log('Global radio search failed: $e');
        }
        // Race condition fix: Abort if a newer search has started
        if (!mounted || searchId != _currentSearchId) {
          _logger.log('⏭️ Ignoring stale radio search results for "$query"');
          return;
        }
      }

      // 3. Combine and deduplicate by name
      final allRadios = <String, MediaItem>{};
      for (final radio in libraryRadios) {
        allRadios[radio.name.toLowerCase()] = radio;
      }
      for (final radio in globalRadios) {
        final key = radio.name.toLowerCase();
        if (!allRadios.containsKey(key)) {
          allRadios[key] = radio;
        }
      }

      // Search for podcasts: combine library filtering + global search
      // 1. Filter from library podcasts
      final libraryPodcasts = provider.podcasts
          .where((podcast) => podcast.name.toLowerCase().contains(queryLower))
          .toList();

      // 2. Also search globally via API (for providers like iTunes)
      List<MediaItem> globalPodcasts = [];
      if (!_libraryOnly) {
        try {
          globalPodcasts = await provider.api?.searchPodcasts(query) ?? [];
        } catch (e) {
          _logger.log('Global podcast search failed: $e');
        }
        // Race condition fix: Abort if a newer search has started
        if (!mounted || searchId != _currentSearchId) {
          _logger.log('⏭️ Ignoring stale podcast search results for "$query"');
          return;
        }
      }

      // 3. Combine and deduplicate by name
      final allPodcasts = <String, MediaItem>{};
      for (final podcast in libraryPodcasts) {
        allPodcasts[podcast.name.toLowerCase()] = podcast;
      }
      for (final podcast in globalPodcasts) {
        final key = podcast.name.toLowerCase();
        if (!allPodcasts.containsKey(key)) {
          allPodcasts[key] = podcast;
        }
      }

      // Race condition fix: Only update results if this is still the latest search
      if (!mounted) return;
      if (searchId != _currentSearchId) {
        _logger.log('⏭️ Ignoring stale search results for "$query"');
        return;
      }

      // Combine all results
      var combinedResults = {
        ...results,
        'radios': allRadios.values.toList(),
        'podcasts': allPodcasts.values.toList(),
      };

      // When "in library" mode is on, also filter by enabled providers
      if (_libraryOnly) {
        final enabledProviders = provider.enabledProviderIds.toSet();
        combinedResults = _filterByEnabledProviders(combinedResults, enabledProviders);
      }

      setState(() {
        _searchResults = combinedResults;
        _isSearching = false;
        _hasSearched = true;
        _hasPendingSearch = false;
        _cachedListItems.clear(); // PERF: Clear cache on new results
        _cachedAvailableFilters = null;
      });

      // Save to search history if we got results
      final hasResults = results.values.any((list) => list.isNotEmpty);
      if (hasResults && DatabaseService.instance.isInitialized) {
        DatabaseService.instance.saveSearchQuery(query);
        _loadRecentSearches(); // Refresh the list
      }

      // Keep keyboard open if user is still typing
      if (keepFocus && _focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    } catch (e) {
      _logger.log('Search error: $e');
      if (!mounted) return;
      // Race condition fix: Only update error state if this is still the latest search
      if (searchId == _currentSearchId) {
        setState(() {
          _isSearching = false;
          _hasSearched = true;
          _hasPendingSearch = false;
          _searchError = S.of(context)!.searchFailed;
        });
        if (keepFocus && _focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // PERF: Only rebuild when connection status changes, not on every provider update
    final isConnected = context.select<MusicAssistantProvider, bool>((p) => p.isConnected);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Animated search bar - hides on scroll down
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: _isSearchBarVisible ? kToolbarHeight + 16 : 0,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    // Search field container
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _focusNode,
                          style: TextStyle(color: colorScheme.onSurface),
                          cursorColor: colorScheme.primary,
                          textInputAction: TextInputAction.search,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            hintText: S.of(context)!.searchMusic,
                            hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                            border: InputBorder.none,
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: colorScheme.onSurface.withOpacity(0.5),
                            ),
                            suffixIcon: _hasSearchText
                                ? IconButton(
                                    icon: Icon(Icons.clear_rounded, color: colorScheme.onSurface.withOpacity(0.5)),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _hasSearchText = false;
                                        _searchResults = {'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': [], 'podcasts': []};
                                        _hasSearched = false;
                                        _searchError = null;
                                        _cachedListItems.clear();
                                        _cachedAvailableFilters = null;
                                      });
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (value) {
                            // PERF: Only rebuild when clear button visibility changes
                            final hasText = value.isNotEmpty;
                            if (hasText != _hasSearchText) {
                              setState(() {
                                _hasSearchText = hasText;
                              });
                            }
                            _onSearchChanged(value);
                          },
                          onSubmitted: (query) => _performSearch(query),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Library-only toggle with circle background
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final control = SizedBox(
                          width: 44,
                          height: 44,
                          child: Material(
                            color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _libraryOnly = !_libraryOnly;
                                });
                                if (_searchController.text.isNotEmpty) {
                                  _performSearch(_searchController.text);
                                }
                              },
                              customBorder: const CircleBorder(),
                              child: Icon(
                                Symbols.book_2,
                                fill: _libraryOnly ? 1 : 0,
                                size: 22,
                                color: _libraryOnly
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                          ),
                        );

                        // Only use Tooltip if an Overlay ancestor exists
                        final hasOverlay = Overlay.maybeOf(context) != null;
                        if (!hasOverlay) {
                          return control;
                        }

                        return Tooltip(
                          message: S.of(context)!.libraryOnly,
                          child: control,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            // Main content
            Expanded(
              child: !isConnected
                  ? DisconnectedState.simple(context)
                  : _buildSearchContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchContent() {
    final colorScheme = Theme.of(context).colorScheme;

    // Show cached results even while searching - only show spinner if no cached results
    final hasCachedResults = _searchResults['artists']?.isNotEmpty == true ||
                             _searchResults['albums']?.isNotEmpty == true ||
                             _searchResults['tracks']?.isNotEmpty == true ||
                             _searchResults['playlists']?.isNotEmpty == true ||
                             _searchResults['audiobooks']?.isNotEmpty == true;

    if (_isSearching && !hasCachedResults) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 80,
              color: colorScheme.onBackground.withOpacity(0.3),
            ),
            Spacing.vGap16,
            Text(
              S.of(context)!.searchForContent,
              style: TextStyle(
                color: colorScheme.onBackground.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
            // Show recent searches if available
            if (_recentSearches.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text(
                S.of(context)!.recentSearches,
                style: TextStyle(
                  color: colorScheme.onBackground.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: _recentSearches.map((query) => ActionChip(
                    label: Text(query),
                    onPressed: () {
                      _searchController.text = query;
                      _performSearch(query);
                    },
                    backgroundColor: colorScheme.surfaceVariant.withOpacity(0.5),
                    side: BorderSide.none,
                  )).toList(),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: colorScheme.error.withOpacity(0.7),
            ),
            Spacing.vGap16,
            Text(
              _searchError!,
              style: TextStyle(
                color: colorScheme.error,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            Spacing.vGap16,
            FilledButton.tonal(
              onPressed: () => _performSearch(_searchController.text),
              child: Text(S.of(context)!.retry),
            ),
          ],
        ),
      );
    }

    final artists = _searchResults['artists'] as List<MediaItem>? ?? [];
    final albums = _searchResults['albums'] as List<MediaItem>? ?? [];
    final tracks = _searchResults['tracks'] as List<MediaItem>? ?? [];
    final playlists = _searchResults['playlists'] as List<MediaItem>? ?? [];
    final audiobooks = _searchResults['audiobooks'] as List<MediaItem>? ?? [];
    final radios = _searchResults['radios'] as List<MediaItem>? ?? [];
    final podcasts = _searchResults['podcasts'] as List<MediaItem>? ?? [];

    final hasResults = artists.isNotEmpty || albums.isNotEmpty || tracks.isNotEmpty ||
                       playlists.isNotEmpty || audiobooks.isNotEmpty || radios.isNotEmpty ||
                       podcasts.isNotEmpty;

    if (!hasResults) {
      return EmptyState.search(context: context);
    }

    // Column layout - filter bar above results, no overlay
    return Column(
      children: [
        // Filter tabs - rounded container matching search bar width
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            height: 36, // Match library screen filter row height
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SingleChildScrollView(
                controller: _filterScrollController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: _buildFilterSelector(colorScheme),
              ),
            ),
          ),
        ),
        // Results with swipeable pages
        Expanded(
          child: Stack(
            children: [
              // Main scrollable content
              NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: _getAvailableFilters().length,
                  // Use default physics - custom physics may cause issues with Flutter 3.38
                  physics: const PageScrollPhysics(),
                  itemBuilder: (context, pageIndex) {
                    final filters = _getAvailableFilters();
                    final filterForPage = filters[pageIndex];

                    // PERF: Use cached list items to avoid rebuilding during animation
                    final listItems = _cachedListItems[filterForPage] ??= _buildListItemsForFilter(
                      filterForPage, artists, albums, tracks, playlists, audiobooks, radios, podcasts,
                    );

                    // PERF: Wrap each page in RepaintBoundary to isolate repaints during swipe
                    return RepaintBoundary(
                      key: ValueKey('page_$filterForPage'),
                      child: ListView.builder(
                        // PERF: Use key to preserve scroll position per filter
                        key: PageStorageKey('list_$filterForPage'),
                        padding: EdgeInsets.fromLTRB(16, 16, 16, BottomSpacing.navBarOnly),
                        cacheExtent: 1000,
                        addAutomaticKeepAlives: false,
                        // PERF: false because each tile already has RepaintBoundary
                        addRepaintBoundaries: false,
                        itemCount: listItems.length,
                        itemBuilder: (context, index) {
                          final item = listItems[index];
                          final showTypeInSubtitle = filterForPage == 'all';
                          switch (item.type) {
                            case _ListItemType.header:
                              return _buildSectionHeader(item.headerTitle!, item.headerCount!);
                            case _ListItemType.artist:
                              return _buildArtistTile(item.mediaItem! as Artist, showType: showTypeInSubtitle);
                            case _ListItemType.album:
                              return _buildAlbumTile(item.mediaItem! as Album, showType: showTypeInSubtitle);
                            case _ListItemType.track:
                              return _buildTrackTile(item.mediaItem! as Track, showType: showTypeInSubtitle);
                            case _ListItemType.playlist:
                              return _buildPlaylistTile(item.mediaItem! as Playlist, showType: showTypeInSubtitle);
                            case _ListItemType.audiobook:
                              return _buildAudiobookTile(item.mediaItem! as Audiobook, showType: showTypeInSubtitle);
                            case _ListItemType.radio:
                              return _buildRadioTile(item.mediaItem!, showType: showTypeInSubtitle);
                            case _ListItemType.podcast:
                              return _buildPodcastTile(item.mediaItem!, showType: showTypeInSubtitle);
                            case _ListItemType.spacer:
                              return const SizedBox(height: 24);
                          }
                        },
                      ),
                    );
                  },
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
    );
  }

  /// Calculate relevance score for a media item based on query match.
  ///
  /// Uses advanced scoring with:
  /// - Stopword removal ("the Ramones" finds "Ramones")
  /// - Fuzzy matching (typo tolerance via Jaro-Winkler)
  /// - N-gram matching (partial matches)
  /// - Reverse matching (query contains result name)
  double _calculateRelevanceScore(MediaItem item, String query) {
    return _searchScorer.scoreItem(item, query);
  }

  /// Extract artists from tracks/albums that match the query but aren't in direct results
  /// This enables cross-referencing: searching "Yesterday Beatles" will include The Beatles artist
  List<Artist> _extractCrossReferencedArtists(
    String query,
    List<Artist> directArtists,
    List<Album> albums,
    List<Track> tracks,
  ) {
    if (query.isEmpty) return [];

    // Use normalizer to get tokens with stopwords removed
    // This way "the Beatles" becomes ["beatles"] for better matching
    final normalizedQuery = _searchScorer.normalizer.normalizeQuery(query);
    final queryWords = normalizedQuery.tokensNoStop;

    // Create a set of existing artist identifiers to avoid duplicates
    final existingArtistKeys = <String>{};
    for (final artist in directArtists) {
      existingArtistKeys.add('${artist.provider}:${artist.itemId}');
    }

    // Collect unique artists from tracks and albums
    final candidateArtists = <String, Artist>{};

    for (final track in tracks) {
      if (track.artists != null) {
        for (final artist in track.artists!) {
          final key = '${artist.provider}:${artist.itemId}';
          if (!existingArtistKeys.contains(key) && !candidateArtists.containsKey(key)) {
            candidateArtists[key] = artist;
          }
        }
      }
    }

    for (final album in albums) {
      if (album.artists != null) {
        for (final artist in album.artists!) {
          final key = '${artist.provider}:${artist.itemId}';
          if (!existingArtistKeys.contains(key) && !candidateArtists.containsKey(key)) {
            candidateArtists[key] = artist;
          }
        }
      }
    }

    // Filter candidates: only include if artist name contains any query word
    // (stopwords already removed from queryWords)
    final crossRefArtists = <Artist>[];
    for (final artist in candidateArtists.values) {
      final artistLower = artist.name.toLowerCase();
      for (final word in queryWords) {
        if (word.length >= 3 && artistLower.contains(word)) {
          crossRefArtists.add(artist);
          break;
        }
      }
    }

    return crossRefArtists;
  }

  /// Build list items for a specific filter (used by PageView)
  List<_ListItem> _buildListItemsForFilter(
    String filter,
    List<MediaItem> artists,
    List<MediaItem> albums,
    List<MediaItem> tracks,
    List<MediaItem> playlists,
    List<MediaItem> audiobooks,
    List<MediaItem> radios,
    List<MediaItem> podcasts,
  ) {
    final items = <_ListItem>[];
    final query = _searchController.text;

    // For 'all' filter, create unified relevance-sorted list
    if (filter == 'all') {
      final scoredItems = <_ListItem>[];

      for (final artist in artists) {
        final score = _calculateRelevanceScore(artist, query);
        scoredItems.add(_ListItem.artist(artist, relevanceScore: score));
      }
      for (final album in albums) {
        final score = _calculateRelevanceScore(album, query);
        scoredItems.add(_ListItem.album(album, relevanceScore: score));
      }
      for (final track in tracks) {
        final score = _calculateRelevanceScore(track, query);
        scoredItems.add(_ListItem.track(track, relevanceScore: score));
      }
      for (final playlist in playlists) {
        final score = _calculateRelevanceScore(playlist, query);
        scoredItems.add(_ListItem.playlist(playlist, relevanceScore: score));
      }
      for (final audiobook in audiobooks) {
        final score = _calculateRelevanceScore(audiobook, query);
        scoredItems.add(_ListItem.audiobook(audiobook, relevanceScore: score));
      }
      for (final radio in radios) {
        final score = _calculateRelevanceScore(radio, query);
        scoredItems.add(_ListItem.radio(radio, relevanceScore: score));
      }
      for (final podcast in podcasts) {
        final score = _calculateRelevanceScore(podcast, query);
        scoredItems.add(_ListItem.podcast(podcast, relevanceScore: score));
      }

      final crossRefArtists = _extractCrossReferencedArtists(
        query,
        artists.whereType<Artist>().toList(),
        albums.whereType<Album>().toList(),
        tracks.whereType<Track>().toList(),
      );
      for (final artist in crossRefArtists) {
        scoredItems.add(_ListItem.artist(artist, relevanceScore: 25));
      }

      scoredItems.sort((a, b) => (b.relevanceScore ?? 0).compareTo(a.relevanceScore ?? 0));
      return scoredItems;
    }

    // For specific type filters
    if (filter == 'artists' && artists.isNotEmpty) {
      for (final artist in artists) {
        items.add(_ListItem.artist(artist));
      }
    }

    if (filter == 'albums' && albums.isNotEmpty) {
      for (final album in albums) {
        items.add(_ListItem.album(album));
      }
    }

    if (filter == 'tracks' && tracks.isNotEmpty) {
      for (final track in tracks) {
        items.add(_ListItem.track(track));
      }
    }

    if (filter == 'playlists' && playlists.isNotEmpty) {
      for (final playlist in playlists) {
        items.add(_ListItem.playlist(playlist));
      }
    }

    if (filter == 'audiobooks' && audiobooks.isNotEmpty) {
      for (final audiobook in audiobooks) {
        items.add(_ListItem.audiobook(audiobook));
      }
    }

    if (filter == 'radios' && radios.isNotEmpty) {
      for (final radio in radios) {
        items.add(_ListItem.radio(radio));
      }
    }

    if (filter == 'podcasts' && podcasts.isNotEmpty) {
      for (final podcast in podcasts) {
        items.add(_ListItem.podcast(podcast));
      }
    }

    return items;
  }

  /// Build joined segmented filter selector with animated sliding highlight
  Widget _buildFilterSelector(ColorScheme colorScheme) {
    final filters = _getAvailableFilters();
    final l10n = S.of(context)!;

    String getLabel(String filter) {
      switch (filter) {
        case 'all': return l10n.all;
        case 'artists': return l10n.artists;
        case 'albums': return l10n.albums;
        case 'tracks': return l10n.tracks;
        case 'playlists': return l10n.playlists;
        case 'audiobooks': return l10n.audiobooks;
        case 'radios': return l10n.radio;
        case 'podcasts': return l10n.podcasts;
        default: return filter;
      }
    }

    // Ensure GlobalKeys exist for all filters
    for (final filter in filters) {
      _filterKeys.putIfAbsent(filter, () => GlobalKey());
    }

    // Wrap in ValueListenableBuilder for efficient rebuilds on filter change
    return ValueListenableBuilder<String>(
      valueListenable: _activeFilterNotifier,
      builder: (context, activeFilter, _) {
        // Measure positions after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _measureFilterPositions();
            // Update highlight on first build or when filters change
            final position = _filterPositions[activeFilter];
            final width = _filterWidths[activeFilter];
            if (position != null && width != null &&
                (_highlightLeft != position || _highlightWidth != width)) {
              setState(() {
                _highlightLeft = position;
                _highlightWidth = width;
              });
            }
          }
        });

        final selectedIndex = filters.indexOf(activeFilter);
        final isFirstTab = selectedIndex == 0;
        final isLastTab = selectedIndex == filters.length - 1;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: IntrinsicHeight(
            child: Stack(
              children: [
                // Animated sliding highlight
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  left: _highlightLeft + (isFirstTab ? 0 : 2),
                  width: _highlightWidth - (isFirstTab ? 0 : 2) - (isLastTab ? 0 : 2),
                  top: 0,
                  bottom: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                // Filter buttons row (transparent, on top of highlight)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: filters.map((filter) {
                    final isSelected = activeFilter == filter;
                    return GestureDetector(
                      key: _filterKeys[filter],
                      onTap: () {
                        _activeFilterNotifier.value = filter;
                        _animateToFilter(filter);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Text(
                          getLabel(filter),
                          style: TextStyle(
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant.withOpacity(0.8),
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onBackground,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildArtistTile(Artist artist, {bool showType = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(artist, size: 256);

    const heroSuffix = '_search';
    final artistId = artist.uri ?? artist.itemId;

    return RepaintBoundary(
      child: GestureDetector(
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.artist,
            item: artist,
            isFavorite: artist.favorite ?? false,
            isInLibrary: _isInLibrary(artist),
            onToggleFavorite: () => _toggleArtistFavorite(artist),
            onToggleLibrary: () => _isInLibrary(artist)
                ? _removeFromLibrary(artist, 'artist')
                : _addToLibrary(artist, 'artist'),
          );
        },
        child: ListTile(
          key: ValueKey(artistId),
          leading: Hero(
            tag: HeroTags.artistImage + artistId + heroSuffix,
            child: ArtistAvatar(
              artist: artist,
              radius: 24,
              imageSize: 128,
            ),
          ),
          title: Text(
            artist.name,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: showType
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_buildTypePill('artist', colorScheme)],
                )
              : Text(
                  S.of(context)!.artist,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                ),
          onTap: () {
            updateAdaptiveColorsFromImage(context, imageUrl);
            Navigator.push(
              context,
              FadeSlidePageRoute(
                child: ArtistDetailsScreen(
                  artist: artist,
                  heroTagSuffix: 'search',
                  initialImageUrl: imageUrl,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAlbumTile(Album album, {bool showType = false}) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(album, size: 128);
    final colorScheme = Theme.of(context).colorScheme;

    const heroSuffix = '_search';
    final albumId = album.uri ?? album.itemId;

    return RepaintBoundary(
      child: GestureDetector(
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.album,
            item: album,
            isFavorite: album.favorite ?? false,
            isInLibrary: album.inLibrary,
            onToggleFavorite: () => _toggleAlbumFavorite(album),
            onToggleLibrary: () => album.inLibrary
                ? _removeFromLibrary(album, 'album')
                : _addToLibrary(album, 'album'),
          );
        },
        child: ListTile(
          key: ValueKey(albumId),
          leading: Hero(
            tag: HeroTags.albumCover + albumId + heroSuffix,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                image: imageUrl != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imageUrl == null
                  ? Icon(Icons.album_rounded, color: colorScheme.onSurfaceVariant)
                  : null,
            ),
          ),
          title: Hero(
            tag: HeroTags.albumTitle + albumId + heroSuffix,
            child: Material(
              color: Colors.transparent,
              child: Text(
                album.nameWithYear,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          subtitle: Hero(
            tag: HeroTags.artistName + albumId + heroSuffix,
            child: Material(
              color: Colors.transparent,
              child: showType
                  ? Row(
                      children: [
                        _buildTypePill('album', colorScheme),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            album.artistsString,
                            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      album.artistsString,
                      style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
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
                child: AlbumDetailsScreen(
                  album: album,
                  heroTagSuffix: 'search',
                  initialImageUrl: imageUrl,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrackTile(Track track, {bool showType = false}) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = track.album != null
        ? maProvider.getImageUrl(track.album!, size: 128)
        : null;
    final colorScheme = Theme.of(context).colorScheme;
    final trackId = track.uri ?? track.itemId;

    return RepaintBoundary(
      child: GestureDetector(
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.track,
            item: track,
            isFavorite: track.favorite ?? false,
            isInLibrary: _isInLibrary(track),
            onToggleFavorite: () => _toggleTrackFavorite(track),
            onToggleLibrary: () => _isInLibrary(track)
                ? _removeFromLibrary(track, 'track')
                : _addToLibrary(track, 'track'),
          );
        },
        child: ListTile(
          key: ValueKey(trackId),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              image: imageUrl != null
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imageUrl == null
                ? Icon(Icons.music_note_rounded, color: colorScheme.onSurfaceVariant)
                : null,
          ),
          title: Text(
            track.name,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: showType
              ? Row(
                  children: [
                    _buildTypePill('track', colorScheme),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        track.artistsString,
                        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Text(
                  track.artistsString,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: track.duration != null
              ? Text(
                  _formatDuration(track.duration!),
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
                )
              : null,
          onTap: () => _playTrack(track),
        ),
      ),
    );
  }

  Widget _buildPlaylistTile(Playlist playlist, {bool showType = false}) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(playlist, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final playlistId = playlist.uri ?? playlist.itemId;

    // Unique suffix for search context
    const heroSuffix = '_search';

    return RepaintBoundary(
      child: GestureDetector(
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.playlist,
            item: playlist,
            isFavorite: playlist.favorite ?? false,
            isInLibrary: _isInLibrary(playlist),
            onToggleLibrary: () => _isInLibrary(playlist)
                ? _removeFromLibrary(playlist, 'playlist')
                : _addToLibrary(playlist, 'playlist'),
          );
        },
        child: ListTile(
          key: ValueKey(playlistId),
          leading: Hero(
            tag: HeroTags.playlistCover + playlistId + heroSuffix,
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
                          Icons.queue_music_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(
                        Icons.queue_music_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
              ),
            ),
          ),
          title: Hero(
            tag: HeroTags.playlistTitle + playlistId + heroSuffix,
            child: Material(
              color: Colors.transparent,
              child: Text(
                playlist.name,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          subtitle: showType
              ? Row(
                  children: [
                    _buildTypePill('playlist', colorScheme),
                    if (playlist.owner != null) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          playlist.owner!,
                          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                )
              : Text(
                  playlist.owner ?? S.of(context)!.playlist,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: playlist.trackCount != null
              ? Text(
                  S.of(context)!.trackCount(playlist.trackCount!),
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
                )
              : null,
          onTap: () {
            updateAdaptiveColorsFromImage(context, imageUrl);
            Navigator.push(
              context,
              FadeSlidePageRoute(
                child: PlaylistDetailsScreen(
                  playlist: playlist,
                  heroTagSuffix: 'search',
                  initialImageUrl: imageUrl,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAudiobookTile(Audiobook audiobook, {bool showType = false}) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(audiobook, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final authorText = audiobook.authors?.map((a) => a.name).join(', ') ?? S.of(context)!.unknownAuthor;

    // Use 'search' suffix to avoid hero tag conflicts with library cards
    const heroSuffix = '_search';
    final audiobookId = audiobook.uri ?? audiobook.itemId;

    return RepaintBoundary(
      child: GestureDetector(
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.audiobook,
            item: audiobook,
            isFavorite: audiobook.favorite ?? false,
            isInLibrary: true,
            onToggleFavorite: () => _toggleAudiobookFavorite(audiobook),
          );
        },
        child: ListTile(
          key: ValueKey(audiobookId),
          leading: Hero(
            tag: HeroTags.audiobookCover + audiobookId + heroSuffix,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                image: imageUrl != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imageUrl == null
                  ? Icon(Icons.headphones_rounded, color: colorScheme.onSurfaceVariant)
                  : null,
            ),
          ),
          title: Hero(
            tag: HeroTags.audiobookTitle + audiobookId + heroSuffix,
            child: Material(
              color: Colors.transparent,
              child: Text(
                audiobook.name,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          subtitle: showType
              ? Row(
                  children: [
                    _buildTypePill('audiobook', colorScheme),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        authorText,
                        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Text(
                  authorText,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: audiobook.duration != null
              ? Text(
                  _formatDuration(audiobook.duration!),
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
                )
              : null,
          onTap: () {
            // Update adaptive colors before navigation
            updateAdaptiveColorsFromImage(context, imageUrl);
            Navigator.push(
              context,
              FadeSlidePageRoute(
                child: AudiobookDetailScreen(
                  audiobook: audiobook,
                  heroTagSuffix: 'search',
                  initialImageUrl: imageUrl,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRadioTile(MediaItem radio, {bool showType = false}) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(radio, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final radioId = radio.uri ?? radio.itemId;

    return RepaintBoundary(
      child: GestureDetector(
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.radio,
            item: radio,
            isFavorite: false,
            isInLibrary: true,
          );
        },
        child: ListTile(
          key: ValueKey(radioId),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              image: imageUrl != null
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imageUrl == null
                ? Icon(Icons.radio_rounded, color: colorScheme.onSurfaceVariant)
                : null,
          ),
          title: Text(
            radio.name,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: showType
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_buildTypePill('radio', colorScheme)],
                )
              : Text(
                  S.of(context)!.radio,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => _playRadioStation(radio),
        ),
      ),
    );
  }

  Widget _buildPodcastTile(MediaItem podcast, {bool showType = false}) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getPodcastImageUrl(podcast, size: 128);
    final colorScheme = Theme.of(context).colorScheme;

    // Use 'search' suffix to avoid hero tag conflicts with library cards
    const heroSuffix = '_search';
    final podcastId = podcast.uri ?? podcast.itemId;

    return RepaintBoundary(
      child: GestureDetector(
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.podcast,
            item: podcast,
            isFavorite: false,
            isInLibrary: true,
          );
        },
        child: ListTile(
          key: ValueKey(podcastId),
          leading: Hero(
            tag: HeroTags.podcastCover + podcastId + heroSuffix,
            // Match library/detail pattern: ClipRRect(16) → Container → CachedNetworkImage
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 48,
                height: 48,
                color: colorScheme.surfaceContainerHighest,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, __) => const SizedBox(),
                        errorWidget: (_, __, ___) => Icon(Icons.podcasts_rounded, color: colorScheme.onSurfaceVariant),
                      )
                    : Icon(Icons.podcasts_rounded, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          title: Text(
            podcast.name,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: showType
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_buildTypePill('podcast', colorScheme)],
                )
              : Text(
                  S.of(context)!.podcasts,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () {
            // Update adaptive colors before navigation
            updateAdaptiveColorsFromImage(context, imageUrl);
            Navigator.push(
              context,
              FadeSlidePageRoute(
                child: PodcastDetailScreen(
                  podcast: podcast,
                  heroTagSuffix: 'search',
                  initialImageUrl: imageUrl,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _playRadioStation(MediaItem station) async {
    final maProvider = context.read<MusicAssistantProvider>();

    if (maProvider.selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.api?.playRadioStation(
        maProvider.selectedPlayer!.playerId,
        station,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.playingRadioStation(station.name)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToPlayRadioStation(e.toString()))),
        );
      }
    }
  }

  Future<void> _playTrack(Track track) async {
    final maProvider = context.read<MusicAssistantProvider>();

    if (maProvider.selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    // Use Music Assistant to play the track on the selected player
    await maProvider.playTrack(
      maProvider.selectedPlayer!.playerId,
      track,
    );
  }

  /// Play track radio on current player (1 tap)
  Future<void> _playRadio(Track track) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.playRadio(player.playerId, track);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.startingRadio(track.name)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToStartRadio(e.toString()))),
        );
      }
    }
  }

  /// Show player picker for Radio On (2 taps)
  void _showRadioOnMenu(Track track) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerForRadio,
      onPlayerSelected: (player) async {
        try {
          maProvider.selectPlayer(player);
          await maProvider.playRadio(player.playerId, track);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.startingRadioOnPlayer(track.name, player.name)),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context)!.failedToStartRadio(e.toString()))),
            );
          }
        }
      },
    );
  }

  /// Add track to queue on current player (1 tap)
  Future<void> _addToQueue(Track track) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.addTrackToQueue(player.playerId, track);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.addedToQueue),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToAddToQueue(e.toString()))),
        );
      }
    }
  }

  Future<void> _toggleTrackFavorite(Track track) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final currentFavorite = track.favorite ?? false;

    try {
      bool success;

      if (currentFavorite) {
        // Remove from favorites
        int? libraryItemId;
        if (track.provider == 'library') {
          libraryItemId = int.tryParse(track.itemId);
        } else if (track.providerMappings != null) {
          final libraryMapping = track.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => track.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromFavorites(
            mediaType: 'track',
            libraryItemId: libraryItemId,
          );
        } else {
          success = false;
        }
      } else {
        // Add to favorites
        String actualProvider = track.provider;
        String actualItemId = track.itemId;

        if (track.providerMappings != null && track.providerMappings!.isNotEmpty) {
          final mapping = track.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => track.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => track.providerMappings!.first,
            ),
          );
          // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'track',
          provider: actualProvider,
          itemId: actualItemId,
        );
      }

      if (success && mounted) {
        // Update the track's favorite state in search results
        setState(() {
          final tracks = _searchResults['tracks'] as List<Track>?;
          if (tracks != null) {
            final index = tracks.indexWhere((t) => (t.uri ?? t.itemId) == (track.uri ?? track.itemId));
            if (index != -1) {
              // Create updated track with new favorite state
              final updatedTrack = Track.fromJson({
                ...tracks[index].toJson(),
                'favorite': !currentFavorite,
              });
              tracks[index] = updatedTrack;
            }
          }
        });
      }
    } catch (e) {
      _logger.log('Error toggling favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToUpdateFavorite(e.toString()))),
        );
      }
    }
  }

  /// Check if a media item is in the library
  /// Uses local tracking to reflect changes made in this session
  bool _isInLibrary(MediaItem item) {
    final itemKey = '${item.mediaType.name}:${item.itemId}';

    // Check local state first (overrides server state for this session)
    if (_addedToLibrary.contains(itemKey)) return true;
    if (_removedFromLibrary.contains(itemKey)) return false;

    // Fall back to server state
    if (item.provider == 'library') return true;
    return item.providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
  }

  /// Add media item to library
  Future<void> _addToLibrary(MediaItem item, String mediaTypeKey) async {
    final maProvider = context.read<MusicAssistantProvider>();

    // Get provider info for adding - MUST use non-library provider
    String? actualProvider;
    String? actualItemId;

    if (item.providerMappings != null && item.providerMappings!.isNotEmpty) {
      // For adding to library, we MUST use a non-library provider
      // Availability doesn't matter - we just need the external provider's ID
      final nonLibraryMapping = item.providerMappings!.where(
        (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
      ).firstOrNull;

      if (nonLibraryMapping != null) {
        // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
        actualProvider = nonLibraryMapping.providerDomain;
        actualItemId = nonLibraryMapping.itemId;
      }
    }

    // Fallback to item's own provider if no non-library mapping found
    if (actualProvider == null || actualItemId == null) {
      if (item.provider != 'library') {
        actualProvider = item.provider;
        actualItemId = item.itemId;
      } else {
        // Item is library-only, can't add
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context)!.itemAlreadyInLibrary)),
          );
        }
        return;
      }
    }

    // OPTIMISTIC UPDATE: Update UI immediately, don't wait for API
    final itemKey = '${item.mediaType.name}:${item.itemId}';
    _addedToLibrary.add(itemKey);
    _removedFromLibrary.remove(itemKey);
    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context)!.addedToLibrary),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    // Fire and forget - API call happens in background
    // Even if it times out, MA usually processes it successfully
    maProvider.addToLibrary(
      mediaType: mediaTypeKey,
      provider: actualProvider,
      itemId: actualItemId,
    ).catchError((e) {
      _logger.log('Error adding to library: $e');
      // Only revert on actual errors, not timeouts (MA usually succeeds anyway)
      if (!e.toString().contains('timeout')) {
        _addedToLibrary.remove(itemKey);
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context)!.failedToAddToLibrary)),
          );
        }
      }
    });
  }

  /// Remove media item from library
  Future<void> _removeFromLibrary(MediaItem item, String mediaTypeKey) async {
    final maProvider = context.read<MusicAssistantProvider>();

    // Get library item ID for removal
    int? libraryItemId;
    if (item.provider == 'library') {
      libraryItemId = int.tryParse(item.itemId);
    } else if (item.providerMappings != null) {
      final libraryMapping = item.providerMappings!.firstWhere(
        (m) => m.providerInstance == 'library',
        orElse: () => item.providerMappings!.first,
      );
      if (libraryMapping.providerInstance == 'library') {
        libraryItemId = int.tryParse(libraryMapping.itemId);
      }
    }

    if (libraryItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.cannotFindLibraryId)),
      );
      return;
    }

    // OPTIMISTIC UPDATE: Update UI immediately, don't wait for API
    final itemKey = '${item.mediaType.name}:${item.itemId}';
    _removedFromLibrary.add(itemKey);
    _addedToLibrary.remove(itemKey);
    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context)!.removedFromLibrary),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    // Fire and forget - API call happens in background
    maProvider.removeFromLibrary(
      mediaType: mediaTypeKey,
      libraryItemId: libraryItemId,
    ).catchError((e) {
      _logger.log('Error removing from library: $e');
      // Only revert on actual errors, not timeouts
      if (!e.toString().contains('timeout')) {
        _removedFromLibrary.remove(itemKey);
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context)!.failedToRemoveFromLibrary)),
          );
        }
      }
    });
  }

  /// Play artist radio on current player
  Future<void> _playArtistRadio(Artist artist) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.playArtistRadio(player.playerId, artist);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.startingRadio(artist.name)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToStartRadio(e.toString()))),
        );
      }
    }
  }

  /// Add artist's tracks to queue
  Future<void> _addArtistToQueue(Artist artist) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.api?.addArtistToQueue(player.playerId, artist);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.addedToQueue),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToAddToQueue(e.toString()))),
        );
      }
    }
  }

  /// Toggle artist favorite status
  Future<void> _toggleArtistFavorite(Artist artist) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final currentFavorite = artist.favorite ?? false;

    try {
      bool success;

      if (currentFavorite) {
        // Remove from favorites
        int? libraryItemId;
        if (artist.provider == 'library') {
          libraryItemId = int.tryParse(artist.itemId);
        } else if (artist.providerMappings != null) {
          final libraryMapping = artist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => artist.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromFavorites(
            mediaType: 'artist',
            libraryItemId: libraryItemId,
          );
        } else {
          success = false;
        }
      } else {
        // Add to favorites
        String actualProvider = artist.provider;
        String actualItemId = artist.itemId;

        if (artist.providerMappings != null && artist.providerMappings!.isNotEmpty) {
          final mapping = artist.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => artist.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => artist.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'artist',
          provider: actualProvider,
          itemId: actualItemId,
        );
      }

      if (success && mounted) {
        setState(() {
          final artists = _searchResults['artists'] as List<MediaItem>?;
          if (artists != null) {
            final index = artists.indexWhere((a) => (a.uri ?? a.itemId) == (artist.uri ?? artist.itemId));
            if (index != -1) {
              // Create updated artist with new favorite state
              final updatedArtist = Artist.fromJson({
                ...artists[index].toJson(),
                'favorite': !currentFavorite,
              });
              artists[index] = updatedArtist;
            }
          }
        });
      }
    } catch (e) {
      _logger.log('Error toggling artist favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToUpdateFavorite(e.toString()))),
        );
      }
    }
  }

  /// Play album on current player
  Future<void> _playAlbum(Album album) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.api?.playAlbum(player.playerId, album);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.playingAlbum(album.name)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToPlayAlbum(e.toString()))),
        );
      }
    }
  }

  /// Show player picker for album
  void _showAlbumPlayOnMenu(Album album) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerToPlayAlbum,
      onPlayerSelected: (player) async {
        try {
          maProvider.selectPlayer(player);
          await maProvider.api?.playAlbum(player.playerId, album);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.playingOnPlayer(album.name, player.name)),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context)!.failedToPlayAlbum(e.toString()))),
            );
          }
        }
      },
    );
  }

  /// Add album to queue
  Future<void> _addAlbumToQueue(Album album) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.api?.addAlbumToQueue(player.playerId, album);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.addedToQueue),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToAddToQueue(e.toString()))),
        );
      }
    }
  }

  /// Toggle album favorite status
  Future<void> _toggleAlbumFavorite(Album album) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final currentFavorite = album.favorite ?? false;

    try {
      bool success;

      if (currentFavorite) {
        // Remove from favorites
        int? libraryItemId;
        if (album.provider == 'library') {
          libraryItemId = int.tryParse(album.itemId);
        } else if (album.providerMappings != null) {
          final libraryMapping = album.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => album.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromFavorites(
            mediaType: 'album',
            libraryItemId: libraryItemId,
          );
        } else {
          success = false;
        }
      } else {
        // Add to favorites
        String actualProvider = album.provider;
        String actualItemId = album.itemId;

        if (album.providerMappings != null && album.providerMappings!.isNotEmpty) {
          final mapping = album.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => album.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => album.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'album',
          provider: actualProvider,
          itemId: actualItemId,
        );
      }

      if (success && mounted) {
        setState(() {
          final albums = _searchResults['albums'] as List<MediaItem>?;
          if (albums != null) {
            final index = albums.indexWhere((a) => (a.uri ?? a.itemId) == (album.uri ?? album.itemId));
            if (index != -1) {
              // Create updated album with new favorite state
              final updatedAlbum = Album.fromJson({
                ...albums[index].toJson(),
                'favorite': !currentFavorite,
              });
              albums[index] = updatedAlbum;
            }
          }
        });
      }
    } catch (e) {
      _logger.log('Error toggling album favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToUpdateFavorite(e.toString()))),
        );
      }
    }
  }

  /// Play playlist on current player
  Future<void> _playPlaylist(Playlist playlist) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.api?.playPlaylist(player.playerId, playlist);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.playingPlaylist(playlist.name)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToPlayPlaylist(e.toString()))),
        );
      }
    }
  }

  /// Show player picker for playlist
  void _showPlaylistPlayOnMenu(Playlist playlist) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerToPlayPlaylist,
      onPlayerSelected: (player) async {
        try {
          maProvider.selectPlayer(player);
          await maProvider.api?.playPlaylist(player.playerId, playlist);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.playingOnPlayer(playlist.name, player.name)),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context)!.failedToPlayPlaylist(e.toString()))),
            );
          }
        }
      },
    );
  }

  /// Play audiobook on current player
  Future<void> _playAudiobook(Audiobook audiobook) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.api?.playAudiobook(player.playerId, audiobook);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.playing(audiobook.name)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToPlayAudiobook(e.toString()))),
        );
      }
    }
  }

  /// Show player picker for audiobook
  void _showAudiobookPlayOnMenu(Audiobook audiobook) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerForAudiobook,
      onPlayerSelected: (player) async {
        try {
          maProvider.selectPlayer(player);
          await maProvider.api?.playAudiobook(player.playerId, audiobook);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.playingOnPlayer(audiobook.name, player.name)),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context)!.failedToPlayAudiobook(e.toString()))),
            );
          }
        }
      },
    );
  }

  /// Toggle audiobook favorite status
  Future<void> _toggleAudiobookFavorite(Audiobook audiobook) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final currentFavorite = audiobook.favorite ?? false;

    try {
      bool success;

      if (currentFavorite) {
        // Remove from favorites
        int? libraryItemId;
        if (audiobook.provider == 'library') {
          libraryItemId = int.tryParse(audiobook.itemId);
        } else if (audiobook.providerMappings != null) {
          final libraryMapping = audiobook.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => audiobook.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromFavorites(
            mediaType: 'audiobook',
            libraryItemId: libraryItemId,
          );
        } else {
          success = false;
        }
      } else {
        // Add to favorites
        String actualProvider = audiobook.provider;
        String actualItemId = audiobook.itemId;

        if (audiobook.providerMappings != null && audiobook.providerMappings!.isNotEmpty) {
          final mapping = audiobook.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => audiobook.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => audiobook.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'audiobook',
          provider: actualProvider,
          itemId: actualItemId,
        );
      }

      if (success && mounted) {
        setState(() {
          final audiobooks = _searchResults['audiobooks'] as List<MediaItem>?;
          if (audiobooks != null) {
            final index = audiobooks.indexWhere((a) => (a.uri ?? a.itemId) == (audiobook.uri ?? audiobook.itemId));
            if (index != -1) {
              // Create updated audiobook with new favorite state
              final updatedAudiobook = Audiobook.fromJson({
                ...audiobooks[index].toJson(),
                'favorite': !currentFavorite,
              });
              audiobooks[index] = updatedAudiobook;
            }
          }
        });
      }
    } catch (e) {
      _logger.log('Error toggling audiobook favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToUpdateFavorite(e.toString()))),
        );
      }
    }
  }

  /// Show player picker for radio station
  void _showRadioPlayOnMenu(MediaItem radio) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerForRadio,
      onPlayerSelected: (player) async {
        try {
          maProvider.selectPlayer(player);
          await maProvider.api?.playRadioStation(player.playerId, radio);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.playingOnPlayer(radio.name, player.name)),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context)!.failedToPlayRadioStation(e.toString()))),
            );
          }
        }
      },
    );
  }

  /// Play podcast (navigate to detail screen where episodes can be played)
  Future<void> _playPodcast(MediaItem podcast) async {
    // For podcasts, we navigate to the detail screen where episodes can be selected
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getPodcastImageUrl(podcast, size: 128);
    updateAdaptiveColorsFromImage(context, imageUrl);

    if (mounted) {
      Navigator.push(
        context,
        FadeSlidePageRoute(
          child: PodcastDetailScreen(
            podcast: podcast,
            heroTagSuffix: 'search',
            initialImageUrl: imageUrl,
          ),
        ),
      );
    }
  }

  /// Show player picker for podcast
  void _showPodcastPlayOnMenu(MediaItem podcast) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerToPlay,
      onPlayerSelected: (player) async {
        // Select the player, then navigate to podcast detail
        maProvider.selectPlayer(player);
        final imageUrl = maProvider.getPodcastImageUrl(podcast, size: 128);
        updateAdaptiveColorsFromImage(context, imageUrl);

        if (mounted) {
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: PodcastDetailScreen(
                podcast: podcast,
                heroTagSuffix: 'search',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        }
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Build a colored type pill for media type identification in search results
  Widget _buildTypePill(String type, ColorScheme colorScheme) {
    Color backgroundColor;
    Color textColor;
    String label;

    switch (type) {
      case 'track':
        backgroundColor = Colors.blue.shade100;
        textColor = Colors.blue.shade800;
        label = S.of(context)!.trackSingular;
        break;
      case 'album':
        backgroundColor = Colors.purple.shade100;
        textColor = Colors.purple.shade800;
        label = S.of(context)!.albumSingular;
        break;
      case 'artist':
        backgroundColor = Colors.pink.shade100;
        textColor = Colors.pink.shade800;
        label = S.of(context)!.artist;
        break;
      case 'playlist':
        backgroundColor = Colors.teal.shade100;
        textColor = Colors.teal.shade800;
        label = S.of(context)!.playlist;
        break;
      case 'audiobook':
        backgroundColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        label = S.of(context)!.audiobookSingular;
        break;
      case 'radio':
        backgroundColor = Colors.red.shade100;
        textColor = Colors.red.shade800;
        label = S.of(context)!.radio;
        break;
      case 'podcast':
        backgroundColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        label = S.of(context)!.podcastSingular;
        break;
      default:
        backgroundColor = colorScheme.surfaceVariant;
        textColor = colorScheme.onSurfaceVariant;
        label = type;
    }

    // For dark mode, use darker variants
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      switch (type) {
        case 'track':
          backgroundColor = Colors.blue.shade900.withOpacity(0.5);
          textColor = Colors.blue.shade200;
          break;
        case 'album':
          backgroundColor = Colors.purple.shade900.withOpacity(0.5);
          textColor = Colors.purple.shade200;
          break;
        case 'artist':
          backgroundColor = Colors.pink.shade900.withOpacity(0.5);
          textColor = Colors.pink.shade200;
          break;
        case 'playlist':
          backgroundColor = Colors.teal.shade900.withOpacity(0.5);
          textColor = Colors.teal.shade200;
          break;
        case 'audiobook':
          backgroundColor = Colors.orange.shade900.withOpacity(0.5);
          textColor = Colors.orange.shade200;
          break;
        case 'radio':
          backgroundColor = Colors.red.shade900.withOpacity(0.5);
          textColor = Colors.red.shade200;
          break;
        case 'podcast':
          backgroundColor = Colors.green.shade900.withOpacity(0.5);
          textColor = Colors.green.shade200;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Fast settling physics for horizontal page swipes.
/// Reduces the time the page animation takes to settle, so vertical scrolling
/// within the page becomes responsive sooner after a horizontal swipe.
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
