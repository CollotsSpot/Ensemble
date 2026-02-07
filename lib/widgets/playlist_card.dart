import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/playlist_details_screen.dart';
import '../constants/hero_tags.dart';
import '../constants/timings.dart';
import '../utils/page_transitions.dart';
import '../services/library_status_service.dart';
import '../l10n/app_localizations.dart';
import 'provider_icon.dart';
import 'media_context_menu.dart';
import 'library_status_builder.dart';

class PlaylistCard extends StatefulWidget {
  final Playlist playlist;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  final int? imageCacheSize;

  const PlaylistCard({
    super.key,
    required this.playlist,
    this.onTap,
    this.heroTagSuffix,
    this.imageCacheSize,
  });

  @override
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard> with LibraryStatusMixin {
  bool _isNavigating = false;

  @override
  String get libraryItemKey => LibraryStatusService.makeKey(
    'playlist',
    widget.playlist.provider,
    widget.playlist.itemId,
  );

  @override
  void initState() {
    super.initState();
    // Initialize status in centralized service from widget data
    final service = LibraryStatusService.instance;
    final key = libraryItemKey;
    if (!service.isInLibrary(key) && widget.playlist.inLibrary) {
      service.setLibraryStatus(key, true);
    }
    if (!service.isFavorite(key) && (widget.playlist.favorite ?? false)) {
      service.setFavoriteStatus(key, true);
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

        success = await maProvider.addToFavorites(
          mediaType: 'playlist',
          itemId: actualItemId,
          provider: actualProvider,
        );
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

        if (libraryItemId == null) {
          rollbackFavoriteOperation();
          return;
        }

        success = await maProvider.removeFromFavorites(
          mediaType: 'playlist',
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
          mediaType: 'playlist',
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
          mediaType: 'playlist',
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
    final imageUrl = maProvider.api?.getImageUrl(widget.playlist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';
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
              child: PlaylistDetailsScreen(
                playlist: widget.playlist,
                heroTagSuffix: widget.heroTagSuffix,
                initialImageUrl: imageUrl,
              ),
            ),
          );

          // Reset after navigation debounce delay
          Future.delayed(Timings.navigationDebounce, () {
            if (mounted) _isNavigating = false;
          });
        },
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.playlist,
            item: widget.playlist,
            isFavorite: isFavorite,
            isInLibrary: isInLibrary,
            onToggleFavorite: _toggleFavorite,
            onToggleLibrary: _toggleLibrary,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Playlist artwork
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.playlistCover + (widget.playlist.uri ?? widget.playlist.itemId) + suffix,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: cacheSize,
                                memCacheHeight: cacheSize,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (context, url) => const SizedBox(),
                                errorWidget: (context, url, error) => Center(
                                  child: Icon(
                                    Icons.playlist_play_rounded,
                                    size: 64,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : Center(
                                child: Icon(
                                  Icons.playlist_play_rounded,
                                  size: 64,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                      // Provider icon overlay
                      if (widget.playlist.providerMappings?.isNotEmpty == true)
                        ProviderIconOverlay(
                          domain: widget.playlist.providerMappings!.first.providerDomain,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Playlist title
            // PERF: Removed Hero - text animations provide minimal benefit but add overhead
            Text(
              widget.playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            // Owner/track count
            Text(
              widget.playlist.owner ?? (widget.playlist.trackCount != null ? '${widget.playlist.trackCount} tracks' : ''),
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
