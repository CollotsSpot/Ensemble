import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/album_details_screen.dart';
import '../constants/hero_tags.dart';
import '../constants/timings.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';
import '../services/metadata_service.dart';
import '../services/library_status_service.dart';
import '../l10n/app_localizations.dart';
import 'provider_icon.dart';
import 'media_context_menu.dart';
import 'library_status_builder.dart';

class AlbumCard extends StatefulWidget {
  final Album album;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  /// Image decode size in pixels. Defaults to 256.
  /// Use smaller values (e.g., 128) for list views, larger for grids.
  final int? imageCacheSize;

  const AlbumCard({
    super.key,
    required this.album,
    this.onTap,
    this.heroTagSuffix,
    this.imageCacheSize,
  });

  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> with LibraryStatusMixin {
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
    'album',
    widget.album.provider,
    widget.album.itemId,
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
      if (!service.isInLibrary(key) && widget.album.inLibrary) {
        service.setLibraryStatus(key, true);
      }
      if (!service.isFavorite(key) && (widget.album.favorite ?? false)) {
        service.setFavoriteStatus(key, true);
      }
    });
    _initFallbackImage();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  void _initFallbackImage() {
    // Check if MA has an image after first build, then fetch fallback if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final maProvider = context.read<MusicAssistantProvider>();
      final maImageUrl = maProvider.api?.getImageUrl(widget.album, size: 256);
      _cachedMaImageUrl = maImageUrl;

      if (maImageUrl == null && !_triedFallback) {
        _triedFallback = true;
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

  Future<void> _fetchFallbackImage() async {
    final fallbackUrl = await MetadataService.getAlbumImageUrl(
      widget.album.name,
      widget.album.artistsString,
    );
    if (fallbackUrl != null && mounted) {
      setState(() {
        _fallbackImageUrl = fallbackUrl;
      });
    }
  }

  void _onImageError() {
    // When MA image fails to load, try Deezer fallback
    if (!_triedFallback && !_maImageFailed) {
      _maImageFailed = true;
      _triedFallback = true;
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
        String actualProvider = widget.album.provider;
        String actualItemId = widget.album.itemId;

        if (widget.album.providerMappings != null && widget.album.providerMappings!.isNotEmpty) {
          final mapping = widget.album.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.album.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.album.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'album',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
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
          rollbackFavoriteOperation();
          return;
        }

        success = await maProvider.removeFromFavorites(
          mediaType: 'album',
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

        if (widget.album.providerMappings != null && widget.album.providerMappings!.isNotEmpty) {
          final nonLibraryMapping = widget.album.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        if (actualProvider == null || actualItemId == null) {
          if (widget.album.provider != 'library') {
            actualProvider = widget.album.provider;
            actualItemId = widget.album.itemId;
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    // Use cached URL if available, otherwise get fresh
    final maImageUrl = _cachedMaImageUrl ?? maProvider.api?.getImageUrl(widget.album, size: 256);
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

          // Start color extraction immediately (fire-and-forget)
          // Runs in isolate so won't block Hero animation
          // Results are cached, so detail screen gets them instantly
          if (imageUrl != null) {
            updateAdaptiveColorsFromImage(context, imageUrl);
          }

          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: AlbumDetailsScreen(
                album: widget.album,
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
            mediaType: ContextMenuMediaType.album,
            item: widget.album,
            isFavorite: isFavorite,
            isInLibrary: isInLibrary,
            onToggleFavorite: _toggleFavorite,
            onToggleLibrary: _toggleLibrary,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album artwork
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.albumCover + (widget.album.uri ?? widget.album.itemId) + suffix,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
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
                                  return Icon(
                                    Icons.album_rounded,
                                    size: 64,
                                    color: colorScheme.onSurfaceVariant,
                                  );
                                },
                              )
                            : Center(
                                child: Icon(
                                  Icons.album_rounded,
                                  size: 64,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                      // Provider icon overlay
                      if (widget.album.providerMappings?.isNotEmpty == true)
                        ProviderIconOverlay(
                          domain: widget.album.providerMappings!.first.providerDomain,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Album title with year
          // PERF: Removed Hero - text animations provide minimal benefit but add overhead
          Text(
            widget.album.nameWithYear,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          // Artist name
          Text(
            widget.album.artistsString,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          ],
        ),
      ),
    );
  }
}
