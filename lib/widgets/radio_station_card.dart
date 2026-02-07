import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';
import '../constants/timings.dart';
import '../services/library_status_service.dart';
import '../l10n/app_localizations.dart';
import 'media_context_menu.dart';
import 'library_status_builder.dart';

class RadioStationCard extends StatefulWidget {
  final MediaItem radioStation;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  final int? imageCacheSize;

  const RadioStationCard({
    super.key,
    required this.radioStation,
    this.onTap,
    this.heroTagSuffix,
    this.imageCacheSize,
  });

  @override
  State<RadioStationCard> createState() => _RadioStationCardState();
}

class _RadioStationCardState extends State<RadioStationCard> with LibraryStatusMixin {
  bool _isTapping = false;

  @override
  String get libraryItemKey => LibraryStatusService.makeKey(
    'radio',
    widget.radioStation.provider,
    widget.radioStation.itemId,
  );

  @override
  void initState() {
    super.initState();
    // Initialize status in centralized service from widget data
    final service = LibraryStatusService.instance;
    final key = libraryItemKey;
    if (!service.isInLibrary(key) && widget.radioStation.inLibrary) {
      service.initLibraryStatus(key, true);
    }
    if (!service.isFavorite(key) && (widget.radioStation.favorite ?? false)) {
      service.initFavoriteStatus(key, true);
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
        String actualProvider = widget.radioStation.provider;
        String actualItemId = widget.radioStation.itemId;

        if (widget.radioStation.providerMappings != null && widget.radioStation.providerMappings!.isNotEmpty) {
          final mapping = widget.radioStation.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.radioStation.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.radioStation.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'radio',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        int? libraryItemId;
        if (widget.radioStation.provider == 'library') {
          libraryItemId = int.tryParse(widget.radioStation.itemId);
        } else if (widget.radioStation.providerMappings != null) {
          final libraryMapping = widget.radioStation.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.radioStation.providerMappings!.first,
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
          mediaType: 'radio',
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

        if (widget.radioStation.providerMappings != null && widget.radioStation.providerMappings!.isNotEmpty) {
          final nonLibraryMapping = widget.radioStation.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        if (actualProvider == null || actualItemId == null) {
          if (widget.radioStation.provider != 'library') {
            actualProvider = widget.radioStation.provider;
            actualItemId = widget.radioStation.itemId;
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
          mediaType: 'radio',
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
        if (widget.radioStation.provider == 'library') {
          libraryItemId = int.tryParse(widget.radioStation.itemId);
        } else if (widget.radioStation.providerMappings != null) {
          final libraryMapping = widget.radioStation.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.radioStation.providerMappings!.first,
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
          mediaType: 'radio',
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
    final imageUrl = maProvider.api?.getImageUrl(widget.radioStation, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';
    final cacheSize = widget.imageCacheSize ?? 256;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap ?? () {
          // Prevent double-tap actions
          if (_isTapping) return;
          _isTapping = true;

          HapticFeedback.mediumImpact();
          // Play the radio station on selected player
          final selectedPlayer = maProvider.selectedPlayer;
          if (selectedPlayer != null) {
            maProvider.api?.playRadioStation(selectedPlayer.playerId, widget.radioStation);
          }

          // Reset after debounce delay
          Future.delayed(Timings.navigationDebounce, () {
            if (mounted) _isTapping = false;
          });
        },
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.radio,
            item: widget.radioStation,
            isFavorite: isFavorite,
            isInLibrary: isInLibrary,
            onToggleFavorite: _toggleFavorite,
            onToggleLibrary: _toggleLibrary,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Radio station artwork - circular for radio
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.radioCover + (widget.radioStation.uri ?? widget.radioStation.itemId) + suffix,
                child: ClipOval(
                  child: Container(
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
                                Icons.radio_rounded,
                                size: 64,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.radio_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Radio station name - fixed height container so image size is consistent
            SizedBox(
              height: 36, // Fixed height for 2 lines of text
              child: Hero(
                tag: HeroTags.radioTitle + (widget.radioStation.uri ?? widget.radioStation.itemId) + suffix,
                child: Material(
                  color: Colors.transparent,
                  child: Text(
                    widget.radioStation.name,
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
