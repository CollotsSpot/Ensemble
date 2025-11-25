import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/player_selector.dart';
import 'library_artists_screen.dart';
import 'library_albums_screen.dart';
import 'library_tracks_screen.dart';
import 'library_playlists_screen.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

class NewLibraryScreen extends StatelessWidget {
  const NewLibraryScreen({super.key});

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
        title: Text(
          'Library',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SearchScreen(),
                ),
              );
            },
            color: colorScheme.onBackground,
          ),
          const PlayerSelector(),
        ],
      ),
      body: !provider.isConnected
          ? _buildDisconnectedView(context, provider)
          : _buildLibraryMenu(context, provider),
    );
  }

  Widget _buildDisconnectedView(
      BuildContext context, MusicAssistantProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: colorScheme.onSurface.withOpacity(0.54),
            ),
            const SizedBox(height: 16),
            Text(
              'Not connected to Music Assistant',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Configure Server'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryMenu(
      BuildContext context, MusicAssistantProvider provider) {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        _buildMenuTile(
          context,
          icon: Icons.person_outline_rounded,
          title: 'Artists',
          subtitle: '${provider.artists.length} artists',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const LibraryArtistsScreen(),
              ),
            );
          },
        ),
        _buildMenuTile(
          context,
          icon: Icons.album_outlined,
          title: 'Albums',
          subtitle: '${provider.albums.length} albums',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const LibraryAlbumsScreen(),
              ),
            );
          },
        ),
        _buildMenuTile(
          context,
          icon: Icons.music_note_outlined,
          title: 'Tracks',
          subtitle: '${provider.tracks.length} tracks',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const LibraryTracksScreen(),
              ),
            );
          },
        ),
        _buildMenuTile(
          context,
          icon: Icons.playlist_play_rounded,
          title: 'Playlists',
          subtitle: 'Your playlists',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const LibraryPlaylistsScreen(),
              ),
            );
          },
        ),
        _buildMenuTile(
          context,
          icon: Icons.category_outlined,
          title: 'Genres',
          subtitle: 'Coming soon',
          onTap: null,
        ),
        _buildMenuTile(
          context,
          icon: Icons.calendar_today_outlined,
          title: 'Years',
          subtitle: 'Coming soon',
          onTap: null,
        ),
      ],
    );
  }

  Widget _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: colorScheme.surfaceVariant.withOpacity(0.3),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: colorScheme.onSurfaceVariant,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        trailing: onTap != null
            ? Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurface.withOpacity(0.5),
              )
            : null,
        onTap: onTap,
        enabled: onTap != null,
      ),
    );
  }
}
