import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../widgets/album_card.dart';
import '../widgets/common/empty_state.dart';
import '../l10n/app_localizations.dart';

class LibraryAlbumsScreen extends StatefulWidget {
  const LibraryAlbumsScreen({super.key});

  @override
  State<LibraryAlbumsScreen> createState() => _LibraryAlbumsScreenState();
}

class _LibraryAlbumsScreenState extends State<LibraryAlbumsScreen> {
  List<Album> _albums = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MusicAssistantProvider>();
    _albums = provider.albums;
    _isLoading = provider.isLoading;
    provider.addListener(_onProviderChanged);

    // Auto-load library if empty
    if (_albums.isEmpty && !_isLoading) {
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
      _albums = provider.albums;
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
          S.of(context)!.albums,
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildAlbumsList(context, _albums, _isLoading),
    );
  }

  Widget _buildAlbumsList(BuildContext context, List<Album> albums, bool isLoading) {
    final colorScheme = Theme.of(context).colorScheme;

    // Show cached data immediately if available, even while loading
    // Only show spinner if we have no data at all AND we're loading
    if (albums.isEmpty && isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (albums.isEmpty) {
      return EmptyState.albums(
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
      child: GridView.builder(
        key: const PageStorageKey<String>('library_albums_full_grid'),
        cacheExtent: 500, // Prebuild items off-screen for smoother scrolling
        addAutomaticKeepAlives: false, // Cards have their own keep-alive
        addRepaintBoundaries: false, // Cards have RepaintBoundary
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        padding: const EdgeInsets.all(12),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return AlbumCard(
            key: ValueKey(album.uri ?? album.itemId),
            album: album,
            heroTagSuffix: 'library',
          );
        },
      ),
    );
  }
}
