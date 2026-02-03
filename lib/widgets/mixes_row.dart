import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../models/media_item.dart';
import '../models/recommendation_folder.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import 'playlist_card.dart';
import 'radio_station_card.dart';

class MixesRow extends StatefulWidget {
  final String title;
  final Future<List<RecommendationFolder>> Function() loadMixes;
  final List<RecommendationFolder>? Function()? getCachedMixes;
  final String? heroTagSuffix;
  final double? rowHeight;

  const MixesRow({
    super.key,
    required this.title,
    required this.loadMixes,
    this.getCachedMixes,
    this.heroTagSuffix,
    this.rowHeight,
  });

  @override
  State<MixesRow> createState() => _MixesRowState();
}

class _MixesRowState extends State<MixesRow> with AutomaticKeepAliveClientMixin {
  List<RecommendationFolder> _mixes = [];
  bool _isLoading = true;
  bool _hasLoaded = false;

  static final _logger = DebugLogger();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final cached = widget.getCachedMixes?.call();
    if (cached != null && cached.isNotEmpty) {
      _mixes = cached;
      _isLoading = false;
    }
    _loadMixes();
  }

  Future<void> _loadMixes() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    try {
      final freshMixes = await widget.loadMixes();
      if (mounted && freshMixes.isNotEmpty) {
        setState(() {
          _mixes = freshMixes;
          _isLoading = false;
        });
        _precacheMixImages(freshMixes);
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  void _precacheMixImages(List<RecommendationFolder> mixes) {
    if (!mounted) return;
    final maProvider = context.read<MusicAssistantProvider>();

    final itemsToCache = <MediaItem>[];
    for (final folder in mixes) {
      itemsToCache.addAll(folder.items);
      if (itemsToCache.length >= 10) break;
    }

    for (final mix in itemsToCache.take(10)) {
      final imageUrl = maProvider.api?.getImageUrl(mix, size: 256);
      if (imageUrl != null) {
        precacheImage(
          CachedNetworkImageProvider(imageUrl),
          context,
        ).catchError((_) => false);
      }
    }
  }

  Widget _buildShelfContent(List<MediaItem> items, double contentHeight) {
    const textAreaHeight = 52.0;
    final artworkSize = contentHeight - textAreaHeight;
    final cardWidth = artworkSize;
    final itemExtent = cardWidth + 12;

    return ScrollConfiguration(
      behavior: const _StretchScrollBehavior(),
      child: ListView.builder(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: items.length,
        itemExtent: itemExtent,
        cacheExtent: 500,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        itemBuilder: (context, index) {
          final mix = items[index];
          final key = ValueKey(mix.uri ?? mix.itemId);

          Widget card;
          if (mix is Playlist) {
            card = PlaylistCard(
              playlist: mix,
              heroTagSuffix: widget.heroTagSuffix,
              imageCacheSize: 256,
            );
          } else if (mix.mediaType == MediaType.radio) {
            card = RadioStationCard(
              radioStation: mix,
              heroTagSuffix: widget.heroTagSuffix,
              imageCacheSize: 256,
            );
          } else {
            card = const SizedBox.shrink();
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

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('MixesRow:${widget.title}');
    super.build(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final baseRowHeight = widget.rowHeight ?? 237.0;
    const titleHeight = 52.0;
    final contentHeight = baseRowHeight - titleHeight;

    final result = RepaintBoundary(
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
          if (_mixes.isEmpty && _isLoading)
            SizedBox(
              height: baseRowHeight - titleHeight,
              child: const Center(child: CircularProgressIndicator()),
            )
          else if (_mixes.isEmpty)
            SizedBox(
              height: baseRowHeight - titleHeight,
              child: Center(
                child: Text(
                  S.of(context)!.noPlaylistMixesFound,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                ),
              ),
            )
          else
            ..._mixes.map((folder) {
              return SizedBox(
                height: baseRowHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
                      child: Text(
                        folder.name,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onBackground,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildShelfContent(folder.items, contentHeight),
                    ),
                  ],
                ),
              );
            }).expand((widget) sync* {
              yield widget;
              yield const SizedBox(height: 8.0);
            }).toList()
              ..removeLast(),
        ],
      ),
    );
    _logger.endBuild('MixesRow:${widget.title}');
    return result;
  }
}

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
