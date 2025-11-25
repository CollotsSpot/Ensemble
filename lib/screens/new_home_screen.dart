import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/player_selector.dart';
import '../widgets/album_row.dart';
import '../widgets/artist_row.dart';
import '../widgets/logo_text.dart';
import '../utils/layout_debug.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

class NewHomeScreen extends StatelessWidget {
  const NewHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: ListenableBuilder(
          listenable: LayoutDebug(),
          builder: (context, _) {
            final debug = LayoutDebug();
            return Padding(
              padding: EdgeInsets.only(
                left: debug.logoPaddingLeft,
                top: debug.logoPaddingTop,
                bottom: debug.logoPaddingBottom,
              ),
              child: Image.asset(
                'assets/images/attm_logo.png',
                height: debug.logoSize,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                color: colorScheme.onBackground,
              ),
            );
          },
        ),
        titleSpacing: 0,
        centerTitle: false,
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
          ),
          const PlayerSelector(),
        ],
      ),
      body: SafeArea(
        child: Consumer<MusicAssistantProvider>(
          builder: (context, maProvider, child) {
            return !maProvider.isConnected
                ? _buildDisconnectedView(context, maProvider)
                : _buildConnectedView(context, maProvider);
          },
        ),
      ),
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
              size: 80,
              color: colorScheme.onSurface.withOpacity(0.54),
            ),
            const SizedBox(height: 24),
            Text(
              'Not Connected',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Connect to your Music Assistant server to start listening',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
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
                  horizontal: 32,
                  vertical: 16,
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

  Widget _buildConnectedView(
      BuildContext context, MusicAssistantProvider provider) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // Recently played albums
          AlbumRow(
            title: 'Recently Played',
            loadAlbums: () async {
              if (provider.api == null) return [];
              return await provider.api!.getRecentAlbums(limit: 10);
            },
          ),
          const SizedBox(height: 16),

          // Discover Artists
          ArtistRow(
            title: 'Discover Artists',
            loadArtists: () async {
              if (provider.api == null) return [];
              return await provider.api!.getRandomArtists(limit: 10);
            },
          ),
          const SizedBox(height: 16),

          // Discover Albums
          AlbumRow(
            title: 'Discover Albums',
            loadAlbums: () async {
              if (provider.api == null) return [];
              return await provider.api!.getRandomAlbums(limit: 10);
            },
          ),
          const SizedBox(height: 80), // Space for mini player
        ],
      ),
    );
  }
}
