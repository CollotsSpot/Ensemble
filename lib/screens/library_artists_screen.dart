import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import 'artist_details_screen.dart';
import '../constants/hero_tags.dart';

class LibraryArtistsScreen extends StatelessWidget {
  const LibraryArtistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          color: colorScheme.onBackground,
        ),
        title: Text(
          'Artists',
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildArtistsList(context, provider),
    );
  }

  Widget _buildArtistsList(BuildContext context, MusicAssistantProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;

    if (provider.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (provider.artists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline_rounded,
              size: 64,
              color: colorScheme.onSurface.withOpacity(0.54),
            ),
            const SizedBox(height: 16),
            Text(
              'No artists found',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: provider.loadLibrary,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.surfaceVariant,
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () async {
        await provider.loadLibrary();
      },
      child: ListView.builder(
        itemCount: provider.artists.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          final artist = provider.artists[index];
          return _buildArtistTile(context, artist, provider);
        },
      ),
    );
  }

  Widget _buildArtistTile(BuildContext context, Artist artist, MusicAssistantProvider provider) {
    final imageUrl = provider.getImageUrl(artist, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Builder(
      builder: (context) => ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: colorScheme.surfaceVariant,
          backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
          child: imageUrl == null
              ? Icon(Icons.person_rounded, color: colorScheme.onSurfaceVariant)
              : null,
        ),
        title: Text(
          artist.name,
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ArtistDetailsScreen(artist: artist),
            ),
          );
        },
      ),
    );
  }
}
