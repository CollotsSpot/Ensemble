import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/music_assistant_provider.dart';
import '../../services/settings_service.dart';
import '../../theme/design_tokens.dart';
import '../../theme/palette_helper.dart';
import '../../constants/timings.dart';
import '../global_player_overlay.dart';
import 'player_card.dart';

/// Overlay that reveals all available players with a staggered slide-up animation.
/// Triggered by swiping down on the mini player or tapping the device button.
class PlayerRevealOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  final double miniPlayerBottom; // Bottom position of mini player
  final double miniPlayerHeight;
  final bool showOnboardingHints; // Show additional hints for first-time users

  /// Callback when player is selected for a pending action (e.g., "Play On").
  /// If null, selecting a player just switches to that player.
  final void Function(dynamic player)? onPlayerSelected;

  /// Context hint to display instead of default hints (e.g., "Select player to play album").
  final String? contextHint;

  /// Icon for context hint (default: play_circle_outline).
  final IconData? contextHintIcon;

  const PlayerRevealOverlay({
    super.key,
    required this.onDismiss,
    required this.miniPlayerBottom,
    required this.miniPlayerHeight,
    this.showOnboardingHints = false,
    this.onPlayerSelected,
    this.contextHint,
    this.contextHintIcon,
  });

  @override
  State<PlayerRevealOverlay> createState() => PlayerRevealOverlayState();
}

class PlayerRevealOverlayState extends State<PlayerRevealOverlay>
    with TickerProviderStateMixin {
  late AnimationController _revealController;
  late Animation<double> _revealAnimation;
  late Animation<double> _backdropAnimation;

  Timer? _refreshTimer;

  // Track vertical drag for dismissal
  bool _isDragging = false;

  // Threshold for drag-to-dismiss (in animation value, 0.0-1.0)
  static const double _dismissThreshold = 0.7;

  // Scroll controller for when player list overflows
  final ScrollController _scrollController = ScrollController();
  bool _isScrollable = false;

  // Cache extracted colors per player for per-device accent colors
  final Map<String, ColorScheme?> _playerColors = {};

  // Hint system
  bool _showHints = true;

  // PERF: Pre-cached static BoxShadow to avoid allocation per frame
  static const BoxShadow _cardShadow = BoxShadow(
    color: Color(0x33000000), // 20% black
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  @override
  void initState() {
    super.initState();

    // Load hint settings
    _loadHintSettings();

    _revealController = AnimationController(
      vsync: this,
    );

    // Quick smooth animation with subtle overshoot
    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _backdropAnimation = CurvedAnimation(
      parent: _revealController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );

    // Preload all player track info and extract colors
    _preloadColorsForPlayers();

    // Start reveal animation
    _revealController.duration = const Duration(milliseconds: 200);
    _revealController.forward();

    // Auto-refresh player data
    _refreshTimer = Timer.periodic(Timings.playerPollingInterval, (_) async {
      if (mounted) {
        final provider = context.read<MusicAssistantProvider>();
        provider.refreshPlayers();
        await provider.preloadAllPlayerTracks();
        _preloadColorsForPlayers();
      }
    });
  }

  Future<void> _loadHintSettings() async {
    final value = await SettingsService.getShowHints();
    if (mounted) setState(() => _showHints = value);
  }

  /// Extract accent colors from album art for each player
  Future<void> _preloadColorsForPlayers() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await maProvider.preloadAllPlayerTracks();

    final players = maProvider.availablePlayers;
    for (final player in players) {
      if (_playerColors.containsKey(player.playerId)) continue;

      final track = maProvider.getCachedTrackForPlayer(player.playerId);
      if (track == null) continue;

      final imageUrl = maProvider.getImageUrl(track, size: 128);
      if (imageUrl == null) continue;

      try {
        final imageProvider = NetworkImage(imageUrl);
        final schemes = await PaletteHelper.extractColorSchemes(imageProvider);
        if (mounted && schemes != null) {
          final colorScheme = isDark ? schemes.$2 : schemes.$1;
          setState(() {
            _playerColors[player.playerId] = colorScheme;
          });
        }
      } catch (_) {
        // Ignore color extraction errors
      }
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Animate reveal (called from parent)
  void reveal() {
    _revealController.duration = const Duration(milliseconds: 200);
    _revealController.forward();
  }

  /// Animate dismissal and call callback when done
  Future<void> dismiss() async {
    // Trigger single bounce on mini player when cards are ~70% collapsed
    // This creates the effect of cards "landing" on the mini player
    bool bounceFired = false;
    void fireBounce() {
      if (!bounceFired) {
        bounceFired = true;
        GlobalPlayerOverlay.triggerBounce();
      }
    }

    void checkBounce() {
      if (_revealController.value < 0.3) {
        fireBounce();
      }
    }

    // If user already dragged past bounce threshold, fire immediately
    if (_revealController.value < 0.3) {
      fireBounce();
    }

    _revealController.duration = const Duration(milliseconds: 150);
    _revealController.addListener(checkBounce);
    await _revealController.reverse();
    _revealController.removeListener(checkBounce);
    widget.onDismiss();
  }

  /// Check if scroll is at top (or not scrollable)
  bool get _isAtTop {
    if (!_isScrollable) return true;
    if (!_scrollController.hasClients) return true;
    return _scrollController.offset <= 0;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;

    // If scrollable and not at top, let scroll handle it
    if (_isScrollable && !_isAtTop) {
      // Scroll the list
      if (_scrollController.hasClients) {
        final newOffset = _scrollController.offset - delta;
        _scrollController.jumpTo(newOffset.clamp(0.0, _scrollController.position.maxScrollExtent));
      }
      return;
    }

    // At top: check if trying to scroll down (view more) or dismiss
    if (_isScrollable && delta < 0 && _scrollController.hasClients) {
      // Swiping up (delta negative) = scroll down to see more players
      final newOffset = _scrollController.offset - delta;
      _scrollController.jumpTo(newOffset.clamp(0.0, _scrollController.position.maxScrollExtent));
      return;
    }

    // Only process dismiss gesture when swiping DOWN (positive delta = finger moving down)
    // Ignore swipe up when not scrollable - cards should stay fixed
    if (delta <= 0) return;

    // Swiping down = dismiss gesture - directly control animation controller
    _isDragging = true;

    // Convert drag delta to animation value change
    // Use average card travel distance (~150px) as reference
    const dragSensitivity = 150.0;
    final valueDelta = delta / dragSensitivity;

    // Decrease animation value (cards move down)
    final newValue = (_revealController.value - valueDelta).clamp(0.0, 1.0);
    _revealController.value = newValue;
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

    // If not dragging (was scrolling), don't dismiss
    if (!_isDragging) return;
    _isDragging = false;

    // Dismiss if dragged past threshold or with enough velocity
    if (_revealController.value < _dismissThreshold || velocity > 500) {
      HapticFeedback.lightImpact();
      dismiss();
    } else {
      // Spring back to fully revealed
      _revealController.duration = const Duration(milliseconds: 150);
      _revealController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // PERF Phase 4: Pre-compute hint colors outside animation loop
    final hintColor = colorScheme.onSurface.withOpacity(0.7);

    // Back gesture is handled at GlobalPlayerOverlay level
    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final allPlayers = maProvider.availablePlayers;
        final selectedPlayer = maProvider.selectedPlayer;
        final currentTrack = maProvider.currentTrack;

        // Filter out the selected player - it's already shown in the mini player
        final players = allPlayers
            .where((p) => p.playerId != selectedPlayer?.playerId)
            .toList();

        // Default card colors - used when player doesn't have extracted colors
        final defaultBgColor = colorScheme.primaryContainer;
        final defaultTextColor = colorScheme.onPrimaryContainer;

        // Calculate total stack height for animation
        const cardHeight = 64.0;
        const cardSpacing = 12.0;
        final totalStackHeight = players.length * cardHeight + (players.length - 1) * cardSpacing;

        // Calculate max available height (80% of screen minus mini player area)
        final screenHeight = MediaQuery.of(context).size.height;
        final statusBarHeight = MediaQuery.of(context).padding.top;
        final bottomPadding = widget.miniPlayerBottom + widget.miniPlayerHeight + 20;
        final maxListHeight = (screenHeight - statusBarHeight - bottomPadding) * 0.8;

        // Determine if scrolling is needed
        final needsScroll = totalStackHeight > maxListHeight;
        // Update scrollable state (used by gesture handlers)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isScrollable != needsScroll) {
            _isScrollable = needsScroll;
          }
        });

        // PERF Phase 4: Pre-compute player card data OUTSIDE AnimatedBuilder
        // This avoids re-gathering player data every animation frame
        final playerDataList = players.map((player) {
          final isPlaying = player.state == 'playing';
          final playerTrack = maProvider.getCachedTrackForPlayer(player.playerId);
          String? albumArtUrl;
          if (playerTrack != null && player.available && player.powered) {
            albumArtUrl = maProvider.getImageUrl(playerTrack, size: 128);
          }
          final playerColorScheme = _playerColors[player.playerId];
          final cardBgColor = playerColorScheme?.primaryContainer ?? defaultBgColor;
          final cardTextColor = playerColorScheme?.onPrimaryContainer ?? defaultTextColor;
          final isGrouped = maProvider.isPlayerManuallySynced(player.playerId);

          return _PlayerCardData(
            player: player,
            playerTrack: playerTrack,
            albumArtUrl: albumArtUrl,
            isPlaying: isPlaying,
            isGrouped: isGrouped,
            cardBgColor: cardBgColor,
            cardTextColor: cardTextColor,
          );
        }).toList();

        return AnimatedBuilder(
          animation: _revealAnimation,
          builder: (context, child) {
            final t = _revealAnimation.value;

            return Stack(
              children: [
                // Backdrop - tap to dismiss (darkness handled by GlobalPlayerOverlay)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: dismiss,
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox.expand(),
                  ),
                ),

                // Player cards - positioned above mini player
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: widget.miniPlayerBottom + widget.miniPlayerHeight + 8,
                  child: GestureDetector(
                    onVerticalDragUpdate: _handleVerticalDragUpdate,
                    onVerticalDragEnd: _handleVerticalDragEnd,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Hint above player list - different for onboarding vs regular use
                        // Onboarding: show first-time hint (how to select)
                        // Regular: show sync hint (tap and hold to sync)
                        if (players.isNotEmpty && (_showHints || widget.showOnboardingHints))
                          Builder(
                            builder: (context) {
                              // Calculate slide offset to match the topmost card
                              const baseOffset = 80.0;
                              final hintDistanceToTravel = baseOffset + (players.length * (cardHeight + cardSpacing));
                              final hintSlideOffset = hintDistanceToTravel * (1.0 - t);

                              // Show different hint for onboarding vs regular use
                              final isOnboarding = widget.showOnboardingHints;

                              // PERF Phase 4: Use pre-computed hintColor
                              Widget buildHintRow(IconData icon, String text) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icon,
                                      size: 18,
                                      color: hintColor,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      text,
                                      style: TextStyle(
                                        color: hintColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Transform.translate(
                                offset: Offset(0, hintSlideOffset),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: widget.contextHint != null
                                        ? buildHintRow(
                                            widget.contextHintIcon ?? Icons.play_circle_outline,
                                            widget.contextHint!,
                                          )
                                        : isOnboarding
                                            ? buildHintRow(Icons.touch_app_outlined, S.of(context)!.selectPlayerHint)
                                            : Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  buildHintRow(Icons.lightbulb_outline, S.of(context)!.holdToSync),
                                                  const SizedBox(height: 4),
                                                  buildHintRow(Icons.lightbulb_outline, S.of(context)!.swipeToAdjustVolume),
                                                ],
                                              ),
                                  ),
                                ),
                              );
                            },
                          ),
                        // Build player cards - scrollable when overflow, otherwise static
                        // Using ListView.builder for many players: only builds visible items
                        // This significantly improves animation performance with 10+ players
                        // PERF Phase 4: Use pre-computed playerDataList
                        if (needsScroll)
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: maxListHeight),
                            child: ListView.builder(
                              controller: _scrollController,
                              physics: const ClampingScrollPhysics(),
                              itemCount: playerDataList.length,
                              // Fixed height per item for optimal scroll performance
                              itemExtent: cardHeight + cardSpacing,
                              itemBuilder: (context, index) {
                                final data = playerDataList[index];

                                // Animation: slide from behind mini player
                                // Only calculate for items that will be built (visible ones)
                                const baseOffset = 80.0;
                                final reverseIndex = playerDataList.length - 1 - index;
                                final distanceToTravel = baseOffset + (reverseIndex * (cardHeight + cardSpacing));
                                final slideOffset = distanceToTravel * (1.0 - t);

                                return Transform.translate(
                                  offset: Offset(0, slideOffset),
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: cardSpacing),
                                    child: PlayerCard(
                                      player: data.player,
                                      trackInfo: data.playerTrack,
                                      albumArtUrl: data.albumArtUrl,
                                      isSelected: false,
                                      isPlaying: data.isPlaying,
                                      isGrouped: data.isGrouped,
                                      backgroundColor: data.cardBgColor,
                                      textColor: data.cardTextColor,
                                      onTap: () {
                                        HapticFeedback.mediumImpact();
                                        if (widget.onPlayerSelected != null) {
                                          widget.onPlayerSelected!(data.player);
                                        } else {
                                          maProvider.selectPlayer(data.player);
                                        }
                                        dismiss();
                                      },
                                      onLongPress: () {
                                        HapticFeedback.mediumImpact();
                                        maProvider.togglePlayerSync(data.player.playerId);
                                      },
                                      onPlayPause: () {
                                        if (data.isPlaying) {
                                          maProvider.pausePlayer(data.player.playerId);
                                        } else {
                                          maProvider.resumePlayer(data.player.playerId);
                                        }
                                      },
                                      onSkipNext: () => maProvider.nextTrack(data.player.playerId),
                                      onPower: () => maProvider.togglePower(data.player.playerId),
                                      onVolumeChange: (volume) => maProvider.setVolume(data.player.playerId, (volume * 100).round()),
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        else
                        // Non-scrollable list for when players fit
                        // PERF Phase 4: Use pre-computed playerDataList
                        ...List.generate(playerDataList.length, (index) {
                          final data = playerDataList[index];

                          // Animation: all cards start hidden behind mini player
                          // and fan out to their final positions with spring physics
                          const baseOffset = 80.0;
                          final reverseIndex = playerDataList.length - 1 - index;
                          final distanceToTravel = baseOffset + (reverseIndex * (cardHeight + cardSpacing));

                          // Use the elastic animation value directly (already has bounce)
                          final slideOffset = distanceToTravel * (1.0 - t);

                          return Transform.translate(
                            offset: Offset(0, slideOffset),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: PlayerCard(
                                player: data.player,
                                trackInfo: data.playerTrack,
                                albumArtUrl: data.albumArtUrl,
                                isSelected: false,
                                isPlaying: data.isPlaying,
                                isGrouped: data.isGrouped,
                                backgroundColor: data.cardBgColor,
                                textColor: data.cardTextColor,
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  if (widget.onPlayerSelected != null) {
                                    widget.onPlayerSelected!(data.player);
                                  } else {
                                    maProvider.selectPlayer(data.player);
                                  }
                                  dismiss();
                                },
                                onLongPress: () {
                                  HapticFeedback.mediumImpact();
                                  maProvider.togglePlayerSync(data.player.playerId);
                                },
                                onPlayPause: () {
                                  if (data.isPlaying) {
                                    maProvider.pausePlayer(data.player.playerId);
                                  } else {
                                    maProvider.resumePlayer(data.player.playerId);
                                  }
                                },
                                onSkipNext: () => maProvider.nextTrack(data.player.playerId),
                                onPower: () => maProvider.togglePower(data.player.playerId),
                                onVolumeChange: (volume) => maProvider.setVolume(data.player.playerId, (volume * 100).round()),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// PERF Phase 4: Pre-computed player card data to avoid gathering per animation frame
class _PlayerCardData {
  final dynamic player;
  final dynamic playerTrack;
  final String? albumArtUrl;
  final bool isPlaying;
  final bool isGrouped;
  final Color cardBgColor;
  final Color cardTextColor;

  const _PlayerCardData({
    required this.player,
    required this.playerTrack,
    required this.albumArtUrl,
    required this.isPlaying,
    required this.isGrouped,
    required this.cardBgColor,
    required this.cardTextColor,
  });
}
