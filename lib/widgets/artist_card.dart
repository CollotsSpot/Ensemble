import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/artist_details_screen.dart';
import '../constants/hero_tags.dart';

class ArtistCard extends StatelessWidget {
  final Artist artist;
  final VoidCallback? onTap;

  const ArtistCard({
    super.key, 
    required this.artist,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.api?.getImageUrl(artist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap ?? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArtistDetailsScreen(artist: artist),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Artist image - circular
          CircleAvatar(
            radius: 55, 
            backgroundColor: colorScheme.surfaceVariant,
            backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
            child: imageUrl == null
                ? Icon(Icons.person_rounded, size: 60, color: colorScheme.onSurfaceVariant)
                : null,
          ),
          const SizedBox(height: 12),
          // Artist name
          Text(
            artist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
