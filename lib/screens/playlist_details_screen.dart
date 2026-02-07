import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/debug_logger.dart';
import '../services/recently_played_service.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/provider_icon.dart';
import '../widgets/hires_badge.dart';
import '../widgets/media_context_menu.dart';
import '../l10n/app_localizations.dart';
import '../theme/design_tokens.dart';

class PlaylistDetailsScreen extends StatefulWidget {
  final Playlist playlist;
  final String? heroTagSuffix;
  /// Initial image URL from the source (e.g., PlaylistCard) for seamless hero animation
  final String? initialImageUrl;

  // Legacy constructor parameters for backward compatibility
  final String? provider;
  final String? itemId;

  const PlaylistDetailsScreen({
    super.key,
    required this.playlist,
    this.heroTagSuffix,
    this.initialImageUrl,
    this.provider,
    this.itemId,
  });

  @override
  State<PlaylistDetailsScreen> createState() => _PlaylistDetailsScreenState();
}

class _PlaylistDetailsScreenState extends State<PlaylistDetailsScreen> with SingleTickerProviderStateMixin {
  final _logger = DebugLogger();
  List<Track> _tracks = [];
  bool _isLoading = true;
  bool _isFavorite = false;
  late bool _isInLibrary;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  // Helper to get provider/itemId from widget or playlist
  String get _provider => widget.provider ?? widget.playlist.provider;
  String get _itemId => widget.itemId ?? widget.playlist.itemId;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.playlist.favorite ?? false;
    _isInLibrary = widget.playlist.inLibrary;
    _loadTracks();

    // Mark that we're on a detail screen and extract colors immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        markDetailScreenEntered(context);
        _extractColors(); // Extract colors immediately - async so won't block
      }
    });
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.playlist, size: 512);

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
      _logger.log('Failed to extract colors for playlist: $e');
    }
  }

  Future<void> _loadTracks() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final cacheKey = '${_provider}_$_itemId';

    // 1. Show cached data immediately (if available)
    final cachedTracks = maProvider.getCachedPlaylistTracks(cacheKey);
    if (cachedTracks != null && cachedTracks.isNotEmpty) {
      if (mounted) {
        setState(() {
          _tracks = cachedTracks;
          _isLoading = false;
        });
      }
    } else {
      setState(() => _isLoading = true);
    }

    // 2. Fetch fresh data in background (silent refresh)
    try {
      final freshTracks = await maProvider.getPlaylistTracksWithCache(
        _provider,
        _itemId,
        forceRefresh: cachedTracks != null,
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
      // Silent failure - keep showing cached data
      _logger.log('Background refresh failed: $e');
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final newState = !_isFavorite;
      bool success;

      if (newState) {
        // For adding: use the actual provider and itemId from provider_mappings
        String actualProvider = widget.playlist.provider;
        String actualItemId = widget.playlist.itemId;

        if (widget.playlist.providerMappings != null && widget.playlist.providerMappings!.isNotEmpty) {
          final mapping = widget.playlist.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.playlist.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.playlist.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        _logger.log('Adding playlist to favorites: provider=$actualProvider, itemId=$actualItemId');
        success = await maProvider.addToFavorites(
          mediaType: 'playlist',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        // For removing: need the library_item_id (numeric)
        int? libraryItemId;

        if (widget.playlist.provider == 'library') {
          libraryItemId = int.tryParse(widget.playlist.itemId);
        } else if (widget.playlist.providerMappings != null) {
          final libraryMapping = widget.playlist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.playlist.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          _logger.log('Error: Could not determine library_item_id for removal');
          throw Exception('Could not determine library ID for this playlist');
        }

        success = await maProvider.removeFromFavorites(
          mediaType: 'playlist',
          libraryItemId: libraryItemId,
        );
      }

      if (success) {
        setState(() {
          _isFavorite = newState;
        });

        maProvider.invalidateHomeCache();

        if (mounted) {
          final isOffline = !maProvider.isConnected;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOffline
                    ? S.of(context)!.actionQueuedForSync
                    : (_isFavorite ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
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

  Future<void> _toggleLibrary() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !_isInLibrary;

    try {
      if (newState) {
        String? actualProvider;
        String? actualItemId;

        if (widget.playlist.providerMappings != null && widget.playlist.providerMappings!.isNotEmpty) {
          final nonLibraryMapping = widget.playlist.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        if (actualProvider == null || actualItemId == null) {
          if (widget.playlist.provider != 'library') {
            actualProvider = widget.playlist.provider;
            actualItemId = widget.playlist.itemId;
          } else {
            return;
          }
        }

        setState(() => _isInLibrary = newState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.addedToLibrary),
            duration: const Duration(seconds: 1),
          ),
        );

        maProvider.addToLibrary(
          mediaType: 'playlist',
          provider: actualProvider,
          itemId: actualItemId,
        ).catchError((e) {
          if (mounted) setState(() => _isInLibrary = !newState);
        });
      } else {
        int? libraryItemId;
        if (widget.playlist.provider == 'library') {
          libraryItemId = int.tryParse(widget.playlist.itemId);
        } else if (widget.playlist.providerMappings != null) {
          final libraryMapping = widget.playlist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.playlist.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) return;

        setState(() => _isInLibrary = newState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.removedFromLibrary),
            duration: const Duration(seconds: 1),
          ),
        );

        maProvider.removeFromLibrary(
          mediaType: 'playlist',
          libraryItemId: libraryItemId,
        ).catchError((e) {
          if (mounted) setState(() => _isInLibrary = !newState);
        });
      }
    } catch (e) {
      // Silent failure
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

  Future<void> _playPlaylist() async {
    if (_tracks.isEmpty) return;

    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError(S.of(context)!.noPlayerSelected);
        return;
      }

      _logger.log('Queueing playlist on ${player.name}');
      await maProvider.playTracks(player.playerId, _tracks, startIndex: 0);
      _logger.log('Playlist queued successfully');

      RecentlyPlayedService.instance.recordPlaylistPlayed(widget.playlist);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.playingPlaylist(widget.playlist.name)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error playing playlist: $e');
      _showError('Error playing playlist: $e');
    }
  }

  Future<void> _playTrack(int index) async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError(S.of(context)!.noPlayerSelected);
        return;
      }

      _logger.log('Queueing tracks on ${player.name} starting at index $index');
      await maProvider.playTracks(player.playerId, _tracks, startIndex: index);
      _logger.log('Tracks queued on ${player.name}');
    } catch (e) {
      _logger.log('Error playing track: $e');
      _showError('Failed to play track: $e');
    }
  }

  void _showPlayOnMenu(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerToPlayPlaylist,
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
                          content: Text(S.of(context)!.tracksAddedToQueue),
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
                _addPlaylistToQueue();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _addPlaylistToQueue() {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.addToQueueOn,
      onPlayerSelected: (player) async {
        try {
          _logger.log('Adding playlist to queue on ${player.name}');
          await maProvider.addTracksToQueue(
            player.playerId,
            _tracks,
          );
          _logger.log('Playlist added to queue on ${player.name}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.tracksAddedToQueue),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          _logger.log('Error adding playlist to queue: $e');
          _showError('Failed to add playlist to queue: $e');
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

  /// Show fullscreen playlist art overlay
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Use select() to reduce rebuilds
    final providerImageUrl = context.select<MusicAssistantProvider, String?>(
      (provider) => provider.getImageUrl(widget.playlist, size: 512),
    );
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

    final isDark = Theme.of(context).brightness == Brightness.dark;

    ColorScheme? adaptiveScheme;
    if (adaptiveTheme) {
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
        backgroundColor: colorScheme.surface,
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
                  backgroundColor: colorScheme.surface,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () {
                      clearAdaptiveColorsOnBack(context);
                      Navigator.pop(context);
                    },
                    color: colorScheme.onSurface,
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60),
                        GestureDetector(
                          onTap: () => _showFullscreenArt(imageUrl),
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
                              tag: HeroTags.playlistCover + (widget.playlist.uri ?? widget.playlist.itemId) + _heroTagSuffix,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: coverSize,
                                  height: coverSize,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Container(
                                        color: colorScheme.surfaceContainerHighest,
                                        child: imageUrl != null
                                            ? CachedNetworkImage(
                                                imageUrl: imageUrl,
                                                fit: BoxFit.cover,
                                                memCacheWidth: 256,
                                                memCacheHeight: 256,
                                                fadeInDuration: Duration.zero,
                                                fadeOutDuration: Duration.zero,
                                                placeholder: (_, __) => const SizedBox(),
                                                errorWidget: (_, __, ___) => Icon(
                                                  Icons.playlist_play_rounded,
                                                  size: coverSize * 0.43,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              )
                                            : Icon(
                                                Icons.playlist_play_rounded,
                                                size: coverSize * 0.43,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                      ),
                                      // Provider icon overlay
                                      if (widget.playlist.providerMappings?.isNotEmpty == true)
                                        ProviderIconOverlay(
                                          domain: widget.playlist.providerMappings!.first.providerDomain,
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
                        // Playlist title with Hero animation
                        Hero(
                          tag: HeroTags.playlistTitle + (widget.playlist.uri ?? widget.playlist.itemId) + _heroTagSuffix,
                          child: Material(
                            color: Colors.transparent,
                            child: Text(
                              widget.playlist.name,
                              style: textTheme.headlineMedium?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Spacing.vGap8,
                        // Owner info
                        if (widget.playlist.owner != null)
                          Text(
                            S.of(context)!.byOwner(widget.playlist.owner!),
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        const SizedBox(height: 4),
                        // Track count
                        Text(
                          S.of(context)!.trackCount(_tracks.isNotEmpty ? _tracks.length : (widget.playlist.trackCount ?? 0)),
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        Spacing.vGap16,
                        // Action buttons row
                        Row(
                          children: [
                            // Main Play Button
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading || _tracks.isEmpty ? null : _playPlaylist,
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
                                  color: _isFavorite
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
                                      mediaType: ContextMenuMediaType.playlist,
                                      item: widget.playlist,
                                      isFavorite: _isFavorite,
                                      isInLibrary: _isInLibrary,
                                      onToggleFavorite: _toggleFavorite,
                                      onToggleLibrary: _toggleLibrary,
                                      adaptiveColorScheme: adaptiveScheme,
                                      showTopRow: false,
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
                        S.of(context)!.noTracksInPlaylist,
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.54),
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
                        final trackImageUrl = context.read<MusicAssistantProvider>().getImageUrl(track, size: 80);

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
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Track number
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${index + 1}',
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurface.withOpacity(0.5),
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Track artwork
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    color: colorScheme.surfaceContainerHighest,
                                    child: trackImageUrl != null
                                        ? CachedNetworkImage(
                                            imageUrl: trackImageUrl,
                                            fit: BoxFit.cover,
                                            memCacheWidth: 96,
                                            memCacheHeight: 96,
                                            fadeInDuration: Duration.zero,
                                            fadeOutDuration: Duration.zero,
                                            placeholder: (_, __) => const SizedBox(),
                                            errorWidget: (_, __, ___) => Icon(
                                              Icons.music_note,
                                              size: 24,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          )
                                        : Icon(
                                            Icons.music_note,
                                            size: 24,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                  ),
                                ),
                              ],
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
}
