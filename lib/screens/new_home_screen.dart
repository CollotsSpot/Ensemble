import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_selector.dart';
import '../widgets/album_row.dart';
import '../widgets/artist_row.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

class NewHomeScreen extends StatefulWidget {
  const NewHomeScreen({super.key});

  @override
  State<NewHomeScreen> createState() => _NewHomeScreenState();
}

class _NewHomeScreenState extends State<NewHomeScreen> with AutomaticKeepAliveClientMixin {
  Key _refreshKey = UniqueKey();

  @override
  bool get wantKeepAlive => true;

  Future<void> _onRefresh() async {
    // Simulate a short delay or verify connection
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _refreshKey = UniqueKey();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: ColorFiltered(
            colorFilter: Theme.of(context).brightness == Brightness.light
                ? const ColorFilter.matrix(<double>[
                    -1,  0,  0, 0, 255,
                     0, -1,  0, 0, 255,
                     0,  0, -1, 0, 255,
                     0,  0,  0, 1,   0,
                  ])
                : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
            child: Image.asset(
              'assets/images/ensemble_logo.png',
              height: 40,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        titleSpacing: 0,
        centerTitle: false,
        actions: [
          const PlayerSelector(),
        ],
      ),
      body: SafeArea(
        child: Selector<MusicAssistantProvider, bool>(
          selector: (_, p) => p.isConnected,
          builder: (context, isConnected, child) {
            final maProvider = context.read<MusicAssistantProvider>();
            return !isConnected
                ? _buildDisconnectedView(context, maProvider)
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    color: colorScheme.primary,
                    backgroundColor: colorScheme.surface,
                    child: _buildConnectedView(context, maProvider),
                  );
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
    // Use Android 12+ stretch overscroll effect
    return ScrollConfiguration(
      behavior: const _StretchScrollBehavior(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
        key: _refreshKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Recently played albums (extracted from recently played tracks)
          AlbumRow(
            title: 'Recently Played',
            loadAlbums: () async {
              if (provider.api == null) return [];
              return await provider.api!.getRecentAlbums(limit: 10);
            },
          ),
          const SizedBox(height: 6),

          // Discover Artists
          ArtistRow(
            title: 'Discover Artists',
            loadArtists: () async {
              if (provider.api == null) return [];
              return await provider.api!.getRandomArtists(limit: 10);
            },
          ),
          const SizedBox(height: 6),

          // Discover Albums
          AlbumRow(
            title: 'Discover Albums',
            loadAlbums: () async {
              if (provider.api == null) return [];
              return await provider.api!.getRandomAlbums(limit: 10);
            },
          ),
          SizedBox(height: BottomSpacing.withMiniPlayer), // Space for bottom nav + mini player
        ],
        ),
      ),
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
