import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import 'album_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/metadata_service.dart';

class ArtistDetailsScreen extends StatefulWidget {
  final Artist artist;

  const ArtistDetailsScreen({super.key, required this.artist});

  @override
  State<ArtistDetailsScreen> createState() => _ArtistDetailsScreenState();
}

class _ArtistDetailsScreenState extends State<ArtistDetailsScreen> {
  List<Album> _albums = [];
  List<Album> _providerAlbums = [];
  bool _isLoading = true;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  bool _isDescriptionExpanded = false;
  String? _artistDescription;

  @override
  void initState() {
    super.initState();
    _loadArtistAlbums();
    _extractColors();
    _loadArtistDescription();
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

  Future<void> _loadArtistDescription() async {
    final artistName = widget.artist.name;

    if (artistName.isEmpty) return;

    final description = await MetadataService.getArtistDescription(
      artistName,
      widget.artist.metadata,
    );

    if (mounted) {
      setState(() {
        _artistDescription = description;
      });
    }
  }

  Future<void> _loadArtistAlbums() async {
    final provider = context.read<MusicAssistantProvider>();

    if (provider.api != null) {
      // 1. Get Library Albums
      final allAlbums = await provider.api!.getAlbums();
      
      var libraryAlbums = allAlbums.where((album) {
        if (album.artists == null) return false;
        return album.artists!.any((artist) =>
          artist.itemId == widget.artist.itemId || 
          artist.name == widget.artist.name
        );
      }).toList();

      List<Album> providerAlbums = [];

      // 2. Get Provider Albums (via search)
      if (widget.artist.name.isNotEmpty) {
        try {
          final searchResults = await provider.search(widget.artist.name);
          final searchAlbums = (searchResults['albums'] as List<dynamic>?)
              ?.map((item) => item as Album)
              .toList() ?? [];
          
          // Filter: Must match artist name
          providerAlbums = searchAlbums.where((album) {
             return album.artists?.any((a) => 
               a.name.toLowerCase() == widget.artist.name.toLowerCase()
             ) ?? false;
          }).toList();

          // Filter: Must NOT be in libraryAlbums
          final libraryAlbumNames = libraryAlbums.map((a) => a.name.toLowerCase()).toSet();
          
          providerAlbums = providerAlbums.where((a) => 
            !libraryAlbumNames.contains(a.name.toLowerCase())
          ).toList();

        } catch (e) {
          print('Error searching provider albums: $e');
        }
      }

      if (mounted) {
        setState(() {
          _albums = libraryAlbums;
          _providerAlbums = providerAlbums;
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

    final useAdaptiveTheme = themeProvider.adaptiveTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ColorScheme? adaptiveScheme;
    if (useAdaptiveTheme) {
      adaptiveScheme = isDark ? _darkColorScheme : _lightColorScheme;
    }
    final colorScheme = adaptiveScheme ?? Theme.of(context).colorScheme;
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
                  const SizedBox(height: 16),
                  if (_artistDescription != null && _artistDescription!.isNotEmpty) ...[
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isDescriptionExpanded = !_isDescriptionExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _artistDescription!,
                          style: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onBackground.withOpacity(0.8),
                          ),
                          maxLines: _isDescriptionExpanded ? null : 2,
                          overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
          else if (_albums.isEmpty && _providerAlbums.isEmpty)
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
          else ...[
            // Library Albums Section
            if (_albums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Text(
                    'In Library',
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
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

            // Provider Albums Section
            if (_providerAlbums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24.0, 32.0, 24.0, 12.0),
                  child: Text(
                    'From Providers',
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
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
                      final album = _providerAlbums[index];
                      return _buildAlbumCard(album, maProvider);
                    },
                    childCount: _providerAlbums.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
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
