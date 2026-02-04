import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import 'album_card.dart';

class AlbumRow extends StatefulWidget {
  final String title;
  final Future<List<Album>> Function() loadAlbums;
  final String? heroTagSuffix;
  final double? rowHeight;
  /// Optional: synchronous getter for cached data (for instant display)
  final List<Album>? Function()? getCachedAlbums;

  const AlbumRow({
    super.key,
    required this.title,
    required this.loadAlbums,
    this.heroTagSuffix,
    this.rowHeight,
    this.getCachedAlbums,
  });

  @override
  State<AlbumRow> createState() => _AlbumRowState();
}

class _AlbumRowState extends State<AlbumRow> with AutomaticKeepAliveClientMixin {
  List<Album> _albums = [];
  bool _isLoading = true;
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Get cached data synchronously BEFORE first build (no spinner flash)
    final cached = widget.getCachedAlbums?.call();
    if (cached != null && cached.isNotEmpty) {
      _albums = cached;
      _isLoading = false;
    }
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    // Load fresh data (always update - fresh data may have images that cached data lacks)
    try {
      final freshAlbums = await widget.loadAlbums();
      if (mounted && freshAlbums.isNotEmpty) {
        setState(() {
          _albums = freshAlbums;
          _isLoading = false;
        });
        // Pre-cache images for smooth hero animations
        _precacheAlbumImages(freshAlbums);
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  /// Pre-cache album images so hero animations are smooth on first tap
  void _precacheAlbumImages(List<Album> albums) {
    if (!mounted) return;
    final maProvider = context.read<MusicAssistantProvider>();

    // Only precache first ~10 visible items to avoid excessive network/memory use
    final albumsToCache = albums.take(10);

    for (final album in albumsToCache) {
      final imageUrl = maProvider.api?.getImageUrl(album, size: 256);
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
    if (_albums.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_albums.isEmpty) {
      return Center(
        child: Text(
          S.of(context)!.noAlbumsFound,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }

    // Card layout: square artwork + text below
    // Text area: 8px gap + ~18px title + ~18px artist = ~44px
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
        itemCount: _albums.length,
        itemExtent: itemExtent,
        cacheExtent: 500, // Preload ~3 items ahead for smoother scrolling
        addAutomaticKeepAlives: false, // Row already uses AutomaticKeepAliveClientMixin
        addRepaintBoundaries: false, // Cards already have RepaintBoundary
        itemBuilder: (context, index) {
          final album = _albums[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Container(
              key: ValueKey(album.uri ?? album.itemId),
              width: cardWidth,
              margin: const EdgeInsets.symmetric(horizontal: 6.0),
              child: AlbumCard(
                album: album,
                heroTagSuffix: widget.heroTagSuffix,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('AlbumRow:${widget.title}');
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
    _logger.endBuild('AlbumRow:${widget.title}');
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

