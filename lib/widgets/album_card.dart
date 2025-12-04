import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/album_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';

class AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback? onTap;
  final String? heroTagSuffix;

  const AlbumCard({
    super.key,
    required this.album,
    this.onTap,
    this.heroTagSuffix,
  });

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.api?.getImageUrl(album, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = heroTagSuffix != null ? '_$heroTagSuffix' : '';

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap ?? () {
          // Update adaptive colors immediately on tap
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: AlbumDetailsScreen(
                album: album,
                heroTagSuffix: heroTagSuffix,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album artwork
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.albumCover + (album.uri ?? album.itemId) + suffix,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Container(
                    color: colorScheme.surfaceVariant,
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 256,
                            cacheHeight: 256,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.album_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.album_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Album title
          Hero(
            tag: HeroTags.albumTitle + (album.uri ?? album.itemId) + suffix,
            child: Material(
              color: Colors.transparent,
              child: Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // Artist name
          Hero(
            tag: HeroTags.artistName + (album.uri ?? album.itemId) + suffix,
            child: Material(
              color: Colors.transparent,
              child: Text(
                album.artistsString,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}
