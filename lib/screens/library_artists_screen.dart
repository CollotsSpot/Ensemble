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

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          color: Colors.white,
        ),
        title: const Text(
          'Artists',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildArtistsList(provider),
    );
  }

  Widget _buildArtistsList(MusicAssistantProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (provider.artists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person_outline_rounded,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            const Text(
              'No artists found',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: provider.loadLibrary,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1a1a1a),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.loadLibrary();
      },
      child: ListView.builder(
        itemCount: provider.artists.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          final artist = provider.artists[index];
          return _buildArtistTile(artist, provider);
        },
      ),
    );
  }

  Widget _buildArtistTile(Artist artist, MusicAssistantProvider provider) {
    final imageUrl = provider.getImageUrl(artist, size: 128);

    return Builder(
      builder: (context) => ListTile(
        leading: Hero(
          tag: HeroTags.artistImage + (artist.uri ?? artist.itemId),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white12,
            backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
            child: imageUrl == null
                ? const Icon(Icons.person_rounded, color: Colors.white54)
                : null,
          ),
        ),
        title: Hero(
          tag: HeroTags.artistName + (artist.uri ?? artist.itemId),
          child: Material(
            color: Colors.transparent,
            child: Text(
              artist.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
