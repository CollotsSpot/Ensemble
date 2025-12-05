import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import 'artist_card.dart';

class ArtistRow extends StatefulWidget {
  final String title;
  final Future<List<Artist>> Function() loadArtists;
  final String? heroTagSuffix;

  const ArtistRow({
    super.key,
    required this.title,
    required this.loadArtists,
    this.heroTagSuffix,
  });

  @override
  State<ArtistRow> createState() => _ArtistRowState();
}

class _ArtistRowState extends State<ArtistRow> with AutomaticKeepAliveClientMixin {
  late Future<List<Artist>> _artistsFuture;
  List<Artist>? _cachedArtists; // Keep last loaded data to prevent flash
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadArtistsOnce();
  }

  void _loadArtistsOnce() {
    if (!_hasLoaded) {
      _artistsFuture = widget.loadArtists().then((artists) {
        _cachedArtists = artists;
        return artists;
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
          height: 163,
          child: FutureBuilder<List<Artist>>(
            future: _artistsFuture,
            builder: (context, snapshot) {
              // Use cached data immediately if available (prevents flash on rebuild)
              final artists = snapshot.data ?? _cachedArtists;

              // Only show loading if we have no data at all
              if (artists == null && snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError && artists == null) {
                return Center(
                  child: Text('Error: ${snapshot.error}'),
                );
              }

              if (artists == null || artists.isEmpty) {
                return Center(
                  child: Text(
                    'No artists found',
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  ),
                );
              }

              return ScrollConfiguration(
                behavior: const _StretchScrollBehavior(),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  itemCount: artists.length,
                  itemExtent: 136, // 120px width + 16px horizontal margins
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    return Container(
                      key: ValueKey(artist.uri ?? artist.itemId),
                      width: 120,
                      margin: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: ArtistCard(
                        artist: artist,
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
