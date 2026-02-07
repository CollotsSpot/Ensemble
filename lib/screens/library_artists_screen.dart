import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../utils/page_transitions.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/artist_avatar.dart';
import 'artist_details_screen.dart';
import '../l10n/app_localizations.dart';

class LibraryArtistsScreen extends StatefulWidget {
  const LibraryArtistsScreen({super.key});

  @override
  State<LibraryArtistsScreen> createState() => _LibraryArtistsScreenState();
}

class _LibraryArtistsScreenState extends State<LibraryArtistsScreen> {
  List<Artist> _artists = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MusicAssistantProvider>();
    _artists = provider.artists;
    _isLoading = provider.isLoading;
    provider.addListener(_onProviderChanged);

    // Auto-load library if empty
    if (_artists.isEmpty && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          provider.loadLibrary();
        }
      });
    }
  }

  @override
  void dispose() {
    context.read<MusicAssistantProvider>().removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (!mounted) return;
    final provider = context.read<MusicAssistantProvider>();
    setState(() {
      _artists = provider.artists;
      _isLoading = provider.isLoading;
    });
  }

  @override
  Widget build(BuildContext context) {
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
          S.of(context)!.artists,
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildArtistsList(context, _artists, _isLoading),
    );
  }

  Widget _buildArtistsList(BuildContext context, List<Artist> artists, bool isLoading) {
    final colorScheme = Theme.of(context).colorScheme;

    // Show cached data immediately if available, even while loading
    // Only show spinner if we have no data at all AND we're loading
    if (artists.isEmpty && isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (artists.isEmpty) {
      return EmptyState.artists(
        context: context,
        onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
      );
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.background,
      onRefresh: () async {
        await context.read<MusicAssistantProvider>().loadLibrary();
      },
      child: ListView.builder(
        key: const PageStorageKey<String>('library_artists_full_list'),
        cacheExtent: 500, // Prebuild items off-screen for smoother scrolling
        addAutomaticKeepAlives: false, // Tiles have their own keep-alive
        addRepaintBoundaries: false, // Tiles have RepaintBoundary
        itemCount: artists.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          final artist = artists[index];
          return _buildArtistTile(
            context,
            artist,
            key: ValueKey(artist.uri ?? artist.itemId),
          );
        },
      ),
    );
  }

  Widget _buildArtistTile(
    BuildContext context,
    Artist artist, {
    Key? key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();
    // Get image URL for hero animation
    final imageUrl = maProvider.getImageUrl(artist, size: 256);

    // RepaintBoundary isolates repaints to individual tiles
    return RepaintBoundary(
      child: ListTile(
        key: key,
        leading: ArtistAvatar(
          artist: artist,
          radius: 24,
          imageSize: 128,
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
            FadeSlidePageRoute(
              child: ArtistDetailsScreen(
                artist: artist,
                heroTagSuffix: 'library',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
      ),
    );
  }
}
