import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import 'album_card.dart';

class AlbumRow extends StatefulWidget {
  final String title;
  final Future<List<Album>> Function() loadAlbums;
  final String? heroTagSuffix;

  const AlbumRow({
    super.key,
    required this.title,
    required this.loadAlbums,
    this.heroTagSuffix,
  });

  @override
  State<AlbumRow> createState() => _AlbumRowState();
}

class _AlbumRowState extends State<AlbumRow> with AutomaticKeepAliveClientMixin {
  late Future<List<Album>> _albumsFuture;
  List<Album>? _cachedAlbums; // Keep last loaded data to prevent flash
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAlbumsOnce();
  }

  void _loadAlbumsOnce() {
    if (!_hasLoaded) {
      _albumsFuture = widget.loadAlbums().then((albums) {
        _cachedAlbums = albums;
        return albums;
      });
      _hasLoaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            widget.title,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onBackground,
            ),
          ),
        ),
        SizedBox(
          height: 193,
          child: FutureBuilder<List<Album>>(
            future: _albumsFuture,
            builder: (context, snapshot) {
              // Use cached data immediately if available (prevents flash on rebuild)
              final albums = snapshot.data ?? _cachedAlbums;

              // Only show loading if we have no data at all
              if (albums == null && snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError && albums == null) {
                return Center(
                  child: Text('Error: ${snapshot.error}'),
                );
              }

              if (albums == null || albums.isEmpty) {
                return Center(
                  child: Text(
                    'No albums found',
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  ),
                );
              }

              return ScrollConfiguration(
                behavior: const _StretchScrollBehavior(),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  itemCount: albums.length,
                  itemExtent: 162, // 150px width + 12px horizontal margins
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return Container(
                      key: ValueKey(album.uri ?? album.itemId),
                      width: 150,
                      margin: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: AlbumCard(
                        album: album,
                        heroTagSuffix: widget.heroTagSuffix,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
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

