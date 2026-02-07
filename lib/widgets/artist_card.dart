import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/artist_details_screen.dart';
import '../constants/hero_tags.dart';
import '../constants/timings.dart';
import '../utils/page_transitions.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import '../services/library_status_service.dart';
import '../l10n/app_localizations.dart';
import 'media_context_menu.dart';
import 'library_status_builder.dart';

class ArtistCard extends StatefulWidget {
  final Artist artist;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  /// Image decode size in pixels. Defaults to 256.
  /// Use smaller values (e.g., 128) for list views, larger for grids.
  final int? imageCacheSize;

  const ArtistCard({
    super.key,
    required this.artist,
    this.onTap,
    this.heroTagSuffix,
    this.imageCacheSize,
  });

  @override
  State<ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<ArtistCard> with LibraryStatusMixin {
  static final _logger = DebugLogger();
  String? _fallbackImageUrl;
  bool _triedFallback = false;
  bool _maImageFailed = false;
  String? _cachedMaImageUrl;
  Timer? _fallbackTimer;
  bool _isNavigating = false;

  /// Delay before fetching fallback images to avoid requests during fast scroll
  /// PERF: Increased from 200ms to 400ms to reduce network requests during slow scroll
  static const _fallbackDelay = Duration(milliseconds: 400);

  @override
  String get libraryItemKey => LibraryStatusService.makeKey(
    'artist',
    widget.artist.provider,
    widget.artist.itemId,
  );

  @override
  void initState() {
    super.initState();
    // Defer status initialization to after the build frame completes.
    // setLibraryStatus() calls notifyListeners() synchronously, which triggers
    // setState() in listening widgets — illegal during the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final service = LibraryStatusService.instance;
      final key = libraryItemKey;
      if (!service.isInLibrary(key) && widget.artist.inLibrary) {
        service.setLibraryStatus(key, true);
      }
      if (!service.isFavorite(key) && (widget.artist.favorite ?? false)) {
        service.setFavoriteStatus(key, true);
      }
    });
    // Fetch fallback image once in initState, not during build
    _initFallbackImage();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  void _initFallbackImage() {
    // We'll check if MA has an image after first build, then fetch fallback if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final maProvider = context.read<MusicAssistantProvider>();
      final maImageUrl = maProvider.api?.getImageUrl(widget.artist, size: 256);
      _cachedMaImageUrl = maImageUrl;

      if (maImageUrl == null && !_triedFallback) {
        _triedFallback = true;
        _logger.debug('No MA image for "${widget.artist.name}", scheduling fallback', context: 'ArtistCard');
        _scheduleFallbackFetch();
      }
    });
  }

  /// Schedule fallback fetch with delay to avoid requests during fast scroll
  void _scheduleFallbackFetch() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(_fallbackDelay, () {
      if (mounted) {
        _fetchFallbackImage();
      }
    });
  }

  void _onImageError() {
    // When MA image fails to load, try Deezer fallback
    if (!_triedFallback && !_maImageFailed) {
      _maImageFailed = true;
      _triedFallback = true;
      _logger.debug('MA image failed for "${widget.artist.name}", scheduling fallback', context: 'ArtistCard');
      _scheduleFallbackFetch();
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
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

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
          rollbackFavoriteOperation();
          return;
        }

        success = await maProvider.removeFromFavorites(
          mediaType: 'artist',
          libraryItemId: libraryItemId,
        );
      }

      if (success && mounted) {
        completeFavoriteOperation();
        maProvider.invalidateHomeCache();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newState ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites),
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        rollbackFavoriteOperation();
      }
    } catch (e) {
      rollbackFavoriteOperation();
    }
  }

  Future<void> _toggleLibrary() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final currentInLibrary = isInLibrary;
    final newState = !currentInLibrary;

    try {
      if (newState) {
        String? actualProvider;
        String? actualItemId;

        if (widget.artist.providerMappings != null && widget.artist.providerMappings!.isNotEmpty) {
          final nonLibraryMapping = widget.artist.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        if (actualProvider == null || actualItemId == null) {
          if (widget.artist.provider != 'library') {
            actualProvider = widget.artist.provider;
            actualItemId = widget.artist.itemId;
          } else {
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

        if (libraryItemId == null) return;

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
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    // Use cached URL if available, otherwise get fresh (but don't trigger fetches during build)
    final maImageUrl = _cachedMaImageUrl ?? maProvider.api?.getImageUrl(widget.artist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

    // Use fallback if MA image failed or wasn't available
    final imageUrl = (_maImageFailed || maImageUrl == null) ? _fallbackImageUrl : maImageUrl;

    // PERF: Use appropriate cache size based on display size
    final cacheSize = widget.imageCacheSize ?? 256;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap ?? () {
          // Prevent double-tap navigation
          if (_isNavigating) return;
          _isNavigating = true;

          // PERF: Color extraction deferred to detail screen's initState
          // to avoid competing with Hero animation for GPU resources
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: ArtistDetailsScreen(
                artist: widget.artist,
                heroTagSuffix: widget.heroTagSuffix,
                initialImageUrl: imageUrl,
              ),
            ),
          ).then((_) {
            // Reset after navigation debounce delay
            Future.delayed(Timings.navigationDebounce, () {
              if (mounted) _isNavigating = false;
            });
          });
        },
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.artist,
            item: widget.artist,
            isFavorite: isFavorite,
            isInLibrary: isInLibrary,
            onToggleFavorite: _toggleFavorite,
            onToggleLibrary: _toggleLibrary,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Artist image - circular
            // PERF: Use AspectRatio instead of LayoutBuilder to provide fixed geometry
            // before Hero animation starts. This prevents grey icon flash caused by
            // dynamic sizing inside the Hero widget.
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.artistImage + (widget.artist.uri ?? widget.artist.itemId) + suffix,
                child: ClipOval(
                  child: Container(
                    color: colorScheme.surfaceVariant,
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: cacheSize,
                            memCacheHeight: cacheSize,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (context, url) => const SizedBox(),
                            errorWidget: (context, url, error) {
                              // Try fallback on error (only for MA URLs, not fallback URLs)
                              if (!_maImageFailed && url == maImageUrl) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _onImageError();
                                });
                              }
                              return Center(
                                child: Icon(
                                  Icons.person_rounded,
                                  size: 64,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Icon(
                              Icons.person_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Artist name - fixed height container so image size is consistent
          // PERF: Removed Hero - text animations provide minimal benefit but add overhead
          SizedBox(
            height: 36, // Fixed height for 2 lines of text
            child: Text(
              widget.artist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchFallbackImage() async {
    final fallbackUrl = await MetadataService.getArtistImageUrl(widget.artist.name);
    if (fallbackUrl != null && mounted) {
      _logger.debug('Found fallback image for "${widget.artist.name}"', context: 'ArtistCard');
      setState(() {
        _fallbackImageUrl = fallbackUrl;
      });
    }
  }
}
