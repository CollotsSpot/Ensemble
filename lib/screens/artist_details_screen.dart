import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/provider_icon.dart';
import '../widgets/media_context_menu.dart';
import 'album_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/metadata_service.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../utils/page_transitions.dart';
import '../l10n/app_localizations.dart';
import '../theme/design_tokens.dart';
import '../services/library_status_service.dart';
import '../widgets/library_status_builder.dart';

class ArtistDetailsScreen extends StatefulWidget {
  final Artist artist;
  final String? heroTagSuffix;
  final String? initialImageUrl;

  const ArtistDetailsScreen({
    super.key,
    required this.artist,
    this.heroTagSuffix,
    this.initialImageUrl,
  });

  @override
  State<ArtistDetailsScreen> createState() => _ArtistDetailsScreenState();
}

class _ArtistDetailsScreenState extends State<ArtistDetailsScreen> with LibraryStatusMixin {
  final _logger = DebugLogger();
  List<Album> _albums = [];
  List<Album> _providerAlbums = [];
  bool _isLoading = true;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  bool _isDescriptionExpanded = false;
  String? _artistDescription;
  String? _artistImageUrl;
  MusicAssistantProvider? _maProvider;

  @override
  String get libraryItemKey => LibraryStatusService.makeKey(
    'artist',
    widget.artist.provider,
    widget.artist.itemId,
  );

  // View preferences
  String _sortOrder = 'alpha'; // 'alpha' or 'year'
  String _viewMode = 'grid2'; // 'grid2', 'grid3', 'list'

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();
    // Initialize status in centralized service from widget data
    final service = LibraryStatusService.instance;
    final key = libraryItemKey;
    if (!service.isInLibrary(key) && _checkIfInLibrary(widget.artist)) {
      service.initLibraryStatus(key, true);
    }
    if (!service.isFavorite(key) && (widget.artist.favorite ?? false)) {
      service.initFavoriteStatus(key, true);
    }
    // Use initial image URL immediately for smooth hero animation
    _artistImageUrl = widget.initialImageUrl;
    _loadViewPreferences();
    _loadArtistAlbums();
    _loadArtistDescription();
    _refreshFavoriteStatus();

    // Mark that we're on a detail screen and extract colors immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        markDetailScreenEntered(context);
        // Extract colors from initial image URL if available
        if (widget.initialImageUrl != null) {
          _extractColors(widget.initialImageUrl!);
        }
      }
    });

    // Defer higher-res image loading until after transition
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _loadArtistImage();
          // Note: _extractColors is called by _loadArtistImage after image loads

          // CRITICAL FIX: Delay adding provider listener until AFTER Hero animation
          // Adding it immediately causes rebuilds during animation (jank)
          _maProvider = context.read<MusicAssistantProvider>();
          _maProvider?.addListener(_onProviderChanged);
        }
      });
    });
  }

  void _onProviderChanged() {
    if (!mounted) return;
    // Re-check library status when provider data changes and sync to service
    final newIsInLibrary = _checkIfInLibraryFromProvider();
    final service = LibraryStatusService.instance;
    final key = libraryItemKey;
    if (newIsInLibrary != service.isInLibrary(key)) {
      service.setLibraryStatus(key, newIsInLibrary);
    }
  }

  /// Check if artist is in library using provider's artists list
  bool _checkIfInLibraryFromProvider() {
    if (_maProvider == null) return _checkIfInLibrary(widget.artist);

    final artistName = widget.artist.name.toLowerCase();
    final artistUri = widget.artist.uri;

    // Check if this artist exists in the provider's library
    return _maProvider!.artists.any((a) {
      // Match by URI if available
      if (artistUri != null && a.uri == artistUri) return true;
      // Match by name as fallback
      if (a.name.toLowerCase() == artistName) return true;
      // Check provider mappings for matching URIs
      if (widget.artist.providerMappings != null) {
        for (final mapping in widget.artist.providerMappings!) {
          if (a.providerMappings?.any((m) =>
            m.providerInstance == mapping.providerInstance &&
            m.itemId == mapping.itemId) == true) {
            return true;
          }
        }
      }
      return false;
    });
  }

  @override
  void dispose() {
    _maProvider?.removeListener(_onProviderChanged);
    super.dispose();
  }

  Future<void> _loadViewPreferences() async {
    // Parallelize settings service calls
    final results = await Future.wait([
      SettingsService.getArtistAlbumsSortOrder(),
      SettingsService.getArtistAlbumsViewMode(),
    ]);
    if (mounted) {
      setState(() {
        _sortOrder = results[0];
        _viewMode = results[1];
      });
    }
  }

  void _toggleSortOrder() {
    final newOrder = _sortOrder == 'alpha' ? 'year' : 'alpha';
    setState(() {
      _sortOrder = newOrder;
      _sortAlbums();
    });
    SettingsService.setArtistAlbumsSortOrder(newOrder);
  }

  void _cycleViewMode() {
    String newMode;
    switch (_viewMode) {
      case 'grid2':
        newMode = 'grid3';
        break;
      case 'grid3':
        newMode = 'list';
        break;
      default:
        newMode = 'grid2';
    }
    setState(() {
      _viewMode = newMode;
    });
    SettingsService.setArtistAlbumsViewMode(newMode);
  }

  void _sortAlbums() {
    if (_sortOrder == 'year') {
      // Sort by year ascending (oldest first), null years at end
      _albums.sort((a, b) {
        if (a.year == null && b.year == null) return a.name.compareTo(b.name);
        if (a.year == null) return 1;
        if (b.year == null) return -1;
        return a.year!.compareTo(b.year!);
      });
      _providerAlbums.sort((a, b) {
        if (a.year == null && b.year == null) return a.name.compareTo(b.name);
        if (a.year == null) return 1;
        if (b.year == null) return -1;
        return a.year!.compareTo(b.year!);
      });
    } else {
      // Sort alphabetically
      _albums.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _providerAlbums.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  Future<void> _refreshFavoriteStatus() async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api == null) return;

    final artistUri = widget.artist.uri;
    if (artistUri == null || artistUri.isEmpty) {
      _logger.log('Cannot refresh favorite status: artist has no URI');
      return;
    }

    try {
      final freshArtist = await maProvider.api!.getArtistByUri(artistUri);
      if (freshArtist != null && mounted) {
        // Sync with centralized service
        final service = LibraryStatusService.instance;
        final key = libraryItemKey;
        final newFavorite = freshArtist.favorite ?? false;
        if (service.isFavorite(key) != newFavorite) {
          service.setFavoriteStatus(key, newFavorite);
        }
      }
    } catch (e) {
      _logger.log('Error refreshing artist favorite status: $e');
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
        String actualProvider = widget.artist.provider;
        String actualItemId = widget.artist.itemId;

        if (widget.artist.providerMappings != null && widget.artist.providerMappings!.isNotEmpty) {
          final mapping = widget.artist.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.artist.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.artist.providerMappings!.first,
            ),
          );
          // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        _logger.log('Adding artist to favorites: provider=$actualProvider, itemId=$actualItemId');
        success = await maProvider.addToFavorites(
          mediaType: 'artist',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        int? libraryItemId;

        if (widget.artist.provider == 'library') {
          libraryItemId = int.tryParse(widget.artist.itemId);
        } else if (widget.artist.providerMappings != null) {
          final libraryMapping = widget.artist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.artist.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          _logger.log('Error: Could not determine library_item_id for removal');
          rollbackFavoriteOperation();
          throw Exception('Could not determine library ID for this artist');
        }

        success = await maProvider.removeFromFavorites(
          mediaType: 'artist',
          libraryItemId: libraryItemId,
        );
      }

      if (success) {
        completeFavoriteOperation();
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
      _logger.log('Error toggling artist favorite: $e');
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

  /// Check if artist is in library
  bool _checkIfInLibrary(Artist artist) {
    if (artist.provider == 'library') return true;
    return artist.providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
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

        if (widget.artist.providerMappings != null && widget.artist.providerMappings!.isNotEmpty) {
          // For adding to library, we MUST use a non-library provider
          final nonLibraryMapping = widget.artist.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        // Fallback to item's own provider if no non-library mapping found
        if (actualProvider == null || actualItemId == null) {
          if (widget.artist.provider != 'library') {
            actualProvider = widget.artist.provider;
            actualItemId = widget.artist.itemId;
          } else {
            // Item is library-only, can't add
            _logger.log('Cannot add to library: artist is library-only');
            return;
          }
        }

        // Optimistic update via centralized service
        setLibraryStatus(newState);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context)!.addedToLibrary),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        _logger.log('Adding artist to library: provider=$actualProvider, itemId=$actualItemId');
        final success = await maProvider.addToLibrary(
          mediaType: 'artist',
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
        if (widget.artist.provider == 'library') {
          libraryItemId = int.tryParse(widget.artist.itemId);
        } else if (widget.artist.providerMappings != null) {
          final libraryMapping = widget.artist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.artist.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          _logger.log('Cannot remove from library: no library ID found');
          return;
        }

        // Optimistic update via centralized service
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
          mediaType: 'artist',
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
      _logger.log('Error toggling artist library: $e');
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

  /// Start radio on the selected player directly
  void _startRadio(BuildContext context) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
        );
      }
      return;
    }

    try {
      await maProvider.playArtistRadio(player.playerId, widget.artist);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.startingRadioOnPlayer(widget.artist.name, player.name)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error starting artist radio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToStartRadio(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showRadioOnMenu(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerForRadio,
      onPlayerSelected: (player) async {
        try {
          await maProvider.playArtistRadio(player.playerId, widget.artist);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.startingRadioOnPlayer(widget.artist.name, player.name)),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          _logger.log('Error starting artist radio on player: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.failedToStartRadio(e.toString())),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  void _showMoreMenu(BuildContext context, ColorScheme colorScheme) {
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
              title: Text(S.of(context)!.startRadioOn(widget.artist.name), style: TextStyle(color: colorScheme.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _showRadioOnMenu(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_add, color: colorScheme.onSurface),
              title: Text(S.of(context)!.addToQueueOn, style: TextStyle(color: colorScheme.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _showAddToQueueMenu(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAddToQueueMenu(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerToAddToQueue,
      onPlayerSelected: (player) async {
        final api = maProvider.api;
        if (api == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context)!.notConnected)),
            );
          }
          return;
        }
        try {
          await api.playArtistRadioToQueue(player.playerId, widget.artist);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.addedRadioToQueue(widget.artist.name)),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          _logger.log('Error adding artist radio to queue: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.failedToAddToQueue(e.toString())),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _loadArtistImage() async {
    final maProvider = context.read<MusicAssistantProvider>();

    // Get image URL with fallback to Deezer/Fanart.tv
    final imageUrl = await maProvider.getArtistImageUrlWithFallback(widget.artist, size: 512);

    if (mounted && imageUrl != null) {
      setState(() {
        _artistImageUrl = imageUrl;
      });
      // Extract colors after we have the image
      _extractColors(imageUrl);
    }
  }

  Future<void> _extractColors(String imageUrl) async {
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
      _logger.log('Failed to extract colors for artist: $e');
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

    // 1. Show cached data immediately (if available)
    final cachedAlbums = provider.getCachedArtistAlbums(widget.artist.name);
    if (cachedAlbums != null && cachedAlbums.isNotEmpty) {
      final libraryAlbums = cachedAlbums.where((a) => a.inLibrary).toList();
      final providerOnlyAlbums = cachedAlbums.where((a) => !a.inLibrary).toList();

      if (mounted) {
        setState(() {
          _albums = libraryAlbums;
          _providerAlbums = providerOnlyAlbums;
          _sortAlbums();
          _isLoading = false;
        });
      }
    }

    // 2. Fetch fresh data in background (silent refresh)
    try {
      final allAlbums = await provider.getArtistAlbumsWithCache(
        widget.artist.name,
        forceRefresh: cachedAlbums != null,
      );

      if (mounted && allAlbums.isNotEmpty) {
        // Check if data actually changed
        final albumsChanged = _albums.length != allAlbums.where((a) => a.inLibrary).length;

        if (albumsChanged || _albums.isEmpty) {
          final libraryAlbums = allAlbums.where((a) => a.inLibrary).toList();
          final providerOnlyAlbums = allAlbums.where((a) => !a.inLibrary).toList();

          setState(() {
            _albums = libraryAlbums;
            _providerAlbums = providerOnlyAlbums;
            _sortAlbums();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  /// Toggle favorite status for an album
  Future<void> _toggleAlbumFavorite(Album album) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !(album.favorite ?? false);

    try {
      bool success;
      if (newState) {
        // Add to favorites
        String actualProvider = album.provider;
        String actualItemId = album.itemId;

        if (album.providerMappings != null && album.providerMappings!.isNotEmpty) {
          final mapping = album.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => album.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => album.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerInstance;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'album',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        // Remove from favorites
        int? libraryItemId;
        if (album.provider == 'library') {
          libraryItemId = int.tryParse(album.itemId);
        } else if (album.providerMappings != null) {
          final libraryMapping = album.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => album.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromFavorites(
            mediaType: 'album',
            libraryItemId: libraryItemId,
          );
        } else {
          success = false;
        }
      }

      if (success) {
        _loadArtistAlbums();
      }
    } catch (e) {
      _logger.log('Error toggling album favorite: $e');
    }
  }

  /// Toggle library status for an album
  Future<void> _toggleAlbumLibrary(Album album) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !album.inLibrary;

    try {
      bool success;
      if (newState) {
        // Add to library
        String? actualProvider;
        String? actualItemId;

        if (album.providerMappings != null && album.providerMappings!.isNotEmpty) {
          final mapping = album.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => album.providerMappings!.first,
          );
          if (mapping.providerInstance != 'library') {
            actualProvider = mapping.providerInstance;
            actualItemId = mapping.itemId;
          }
        }

        if (actualProvider != null && actualItemId != null) {
          success = await maProvider.addToLibrary(
            mediaType: 'album',
            itemId: actualItemId,
            provider: actualProvider,
          );
        } else {
          success = false;
        }
      } else {
        // Remove from library
        int? libraryItemId;
        if (album.provider == 'library') {
          libraryItemId = int.tryParse(album.itemId);
        } else if (album.providerMappings != null) {
          final libraryMapping = album.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => album.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromLibrary(
            mediaType: 'album',
            libraryItemId: libraryItemId,
          );
        } else {
          success = false;
        }
      }

      if (success) {
        _loadArtistAlbums();
      }
    } catch (e) {
      _logger.log('Error toggling album library: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX: Use select() instead of watch() to reduce rebuilds
    // Only rebuild when specific properties change, not on every provider update
    final adaptiveTheme = context.select<ThemeProvider, bool>(
      (provider) => provider.adaptiveTheme,
    );
    final adaptiveLightScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveLightScheme,
    );
    final adaptiveDarkScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveDarkScheme,
    );

    // Use the loaded image URL (with fallback) instead of directly from MA
    final imageUrl = _artistImageUrl;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get the color scheme to use - prefer local state over provider
    ColorScheme? adaptiveScheme;
    if (adaptiveTheme) {
      // Use local state first (from _extractColors), fallback to provider
      adaptiveScheme = isDark
        ? (_darkColorScheme ?? adaptiveDarkScheme)
        : (_lightColorScheme ?? adaptiveLightScheme);
    }
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
            // Responsive cover size: 50% of screen width, clamped between 140-200 (smaller for circular artist image)
            final coverSize = (constraints.maxWidth * 0.5).clamp(140.0, 200.0);
            final expandedHeight = coverSize + 80;

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
                  Hero(
                    tag: HeroTags.artistImage + (widget.artist.uri ?? widget.artist.itemId) + _heroTagSuffix,
                    child: ClipOval(
                      child: Container(
                        width: coverSize,
                        height: coverSize,
                        color: colorScheme.surfaceVariant,
                        child: imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                // Match source memCacheWidth for smooth Hero animation
                                memCacheWidth: 256,
                                memCacheHeight: 256,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, __) => const SizedBox(),
                                errorWidget: (_, __, ___) => Icon(
                                  Icons.person_rounded,
                                  size: coverSize * 0.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              )
                            : Icon(
                                Icons.person_rounded,
                                size: coverSize * 0.5,
                                color: colorScheme.onSurfaceVariant,
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
              padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: HeroTags.artistName + (widget.artist.uri ?? widget.artist.itemId) + _heroTagSuffix,
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
                  Spacing.vGap8,
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
                    Spacing.vGap8,
                  ],
                  // Action Buttons Row
                  Row(
                    children: [
                      // Main Radio Button
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () => _startRadio(context),
                            icon: const Icon(Icons.radio),
                            label: Text(S.of(context)!.radio),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
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
                              borderRadius: BorderRadius.circular(Radii.xxl),
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
                              final RenderBox box = buttonContext.findRenderObject() as RenderBox;
                              final Offset position = box.localToGlobal(Offset(box.size.width / 2, box.size.height));
                              MediaContextMenu.show(
                                context: context,
                                position: position,
                                mediaType: ContextMenuMediaType.artist,
                                item: widget.artist,
                                isFavorite: isFavorite,
                                isInLibrary: isInLibrary,
                                onToggleFavorite: _toggleFavorite,
                                onToggleLibrary: _toggleLibrary,
                                adaptiveColorScheme: adaptiveScheme,
                                showTopRow: false,
                                sortOrder: _sortOrder,
                                onToggleSort: _toggleSortOrder,
                                viewMode: _viewMode,
                                onCycleView: _cycleViewMode,
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
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Spacing.vGap16,
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
                  S.of(context)!.noAlbumsFound,
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
                  padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 8.0),
                  child: Text(
                    S.of(context)!.inLibrary,
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              _buildAlbumSliver(_albums),
            ],

            // Provider Albums Section
            if (_providerAlbums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24.0, _albums.isEmpty ? 8.0 : 24.0, 24.0, 8.0),
                  child: Text(
                    S.of(context)!.fromProviders,
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              _buildAlbumSliver(_providerAlbums),
              SliverToBoxAdapter(child: SizedBox(height: BottomSpacing.withMiniPlayer)), // Space for bottom nav + mini player
            ],
          ],
        ],
        );
          },
        ),
      ),
    );
  }

  Widget _buildAlbumCard(Album album) {
    // Use read instead of passing provider to avoid rebuild dependencies
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(album, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const String heroSuffix = 'artist_albums';

    // Get adaptive scheme for context menu
    final themeProvider = context.read<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    return GestureDetector(
      onLongPressStart: (details) {
        MediaContextMenu.show(
          context: context,
          position: details.globalPosition,
          mediaType: ContextMenuMediaType.album,
          item: album,
          isFavorite: album.favorite ?? false,
          isInLibrary: album.inLibrary,
          adaptiveColorScheme: adaptiveScheme,
          onToggleFavorite: () => _toggleAlbumFavorite(album),
          onToggleLibrary: () => _toggleAlbumLibrary(album),
        );
      },
      child: InkWell(
        onTap: () {
          // Update adaptive colors immediately on tap
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: AlbumDetailsScreen(
                album: album,
                heroTagSuffix: heroSuffix,
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.0,  // Square album art
              child: Stack(
                children: [
                  Hero(
                    tag: HeroTags.albumCover + (album.uri ?? album.itemId) + '_$heroSuffix',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: colorScheme.surfaceVariant,
                        child: imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                errorWidget: (_, __, ___) => Center(
                                  child: Icon(
                                    Icons.album_rounded,
                                    size: 64,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : Center(
                                child: Icon(
                                  Icons.album_rounded,
                                  size: 64,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                    ),
                  ),
                  // Provider icon overlay
                  if (album.providerMappings?.isNotEmpty == true)
                    ProviderIconOverlay(
                      domain: album.providerMappings!.first.providerDomain,
                    ),
                ],
              ),
            ),
            Spacing.vGap8,
            Hero(
              tag: HeroTags.albumTitle + (album.uri ?? album.itemId) + '_$heroSuffix',
              child: Material(
                color: Colors.transparent,
                child: Text(
                  album.nameWithYear,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Hero(
              tag: HeroTags.artistName + (album.uri ?? album.itemId) + '_$heroSuffix',
              child: Material(
                color: Colors.transparent,
                child: Text(
                  album.artistsString,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumSliver(List<Album> albums) {
    if (_viewMode == 'list') {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildAlbumListTile(albums[index]),
            childCount: albums.length,
          ),
        ),
      );
    }

    final crossAxisCount = _viewMode == 'grid3' ? 3 : 2;
    final childAspectRatio = _viewMode == 'grid3' ? 0.70 : 0.78;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAlbumCard(albums[index]),
          childCount: albums.length,
        ),
      ),
    );
  }

  Widget _buildAlbumListTile(Album album) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(album, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Get adaptive scheme for context menu
    final themeProvider = context.read<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    return GestureDetector(
      onLongPressStart: (details) {
        MediaContextMenu.show(
          context: context,
          position: details.globalPosition,
          mediaType: ContextMenuMediaType.album,
          item: album,
          isFavorite: album.favorite ?? false,
          isInLibrary: album.inLibrary,
          adaptiveColorScheme: adaptiveScheme,
          onToggleFavorite: () => _toggleAlbumFavorite(album),
          onToggleLibrary: () => _toggleAlbumLibrary(album),
        );
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 56,
            height: 56,
            color: colorScheme.surfaceVariant,
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget: (_, __, ___) => Icon(
                      Icons.album_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    Icons.album_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
        title: Text(
          album.nameWithYear,
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          album.artistsString,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: AlbumDetailsScreen(
                album: album,
                heroTagSuffix: 'artist_albums',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
      ),
    );
  }
}
