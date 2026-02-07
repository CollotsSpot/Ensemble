import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import '../services/recently_played_service.dart';
import '../services/library_status_service.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/provider_icon.dart';
import '../widgets/hires_badge.dart';
import '../widgets/media_context_menu.dart';
import '../widgets/library_status_builder.dart';
import '../l10n/app_localizations.dart';
import '../theme/design_tokens.dart';
import 'artist_details_screen.dart';

class AlbumDetailsScreen extends StatefulWidget {
  final Album album;
  final String? heroTagSuffix;
  /// Initial image URL from the source (e.g., AlbumCard) for seamless hero animation
  final String? initialImageUrl;

  const AlbumDetailsScreen({
    super.key,
    required this.album,
    this.heroTagSuffix,
    this.initialImageUrl,
  });

  @override
  State<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends State<AlbumDetailsScreen> with SingleTickerProviderStateMixin, LibraryStatusMixin {
  final _logger = DebugLogger();
  List<Track> _tracks = [];
  bool _isLoading = true;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  bool _isDescriptionExpanded = false;
  String? _albumDescription;
  Album? _freshAlbum; // Full album data with image metadata

  /// Get the best album data available (fresh with images, or widget.album as fallback)
  Album get _displayAlbum => _freshAlbum ?? widget.album;

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  String get libraryItemKey => LibraryStatusService.makeKey(
    'album',
    widget.album.provider,
    widget.album.itemId,
  );

  @override
  void initState() {
    super.initState();
    // Initialize status in centralized service from widget data
    final service = LibraryStatusService.instance;
    final key = libraryItemKey;
    if (!service.isInLibrary(key) && widget.album.inLibrary) {
      service.initLibraryStatus(key, true);
    }
    if (!service.isFavorite(key) && (widget.album.favorite ?? false)) {
      service.initFavoriteStatus(key, true);
    }
    _loadTracks();
    _loadAlbumDescription();

    // Mark that we're on a detail screen and extract colors immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        markDetailScreenEntered(context);
        _extractColors(); // Extract colors immediately - async so won't block
      }
    });

    // Defer fresh data loading until after hero animation completes
    // This prevents setState with new image URL during animation → grey icon flash
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _loadFreshAlbumData();
        }
      });
    });
  }

  /// Load fresh album data from API to get full metadata including images
  Future<void> _loadFreshAlbumData() async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api == null) return;

    // Need a URI to fetch fresh album data
    final albumUri = widget.album.uri;
    if (albumUri == null || albumUri.isEmpty) {
      _logger.log('Cannot load fresh album: album has no URI');
      return;
    }

    try {
      final freshAlbum = await maProvider.api!.getAlbumByUri(albumUri);
      if (freshAlbum != null && mounted) {
        setState(() {
          _freshAlbum = freshAlbum;
        });
        // Sync fresh data to centralized service
        final service = LibraryStatusService.instance;
        service.syncSingleItem(
          key: libraryItemKey,
          inLibrary: freshAlbum.inLibrary,
          favorite: freshAlbum.favorite ?? false,
        );
        // Re-extract colors now that we have fresh album with images
        _extractColors();
      }
    } catch (e) {
      _logger.log('Error loading fresh album data: $e');
    }
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(_displayAlbum, size: 512);

    if (imageUrl == null) return;

    try {
      // Use isolate-based extraction to avoid blocking the main thread
      final colorSchemes = await PaletteHelper.extractColorSchemesFromUrl(imageUrl);

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });

        // Update ThemeProvider so nav bar uses adaptive colors
        final themeProvider = context.read<ThemeProvider>();
        themeProvider.updateAdaptiveColors(colorSchemes.$1, colorSchemes.$2, isFromDetailScreen: true);
      }
    } catch (e) {
      _logger.log('Failed to extract colors for album: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final currentFavorite = isFavorite;
    final newState = !currentFavorite;

    // Optimistic update via centralized service
    setFavoriteStatus(newState);

    try {
      bool success;

      if (newState) {
        // For adding: use the actual provider and itemId from provider_mappings
        String actualProvider = widget.album.provider;
        String actualItemId = widget.album.itemId;

        if (widget.album.providerMappings != null && widget.album.providerMappings!.isNotEmpty) {
          // Find a non-library provider mapping (e.g., spotify, qobuz, etc.)
          final mapping = widget.album.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.album.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.album.providerMappings!.first,
            ),
          );
          // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        _logger.log('Adding to favorites: provider=$actualProvider, itemId=$actualItemId');
        success = await maProvider.addToFavorites(
          mediaType: 'album',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        // For removing: need the library_item_id (numeric)
        int? libraryItemId;

        if (widget.album.provider == 'library') {
          libraryItemId = int.tryParse(widget.album.itemId);
        } else if (widget.album.providerMappings != null) {
          final libraryMapping = widget.album.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.album.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          _logger.log('Error: Could not determine library_item_id for removal');
          rollbackFavoriteOperation();
          throw Exception('Could not determine library ID for this album');
        }

        success = await maProvider.removeFromFavorites(
          mediaType: 'album',
          libraryItemId: libraryItemId,
        );
      }

      if (success) {
        completeFavoriteOperation();
        // Invalidate home cache so the home screen shows updated favorite status
        maProvider.invalidateHomeCache();

        if (mounted) {
          final isOffline = !maProvider.isConnected;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOffline
                    ? S.of(context)!.actionQueuedForSync
                    : (newState ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        rollbackFavoriteOperation();
      }
    } catch (e) {
      rollbackFavoriteOperation();
      _logger.log('Error toggling favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToUpdateFavorite(e.toString())),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Toggle library status
  Future<void> _toggleLibrary() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final currentInLibrary = isInLibrary;
    final newState = !currentInLibrary;

    try {
      if (newState) {
        // Add to library - MUST use non-library provider
        String? actualProvider;
        String? actualItemId;

        if (widget.album.providerMappings != null && widget.album.providerMappings!.isNotEmpty) {
          // For adding to library, we MUST use a non-library provider
          final nonLibraryMapping = widget.album.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        // Fallback to item's own provider if no non-library mapping found
        if (actualProvider == null || actualItemId == null) {
          if (widget.album.provider != 'library') {
            actualProvider = widget.album.provider;
            actualItemId = widget.album.itemId;
          } else {
            // Item is library-only, can't add
            _logger.log('Cannot add to library: album is library-only');
            return;
          }
        }

        // OPTIMISTIC UPDATE via centralized service
        setLibraryStatus(newState);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context)!.addedToLibrary),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        _logger.log('Adding album to library: provider=$actualProvider, itemId=$actualItemId');
        final success = await maProvider.addToLibrary(
          mediaType: 'album',
          provider: actualProvider,
          itemId: actualItemId,
        );

        if (success) {
          completeLibraryOperation();
        } else {
          rollbackLibraryOperation();
        }
      } else {
        // Remove from library
        int? libraryItemId;
        if (widget.album.provider == 'library') {
          libraryItemId = int.tryParse(widget.album.itemId);
        } else if (widget.album.providerMappings != null) {
          final libraryMapping = widget.album.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.album.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          _logger.log('Cannot remove from library: no library ID found');
          return;
        }

        // OPTIMISTIC UPDATE via centralized service
        setLibraryStatus(newState);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context)!.removedFromLibrary),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        final success = await maProvider.removeFromLibrary(
          mediaType: 'album',
          libraryItemId: libraryItemId,
        );

        if (success) {
          completeLibraryOperation();
        } else {
          rollbackLibraryOperation();
        }
      }
    } catch (e) {
      rollbackLibraryOperation();
      _logger.log('Error toggling album library: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update library: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleTrackFavorite(int trackIndex) async {
    if (trackIndex < 0 || trackIndex >= _tracks.length) return;

    final track = _tracks[trackIndex];
    final maProvider = context.read<MusicAssistantProvider>();
    final currentFavorite = track.favorite ?? false;

    try {
      bool success;

      if (currentFavorite) {
        // Remove from favorites - need library_item_id
        int? libraryItemId;
        if (track.provider == 'library') {
          libraryItemId = int.tryParse(track.itemId);
        } else if (track.providerMappings != null) {
          final libraryMapping = track.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => track.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromFavorites(
            mediaType: 'track',
            libraryItemId: libraryItemId,
          );
        } else {
          success = false;
        }
      } else {
        // Add to favorites
        String actualProvider = track.provider;
        String actualItemId = track.itemId;

        if (track.providerMappings != null && track.providerMappings!.isNotEmpty) {
          final mapping = track.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => track.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => track.providerMappings!.first,
            ),
          );
          // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'track',
          itemId: actualItemId,
          provider: actualProvider,
        );
      }

      if (success) {
        // Optimistically update local state
        setState(() {
          _tracks[trackIndex] = Track(
            itemId: track.itemId,
            provider: track.provider,
            name: track.name,
            uri: track.uri,
            favorite: !currentFavorite,
            artists: track.artists,
            album: track.album,
            duration: track.duration,
            providerMappings: track.providerMappings,
          );
        });

        if (mounted) {
          final isOffline = !maProvider.isConnected;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOffline
                    ? S.of(context)!.actionQueuedForSync
                    : (!currentFavorite ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      _logger.log('Error toggling track favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToUpdateFavorite(e.toString())),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleTrackLibrary(int trackIndex) async {
    if (trackIndex < 0 || trackIndex >= _tracks.length) return;

    final track = _tracks[trackIndex];
    final maProvider = context.read<MusicAssistantProvider>();
    final currentInLibrary = track.inLibrary;

    try {
      if (!currentInLibrary) {
        // Add to library
        String? actualProvider;
        String? actualItemId;

        if (track.providerMappings != null && track.providerMappings!.isNotEmpty) {
          final nonLibraryMapping = track.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        if (actualProvider == null || actualItemId == null) {
          if (track.provider != 'library') {
            actualProvider = track.provider;
            actualItemId = track.itemId;
          } else {
            return;
          }
        }

        await maProvider.addToLibrary(
          mediaType: 'track',
          provider: actualProvider,
          itemId: actualItemId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context)!.addedToLibrary),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        // Remove from library
        int? libraryItemId;
        if (track.provider == 'library') {
          libraryItemId = int.tryParse(track.itemId);
        } else if (track.providerMappings != null) {
          final libraryMapping = track.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => track.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) return;

        await maProvider.removeFromLibrary(
          mediaType: 'track',
          libraryItemId: libraryItemId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context)!.removedFromLibrary),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      _logger.log('Error toggling track library: $e');
    }
  }

  Future<void> _loadTracks() async {
    final provider = context.read<MusicAssistantProvider>();
    final cacheKey = '${widget.album.provider}_${widget.album.itemId}';

    // 1. Show cached data immediately (if available)
    final cachedTracks = provider.getCachedAlbumTracks(cacheKey);
    if (cachedTracks != null && cachedTracks.isNotEmpty) {
      if (mounted) {
        setState(() {
          _tracks = cachedTracks;
          _isLoading = false;
        });
      }
    }

    // 2. Fetch fresh data in background (silent refresh)
    try {
      final freshTracks = await provider.getAlbumTracksWithCache(
        widget.album.provider,
        widget.album.itemId,
        forceRefresh: cachedTracks != null, // Force refresh if we had cache
      );

      // 3. Update if we got different data
      if (mounted && freshTracks.isNotEmpty) {
        final tracksChanged = _tracks.length != freshTracks.length ||
            (_tracks.isNotEmpty && freshTracks.isNotEmpty &&
             _tracks.first.itemId != freshTracks.first.itemId);
        if (tracksChanged || _tracks.isEmpty) {
          setState(() {
            _tracks = freshTracks;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      _logger.log('⚠️ Background refresh failed: $e');
    }

    // Ensure loading is false even if everything failed
    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _playAlbum() async {
    if (_tracks.isEmpty) return;

    final maProvider = context.read<MusicAssistantProvider>();

    try {
      // Use the selected player
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError(S.of(context)!.noPlayerSelected);
        return;
      }

      _logger.log('Queueing album on ${player.name}: ${player.playerId}');

      // Queue all tracks via Music Assistant
      await maProvider.playTracks(player.playerId, _tracks, startIndex: 0);
      _logger.log('Album queued on ${player.name}');

      // Record to local recently played (per-profile)
      RecentlyPlayedService.instance.recordAlbumPlayed(widget.album);
      // Stay on album page - mini player will appear
    } catch (e) {
      _logger.log('Error playing album: $e');
      _showError('Failed to play album: $e');
    }
  }

  Future<void> _playTrack(int index) async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      // Use the selected player
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError(S.of(context)!.noPlayerSelected);
        return;
      }

      _logger.log('Queueing tracks on ${player.name} starting at index $index');

      // Queue tracks starting at the selected index
      await maProvider.playTracks(player.playerId, _tracks, startIndex: index);
      _logger.log('Tracks queued on ${player.name}');
      // Stay on album page - mini player will appear
    } catch (e) {
      _logger.log('Error playing track: $e');
      _showError('Failed to play track: $e');
    }
  }

  void _addAlbumToQueue() {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.addAlbumToQueueOn,
      onPlayerSelected: (player) async {
        try {
          _logger.log('Adding album to queue on ${player.name}');
          await maProvider.addTracksToQueue(
            player.playerId,
            _tracks,
          );
          _logger.log('Album added to queue on ${player.name}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.albumAddedToQueue),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          _logger.log('Error adding album to queue: $e');
          _showError('Failed to add album to queue: $e');
        }
      },
    );
  }

  void _addTrackToQueue(BuildContext context, int index) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.addToQueueOn,
      onPlayerSelected: (player) async {
        try {
          // Add tracks from this index onwards to queue
          await maProvider.addTracksToQueue(
            player.playerId,
            _tracks,
            startIndex: index,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.tracksAddedToQueue),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          _logger.log('Error adding to queue: $e');
          _showError('Failed to add to queue: $e');
        }
      },
    );
  }

  void _navigateToArtist() {
    // Navigate to the first artist if available
    if (_displayAlbum.artists != null && _displayAlbum.artists!.isNotEmpty) {
      final artist = _displayAlbum.artists!.first;
      final maProvider = context.read<MusicAssistantProvider>();
      final imageUrl = maProvider.getImageUrl(artist, size: 256);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ArtistDetailsScreen(
            artist: artist,
            initialImageUrl: imageUrl,
          ),
        ),
      );
    }
  }

  Future<void> _loadAlbumDescription() async {
    final artistName = widget.album.artists?.firstOrNull?.name ?? '';
    final albumName = widget.album.name;

    if (artistName.isEmpty || albumName.isEmpty) return;

    final description = await MetadataService.getAlbumDescription(
      artistName,
      albumName,
      widget.album.metadata,
    );

    if (mounted) {
      setState(() {
        _albumDescription = description;
      });
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show fullscreen album art overlay
  void _showFullscreenArt(String? imageUrl) {
    if (imageUrl == null) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) {
                  Navigator.of(context).pop();
                }
              },
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 3.0,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      memCacheWidth: 1024,
                      memCacheHeight: 1024,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX: Use select() instead of watch() to reduce rebuilds
    // Only rebuild when specific properties change, not on every provider update
    // Use _displayAlbum which has fresh data with images if available
    final providerImageUrl = context.select<MusicAssistantProvider, String?>(
      (provider) => provider.getImageUrl(_displayAlbum, size: 512),
    );
    // Use initialImageUrl as fallback for seamless hero animation
    final imageUrl = providerImageUrl ?? widget.initialImageUrl;
    final adaptiveTheme = context.select<ThemeProvider, bool>(
      (provider) => provider.adaptiveTheme,
    );
    final adaptiveLightScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveLightScheme,
    );
    final adaptiveDarkScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveDarkScheme,
    );

    // Determine if we should use adaptive theme colors
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get the color scheme to use - prefer local state over provider
    // Local state (_darkColorScheme/_lightColorScheme) is set by _extractColors()
    ColorScheme? adaptiveScheme;
    if (adaptiveTheme) {
      // Use local state first (from _extractColors), fallback to provider
      adaptiveScheme = isDark
        ? (_darkColorScheme ?? adaptiveDarkScheme)
        : (_lightColorScheme ?? adaptiveLightScheme);
    }

    // Use adaptive scheme if available, otherwise use global theme
    final colorScheme = adaptiveScheme ?? Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          clearAdaptiveColorsOnBack(context);
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.background,
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive cover size: 70% of screen width, clamped between 200-320
            final coverSize = (constraints.maxWidth * 0.7).clamp(200.0, 320.0);
            final expandedHeight = coverSize + 70;

            return CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: expandedHeight,
            pinned: true,
            backgroundColor: colorScheme.background,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                clearAdaptiveColorsOnBack(context);
                Navigator.pop(context);
              },
              color: colorScheme.onBackground,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  GestureDetector(
                    onTap: () => _showFullscreenArt(imageUrl),
                    // Shadow container (outside Hero for correct clipping)
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Hero(
                        tag: HeroTags.albumCover + (widget.album.uri ?? widget.album.itemId) + _heroTagSuffix,
                        // FIXED: Match source structure - ClipRRect(12) → Container → CachedNetworkImage
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: coverSize,
                            height: coverSize,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  color: colorScheme.surfaceVariant,
                                  child: imageUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          fit: BoxFit.cover,
                                          // Match source memCacheWidth for smooth Hero
                                          memCacheWidth: 256,
                                          memCacheHeight: 256,
                                          fadeInDuration: Duration.zero,
                                          fadeOutDuration: Duration.zero,
                                          placeholder: (_, __) => const SizedBox(),
                                          errorWidget: (_, __, ___) => Icon(
                                            Icons.album_rounded,
                                            size: coverSize * 0.43,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        )
                                      : Icon(
                                          Icons.album_rounded,
                                          size: coverSize * 0.43,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                ),
                                // Provider icon overlay
                                if (widget.album.providerMappings?.isNotEmpty == true)
                                  ProviderIconOverlay(
                                    domain: widget.album.providerMappings!.first.providerDomain,
                                    size: 24,
                                    margin: 8,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: HeroTags.albumTitle + (widget.album.uri ?? widget.album.itemId) + _heroTagSuffix,
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.album.nameWithYear,
                        style: textTheme.headlineMedium?.copyWith(
                          color: colorScheme.onBackground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Spacing.vGap8,
                  Hero(
                    tag: HeroTags.artistName + (widget.album.uri ?? widget.album.itemId) + _heroTagSuffix,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _navigateToArtist(),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(
                            _displayAlbum.artistsString,
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onBackground.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Spacing.vGap16,
                  // Album Description
                  if (_albumDescription != null && _albumDescription!.isNotEmpty) ...[
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
                          _albumDescription!,
                          style: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onBackground.withOpacity(0.8),
                          ),
                          maxLines: _isDescriptionExpanded ? null : 2,
                          overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Spacing.vGap8,
                  ],
                  Row(
                    children: [
                      // Main Play Button
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading || _tracks.isEmpty ? null : _playAlbum,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(S.of(context)!.play),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              disabledBackgroundColor: colorScheme.primary.withOpacity(0.38),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Library Button
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: _toggleLibrary,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Icon(
                            Symbols.book_2,
                            size: 25,
                            fill: isInLibrary ? 1 : 0,
                            color: isInLibrary
                                ? colorScheme.primary
                                : Colors.white70,
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Favorite Button
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: _toggleFavorite,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Radii.xxl), // Circular
                            ),
                          ),
                          child: Icon(
                            Icons.favorite,
                            size: 25,
                            color: isFavorite
                                ? colorScheme.error
                                : Colors.white70,
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Three-dot Menu Button
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: Builder(
                          builder: (buttonContext) => FilledButton.tonal(
                            onPressed: () {
                              if (_isLoading || _tracks.isEmpty) return;
                              final RenderBox box = buttonContext.findRenderObject() as RenderBox;
                              final Offset position = box.localToGlobal(Offset(box.size.width / 2, box.size.height));
                              MediaContextMenu.show(
                                context: context,
                                position: position,
                                mediaType: ContextMenuMediaType.album,
                                item: widget.album,
                                isFavorite: isFavorite,
                                isInLibrary: isInLibrary,
                                onToggleFavorite: _toggleFavorite,
                                onToggleLibrary: _toggleLibrary,
                                adaptiveColorScheme: adaptiveScheme,
                                showTopRow: false, // Only show list items since buttons are already visible
                              );
                            },
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Icon(
                              Icons.more_vert,
                              size: 25,
                              color: _isLoading || _tracks.isEmpty
                                  ? Colors.white70.withOpacity(0.38)
                                  : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
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
          else if (_tracks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  S.of(context)!.noTracksFound,
                  style: TextStyle(
                    color: colorScheme.onBackground.withOpacity(0.54),
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks[index];

                  return GestureDetector(
                    onLongPressStart: (details) {
                      MediaContextMenu.show(
                        context: context,
                        position: details.globalPosition,
                        mediaType: ContextMenuMediaType.track,
                        item: track,
                        isFavorite: track.favorite ?? false,
                        isInLibrary: track.inLibrary,
                        onToggleFavorite: () => _toggleTrackFavorite(index),
                        onToggleLibrary: () => _toggleTrackLibrary(index),
                        adaptiveColorScheme: adaptiveScheme,
                      );
                    },
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${track.position ?? index + 1}',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        track.name,
                        style: textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.artistsString,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (HiResBadge.getTooltip(track) != null) ...[
                            HiResBadge.fromTrack(track, primaryColor: colorScheme.primary)!,
                            const SizedBox(width: 12),
                          ],
                          if (track.duration != null)
                            SizedBox(
                              width: 40,
                              child: Text(
                                _formatDuration(track.duration!),
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.5),
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                        ],
                      ),
                      onTap: () => _playTrack(index),
                    ),
                  );
                },
                childCount: _tracks.length,
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: BottomSpacing.withMiniPlayer)), // Space for bottom nav + mini player
        ],
      );
          },
        ),
      ),
    );
  }

  void _showPlayAlbumFromHereMenu(BuildContext context, int startIndex) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerToPlayAlbum,
      onPlayerSelected: (player) async {
        maProvider.selectPlayer(player);
        await maProvider.playTracks(
          player.playerId,
          _tracks,
          startIndex: startIndex,
        );
      },
    );
  }

  void _showPlayRadioMenu(BuildContext context, int trackIndex) {
    final maProvider = context.read<MusicAssistantProvider>();
    final track = _tracks[trackIndex];

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerForRadio,
      onPlayerSelected: (player) async {
        maProvider.selectPlayer(player);
        await maProvider.playRadio(player.playerId, track);
      },
    );
  }

  void _showPlayOnMenu(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerToPlayAlbum,
      onPlayerSelected: (player) async {
        maProvider.selectPlayer(player);
        await maProvider.playTracks(player.playerId, _tracks);
      },
    );
  }

  void _showMoreMenu(BuildContext context, ColorScheme colorScheme) {
    final maProvider = context.read<MusicAssistantProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.speaker_group_outlined, color: colorScheme.onSurface),
              title: Text(S.of(context)!.playOn, style: TextStyle(color: colorScheme.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _showPlayOnMenu(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_add, color: colorScheme.onSurface),
              title: Text(S.of(context)!.addToQueue, style: TextStyle(color: colorScheme.onSurface)),
              onTap: () async {
                Navigator.pop(context);
                // Add to queue on selected player
                final player = maProvider.selectedPlayer;
                if (player != null) {
                  try {
                    await maProvider.addTracksToQueue(player.playerId, _tracks);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(S.of(context)!.albumAddedToQueue),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      _showError(S.of(context)!.failedToAddToQueue(e.toString()));
                    }
                  }
                } else {
                  _showError(S.of(context)!.noPlayerSelected);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.queue_music, color: colorScheme.onSurface),
              title: Text(S.of(context)!.addToQueueOn, style: TextStyle(color: colorScheme.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _addAlbumToQueue();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
