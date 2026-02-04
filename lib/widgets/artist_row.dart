import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import 'artist_card.dart';

class ArtistRow extends StatefulWidget {
  final String title;
  final Future<List<Artist>> Function() loadArtists;
  final String? heroTagSuffix;
  final double? rowHeight;
  /// Optional: synchronous getter for cached data (for instant display)
  final List<Artist>? Function()? getCachedArtists;

  const ArtistRow({
    super.key,
    required this.title,
    required this.loadArtists,
    this.heroTagSuffix,
    this.rowHeight,
    this.getCachedArtists,
  });

  @override
  State<ArtistRow> createState() => _ArtistRowState();
}

class _ArtistRowState extends State<ArtistRow> with AutomaticKeepAliveClientMixin {
  List<Artist> _artists = [];
  bool _isLoading = true;
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Get cached data synchronously BEFORE first build (no spinner flash)
    final cached = widget.getCachedArtists?.call();
    if (cached != null && cached.isNotEmpty) {
      _artists = cached;
      _isLoading = false;
    }
    _loadArtists();
  }

  Future<void> _loadArtists() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    // Load fresh data (always update - fresh data may have images that cached data lacks)
    try {
      final freshArtists = await widget.loadArtists();
      if (mounted && freshArtists.isNotEmpty) {
        setState(() {
          _artists = freshArtists;
          _isLoading = false;
        });
        // Pre-cache images for smooth hero animations
        _precacheArtistImages(freshArtists);
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  /// Pre-cache artist images so hero animations are smooth on first tap
  void _precacheArtistImages(List<Artist> artists) {
    if (!mounted) return;
    final maProvider = context.read<MusicAssistantProvider>();

    // Only precache first ~10 visible items to avoid excessive network/memory use
    final artistsToCache = artists.take(10);

    for (final artist in artistsToCache) {
      final imageUrl = maProvider.api?.getImageUrl(artist, size: 256);
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
    if (_artists.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_artists.isEmpty) {
      return Center(
        child: Text(
          S.of(context)!.noArtistsFound,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }

    // Card layout: circle image + name below
    // Text area: 8px gap + ~36px for 2-line name = ~44px
    const textAreaHeight = 44.0;
    final imageSize = contentHeight - textAreaHeight;
    final cardWidth = imageSize; // Card width = image width (circle)
    final itemExtent = cardWidth + 16; // width + horizontal margins

    return ScrollConfiguration(
      behavior: const _StretchScrollBehavior(),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: _artists.length,
        itemExtent: itemExtent,
        cacheExtent: 500, // Preload ~3 items ahead for smoother scrolling
        addAutomaticKeepAlives: false, // Row already uses AutomaticKeepAliveClientMixin
        addRepaintBoundaries: false, // Cards already have RepaintBoundary
        itemBuilder: (context, index) {
          final artist = _artists[index];
          return Container(
            key: ValueKey(artist.uri ?? artist.itemId),
            width: cardWidth,
            margin: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ArtistCard(
              artist: artist,
              heroTagSuffix: widget.heroTagSuffix,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('ArtistRow:${widget.title}');
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Total row height includes title + content
    final totalHeight = widget.rowHeight ?? 207.0; // Default: 44 title + 163 content
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
    _logger.endBuild('ArtistRow:${widget.title}');
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
