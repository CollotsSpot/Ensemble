import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/artist_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';

class ArtistCard extends StatelessWidget {
  final Artist artist;
  final VoidCallback? onTap;
  final String? heroTagSuffix;

  const ArtistCard({
    super.key,
    required this.artist,
    this.onTap,
    this.heroTagSuffix,
  });

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.api?.getImageUrl(artist, size: 256);
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
              child: ArtistDetailsScreen(
                artist: artist,
                heroTagSuffix: heroTagSuffix,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Artist image - circular
            Hero(
              tag: HeroTags.artistImage + (artist.uri ?? artist.itemId) + suffix,
              child: ClipOval(
                child: Container(
                  width: 110,
                  height: 110,
                  color: colorScheme.surfaceVariant,
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          cacheWidth: 256,
                          cacheHeight: 256,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.person_rounded,
                            size: 60,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Icon(Icons.person_rounded, size: 60, color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          const SizedBox(height: 12),
          // Artist name
          Hero(
            tag: HeroTags.artistName + (artist.uri ?? artist.itemId) + suffix,
            child: Material(
              color: Colors.transparent,
              child: Text(
                artist.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
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
