import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import 'playlist_card.dart';
import 'radio_station_card.dart';

class DiscoveryRow extends StatefulWidget {
  final String title;
  final Future<List<MediaItem>> Function() loadItems;
  final String? heroTagSuffix;
  final double? rowHeight;
  /// Optional: synchronous getter for cached data (for instant display)
  final List<MediaItem>? Function()? getCachedItems;

  const DiscoveryRow({
    super.key,
    required this.title,
    required this.loadItems,
    this.heroTagSuffix,
    this.rowHeight,
    this.getCachedItems,
  });

  @override
  State<DiscoveryRow> createState() => _DiscoveryRowState();
}

class _DiscoveryRowState extends State<DiscoveryRow> with AutomaticKeepAliveClientMixin {
  List<MediaItem> _items = [];
  bool _isLoading = true;
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Get cached data synchronously BEFORE first build (no spinner flash)
    final cached = widget.getCachedItems?.call();
    if (cached != null && cached.isNotEmpty) {
      _items = cached;
      _isLoading = false;
    }
    _loadItems();
  }

  Future<void> _loadItems() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    // Load fresh data (always update - fresh data may have images that cached data lacks)
    try {
      final freshItems = await widget.loadItems();
      if (mounted && freshItems.isNotEmpty) {
        setState(() {
          _items = freshItems;
          _isLoading = false;
        });
        // Pre-cache images for smooth hero animations
        _precacheImages(freshItems);
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  /// Pre-cache images so hero animations are smooth on first tap
  void _precacheImages(List<MediaItem> items) {
    if (!mounted) return;
    final maProvider = context.read<MusicAssistantProvider>();

    // Only precache first ~10 visible items to avoid excessive network/memory use
    final itemsToCache = items.take(10);

    for (final item in itemsToCache) {
      final imageUrl = maProvider.api?.getImageUrl(item, size: 256);
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

  static final _logger = DebugLogger();

  Widget _buildContent(double contentHeight, ColorScheme colorScheme) {
    // Only show loading if we have no data at all
    if (_items.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          S.of(context)!.noAlbumsFound,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }

    // Card layout: square artwork + text below
    // Text area: 8px gap + ~20px title + ~20px subtitle = ~48px
    const textAreaHeight = 48.0;
    final artworkSize = contentHeight - textAreaHeight;
    final cardWidth = artworkSize; // Card width = artwork width (square)
    final itemExtent = cardWidth + 12; // width + horizontal margins

    return ScrollConfiguration(
      behavior: const _StretchScrollBehavior(),
      child: ListView.builder(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: _items.length,
        itemExtent: itemExtent,
        cacheExtent: 500, // Preload ~3 items ahead for smoother scrolling
        addAutomaticKeepAlives: false, // Row already uses AutomaticKeepAliveClientMixin
        addRepaintBoundaries: false, // Cards already have RepaintBoundary
        itemBuilder: (context, index) {
          final item = _items[index];
          final key = ValueKey(item.uri ?? item.itemId);

          Widget card;
          if (item is Playlist) {
            card = PlaylistCard(
              playlist: item,
              heroTagSuffix: widget.heroTagSuffix,
              imageCacheSize: 256,
            );
          } else if (item.mediaType == MediaType.radio) {
            card = RadioStationCard(
              radioStation: item,
              heroTagSuffix: widget.heroTagSuffix,
              imageCacheSize: 256,
            );
          } else {
            // Fallback for other media types
            card = _buildFallbackCard(item, cardWidth);
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Container(
              key: key,
              width: cardWidth,
              margin: const EdgeInsets.symmetric(horizontal: 6.0),
              child: card,
            ),
          );
        },
      ),
    );
  }

  Widget _buildFallbackCard(MediaItem item, double width) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getIconForMediaType(item.mediaType),
                size: 48,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: Text(
              item.name,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForMediaType(MediaType type) {
    switch (type) {
      case MediaType.album:
        return Icons.album;
      case MediaType.artist:
        return Icons.person;
      case MediaType.track:
        return Icons.music_note;
      case MediaType.playlist:
        return Icons.playlist_play;
      case MediaType.radio:
        return Icons.radio;
      case MediaType.audiobook:
        return Icons.book;
      case MediaType.podcast:
        return Icons.podcasts;
      case MediaType.podcastEpisode:
        return Icons.podcasts;
      default:
        return Icons.audiotrack;
    }
  }

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('DiscoveryRow:${widget.title}');
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Total row height includes title + content
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
    _logger.endBuild('DiscoveryRow:${widget.title}');
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
