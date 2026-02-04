import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import 'podcast_card.dart';

class PodcastRow extends StatefulWidget {
  final String title;
  final Future<List<MediaItem>> Function() loadPodcasts;
  final String? heroTagSuffix;
  final double? rowHeight;
  /// Optional: synchronous getter for cached data (for instant display)
  final List<MediaItem>? Function()? getCachedPodcasts;

  const PodcastRow({
    super.key,
    required this.title,
    required this.loadPodcasts,
    this.heroTagSuffix,
    this.rowHeight,
    this.getCachedPodcasts,
  });

  @override
  State<PodcastRow> createState() => _PodcastRowState();
}

class _PodcastRowState extends State<PodcastRow> with AutomaticKeepAliveClientMixin {
  List<MediaItem> _podcasts = [];
  bool _isLoading = true;
  bool _hasLoaded = false;

  static final _logger = DebugLogger();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Get cached data synchronously BEFORE first build (no spinner flash)
    final cached = widget.getCachedPodcasts?.call();
    if (cached != null && cached.isNotEmpty) {
      _podcasts = cached;
      _isLoading = false;
    }
    _loadPodcasts();
  }

  Future<void> _loadPodcasts() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    // Load fresh data (always update - fresh data may have images that cached data lacks)
    try {
      final freshPodcasts = await widget.loadPodcasts();
      if (mounted && freshPodcasts.isNotEmpty) {
        setState(() {
          _podcasts = freshPodcasts;
          _isLoading = false;
        });
        // Pre-cache images for smooth hero animations
        _precachePodcastImages(freshPodcasts);
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  /// Pre-cache podcast images so hero animations are smooth on first tap
  void _precachePodcastImages(List<MediaItem> podcasts) {
    if (!mounted) return;
    final maProvider = context.read<MusicAssistantProvider>();

    // Only precache first ~10 visible items to avoid excessive network/memory use
    final podcastsToCache = podcasts.take(10);

    for (final podcast in podcastsToCache) {
      // Use getPodcastImageUrl which includes iTunes cache
      final imageUrl = maProvider.getPodcastImageUrl(podcast, size: 256);
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

  Widget _buildContent(double contentHeight, ColorScheme colorScheme) {
    // Only show loading if we have no data at all
    if (_podcasts.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_podcasts.isEmpty) {
      return Center(
        child: Text(
          S.of(context)!.noPodcasts,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }

    // Card layout: square artwork + text below (same as AlbumRow)
    // Text area: 8px gap + ~18px title + ~18px author = ~44px
    const textAreaHeight = 44.0;
    final artworkSize = contentHeight - textAreaHeight;
    final cardWidth = artworkSize; // Card width = artwork width (square)
    final itemExtent = cardWidth + 12; // width + horizontal margins

    return ScrollConfiguration(
      behavior: const _StretchScrollBehavior(),
      child: ListView.builder(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: _podcasts.length,
        itemExtent: itemExtent,
        cacheExtent: 500, // Preload ~3 items ahead for smoother scrolling
        addAutomaticKeepAlives: false, // Row already uses AutomaticKeepAliveClientMixin
        addRepaintBoundaries: false, // Cards already have RepaintBoundary
        itemBuilder: (context, index) {
          final podcast = _podcasts[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Container(
              key: ValueKey(podcast.uri ?? podcast.itemId),
              width: cardWidth,
              margin: const EdgeInsets.symmetric(horizontal: 6.0),
              child: PodcastCard(
                podcast: podcast,
                heroTagSuffix: widget.heroTagSuffix,
                imageCacheSize: 256,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('PodcastRow:${widget.title}');
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Total row height includes title + content (same as AlbumRow)
    final totalHeight = widget.rowHeight ?? 237.0; // Default: 44 title + 193 content
    const titleHeight = 44.0; // 12 top padding + ~24 text + 8 bottom padding
    final contentHeight = totalHeight - titleHeight;

    final result = RepaintBoundary(
      child: SizedBox(
        height: totalHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
              child: Text(
                widget.title,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onBackground,
                ),
              ),
            ),
            Expanded(
              child: _buildContent(contentHeight, colorScheme),
            ),
          ],
        ),
      ),
    );
    _logger.endBuild('PodcastRow:${widget.title}');
    return result;
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
