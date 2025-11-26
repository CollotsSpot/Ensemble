import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/album_details_screen.dart';
import '../constants/hero_tags.dart';

class AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback? onTap;

  const AlbumCard({
    super.key, 
    required this.album,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.api?.getImageUrl(album, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap ?? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumDetailsScreen(album: album),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Album artwork
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.0),
                color: colorScheme.surfaceVariant,
                image: imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imageUrl == null
                  ? Center(
                      child: Icon(
                        Icons.album_rounded,
                        size: 64,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          // Album title
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          // Artist name
          Text(
            album.artistsString,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
