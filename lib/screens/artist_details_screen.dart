import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import 'album_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';

class ArtistDetailsScreen extends StatefulWidget {
  final Artist artist;

  const ArtistDetailsScreen({super.key, required this.artist});

  @override
  State<ArtistDetailsScreen> createState() => _ArtistDetailsScreenState();
}

class _ArtistDetailsScreenState extends State<ArtistDetailsScreen> {
  List<Album> _albums = [];
  bool _isLoading = true;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;

  @override
  void initState() {
    super.initState();
    _loadArtistAlbums();
    _extractColors();
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.artist, size: 512);

    if (imageUrl == null) return;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        NetworkImage(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });
      }
    } catch (e) {
      print('⚠️ Failed to extract colors for artist: $e');
    }
  }

  Future<void> _loadArtistAlbums() async {
    final provider = context.read<MusicAssistantProvider>();

    // Load albums for this specific artist by filtering
    if (provider.api != null) {
      print('🎵 Loading albums for artist: ${widget.artist.name}');
      print('   Provider: ${widget.artist.provider}');
      print('   ItemId: ${widget.artist.itemId}');

      // Get all albums and filter locally (API filtering not reliable yet)
      final allAlbums = await provider.api!.getAlbums();

      // Filter albums that include this artist
      var artistAlbums = allAlbums.where((album) {
        if (album.artists == null) return false;
        return album.artists!.any((artist) =>
          artist.itemId == widget.artist.itemId || 
          artist.name == widget.artist.name // Fallback to name match
        );
      }).toList();

      print('   Got ${artistAlbums.length} library albums for this artist');

      // Fallback: If no library albums, try searching the provider
      if (artistAlbums.isEmpty && widget.artist.name.isNotEmpty) {
        print('🔍 No library albums found. Searching provider for "${widget.artist.name}"...');
        try {
          final searchResults = await provider.search(widget.artist.name);
          final searchAlbums = searchResults['albums'] ?? [];
          
          // Filter search results to ensure they are actually for this artist
          final validSearchAlbums = searchAlbums.where((item) {
             // Ensure item is an Album and check artist match
             if (item is! Album) return false;
             return item.artists?.any((a) => 
               a.name.toLowerCase() == widget.artist.name.toLowerCase()
             ) ?? false;
          }).cast<Album>().toList();

          if (validSearchAlbums.isNotEmpty) {
            print('✅ Found ${validSearchAlbums.length} albums via search fallback');
            artistAlbums = validSearchAlbums;
          } else {
            print('⚠️ Search returned no valid albums for this artist');
          }
        } catch (e) {
          print('❌ Error searching for artist albums: $e');
        }
      }

      if (mounted) {
        setState(() {
          _albums = artistAlbums;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final imageUrl = maProvider.getImageUrl(widget.artist, size: 512);

    // Theme colors
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: colorScheme.background,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
              color: colorScheme.onBackground,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  Hero(
                    tag: HeroTags.artistImage + (widget.artist.uri ?? widget.artist.itemId),
                    child: CircleAvatar(
                      radius: 100,
                      backgroundColor: colorScheme.surfaceVariant,
                      backgroundImage:
                          imageUrl != null ? NetworkImage(imageUrl) : null,
                      child: imageUrl == null
                          ? Icon(
                              Icons.person_rounded,
                              size: 100,
                              color: colorScheme.onSurfaceVariant,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: HeroTags.artistName + (widget.artist.uri ?? widget.artist.itemId),
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.artist.name,
                        style: textTheme.headlineMedium?.copyWith(
                          color: colorScheme.onBackground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Albums',
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (_isLoading)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: colorScheme.primary),
              ),
            )
          else if (_albums.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No albums found',
                  style: TextStyle(
                    color: colorScheme.onBackground.withOpacity(0.54),
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.75,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final album = _albums[index];
                    return _buildAlbumCard(album, maProvider);
                  },
                  childCount: _albums.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlbumCard(Album album, MusicAssistantProvider provider) {
    final imageUrl = provider.getImageUrl(album, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
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
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
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
          Text(
            album.name,
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            album.artistsString,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
