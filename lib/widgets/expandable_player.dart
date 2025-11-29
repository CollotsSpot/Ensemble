import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';
import '../screens/queue_screen.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import 'animated_icon_button.dart';
import 'volume_control.dart';

/// A unified player widget that seamlessly expands from mini to full-screen.
///
/// Uses smooth morphing animations where each element (album art, track info,
/// controls) transitions smoothly from their mini to full positions.
class ExpandablePlayer extends StatefulWidget {
  /// Whether there's a bottom navigation bar below this player.
  /// When true, the collapsed player will be positioned above the nav bar.
  final bool hasBottomNav;

  const ExpandablePlayer({
    super.key,
    this.hasBottomNav = false,
  });

  @override
  State<ExpandablePlayer> createState() => ExpandablePlayerState();
}

class ExpandablePlayerState extends State<ExpandablePlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  // Adaptive theme colors extracted from album art
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  String? _lastImageUrl;

  // Queue state
  PlayerQueue? _queue;
  bool _isLoadingQueue = false;

  // Progress timer for elapsed time updates
  Timer? _progressTimer;
  double? _seekPosition;

  // Collapsed dimensions
  static const double _collapsedHeight = 64.0;
  static const double _collapsedMargin = 8.0;
  static const double _collapsedBorderRadius = 16.0;
  static const double _collapsedArtSize = 64.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.forward) {
        _loadQueue();
        _startProgressTimer();
      } else if (status == AnimationStatus.dismissed) {
        _progressTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  void expand() {
    _controller.forward();
  }

  void collapse() {
    _controller.reverse();
  }

  bool get isExpanded => _controller.value > 0.5;

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && isExpanded) {
        setState(() {});
      }
    });
  }

  Future<void> _loadQueue() async {
    if (_isLoadingQueue) return;

    setState(() => _isLoadingQueue = true);

    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player != null && maProvider.api != null) {
      final queue = await maProvider.api!.getQueue(player.playerId);
      if (mounted) {
        setState(() {
          _queue = queue;
          _isLoadingQueue = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingQueue = false);
      }
    }
  }

  Future<void> _extractColors(String imageUrl) async {
    if (_lastImageUrl == imageUrl) return;
    _lastImageUrl = imageUrl;

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
      print('Failed to extract colors: $e');
    }
  }

  Future<void> _toggleShuffle() async {
    if (_queue == null) return;
    final maProvider = context.read<MusicAssistantProvider>();
    await maProvider.toggleShuffle(_queue!.playerId);
    await _loadQueue();
  }

  Future<void> _cycleRepeat() async {
    if (_queue == null) return;
    final maProvider = context.read<MusicAssistantProvider>();
    await maProvider.cycleRepeatMode(_queue!.playerId, _queue!.repeatMode);
    await _loadQueue();
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final selectedPlayer = maProvider.selectedPlayer;
        final currentTrack = maProvider.currentTrack;

        // Don't show if no track or player
        if (currentTrack == null || selectedPlayer == null) {
          return const SizedBox.shrink();
        }

        final imageUrl = maProvider.getImageUrl(currentTrack, size: 512);

        // Extract colors for adaptive theme
        if (themeProvider.adaptiveTheme && imageUrl != null) {
          _extractColors(imageUrl);
        }

        return AnimatedBuilder(
          animation: _expandAnimation,
          builder: (context, _) {
            return _buildMorphingPlayer(
              context,
              maProvider,
              selectedPlayer,
              currentTrack,
              imageUrl,
              themeProvider,
            );
          },
        );
      },
    );
  }

  Widget _buildMorphingPlayer(
    BuildContext context,
    MusicAssistantProvider maProvider,
    dynamic selectedPlayer,
    dynamic currentTrack,
    String? imageUrl,
    ThemeProvider themeProvider,
  ) {
    final screenSize = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final topPadding = MediaQuery.of(context).padding.top;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Animation progress
    final t = _expandAnimation.value;

    // Get adaptive colors if available
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    // Color transitions
    final collapsedBg = colorScheme.primaryContainer;
    final expandedBg = adaptiveScheme?.surface ?? const Color(0xFF1a1a1a);
    final backgroundColor = Color.lerp(collapsedBg, expandedBg, t)!;

    final collapsedTextColor = colorScheme.onPrimaryContainer;
    final expandedTextColor = adaptiveScheme?.onSurface ?? Colors.white;
    final textColor = Color.lerp(collapsedTextColor, expandedTextColor, t)!;

    final primaryColor = adaptiveScheme?.primary ?? Colors.white;

    // Container dimensions
    const bottomNavHeight = 56.0;
    final collapsedBottomOffset = widget.hasBottomNav
        ? bottomNavHeight + bottomPadding + _collapsedMargin
        : bottomPadding + _collapsedMargin; // Include safe area even without nav

    final collapsedWidth = screenSize.width - (_collapsedMargin * 2);
    final width = lerpDouble(collapsedWidth, screenSize.width, t);
    final height = lerpDouble(_collapsedHeight, screenSize.height, t);
    final horizontalMargin = lerpDouble(_collapsedMargin, 0, t);
    final bottomOffset = lerpDouble(collapsedBottomOffset, 0, t);
    final borderRadius = lerpDouble(_collapsedBorderRadius, 0, t);

    // Album art morphing calculations
    final expandedArtSize = screenSize.width * 0.75;
    final artSize = lerpDouble(_collapsedArtSize, expandedArtSize, t);
    final artBorderRadius = lerpDouble(_collapsedBorderRadius, 16, t);

    // Art position: left-aligned in collapsed, centered in expanded
    final collapsedArtLeft = 0.0;
    final expandedArtLeft = (screenSize.width - expandedArtSize) / 2;
    final artLeft = lerpDouble(collapsedArtLeft, expandedArtLeft, t);

    // Art vertical position: centered in collapsed bar, upper area in expanded
    final collapsedArtTop = 0.0;
    final expandedArtTop = topPadding + 80;
    final artTop = lerpDouble(collapsedArtTop, expandedArtTop, t);

    // Track title morphing
    final collapsedTitleFontSize = 14.0;
    final expandedTitleFontSize = 24.0;
    final titleFontSize = lerpDouble(collapsedTitleFontSize, expandedTitleFontSize, t);

    // Title position: next to art in collapsed, centered below art in expanded
    final collapsedTitleLeft = _collapsedArtSize + 12;
    final expandedTitleLeft = 24.0;
    final titleLeft = lerpDouble(collapsedTitleLeft, expandedTitleLeft, t);

    final collapsedTitleTop = (_collapsedHeight - 32) / 2; // Centered vertically
    final expandedTitleTop = expandedArtTop + expandedArtSize + 40;
    final titleTop = lerpDouble(collapsedTitleTop, expandedTitleTop, t);

    final collapsedTitleWidth = screenSize.width - _collapsedArtSize - 150; // Leave room for controls
    final expandedTitleWidth = screenSize.width - 48;
    final titleWidth = lerpDouble(collapsedTitleWidth, expandedTitleWidth, t);

    // Artist name morphing
    final collapsedArtistFontSize = 12.0;
    final expandedArtistFontSize = 16.0;
    final artistFontSize = lerpDouble(collapsedArtistFontSize, expandedArtistFontSize, t);

    final collapsedArtistTop = collapsedTitleTop + 18;
    final expandedArtistTop = expandedTitleTop + 40;
    final artistTop = lerpDouble(collapsedArtistTop, expandedArtistTop, t);

    // Controls morphing - calculate based on actual button widths
    // Collapsed: just prev(28) + play(34) + next(28) = 90, plus some padding
    // Expanded: shuffle(48) + prev(42) + play(72) + next(42) + repeat(48) + gaps = ~300
    final collapsedControlsRight = 8.0;
    final controlsRight = collapsedControlsRight; // Only used when collapsed

    // Vertical: in collapsed, center the 34px play button in 64px height
    final collapsedControlsTop = (_collapsedHeight - 34) / 2 - 2; // Slight adjustment up
    final expandedControlsTop = expandedArtistTop + 100;
    final controlsTop = lerpDouble(collapsedControlsTop, expandedControlsTop, t);

    // Control button sizes
    final skipButtonSize = lerpDouble(28, 42, t);
    final playButtonSize = lerpDouble(34, 42, t);
    final playButtonContainerSize = lerpDouble(34, 72, t);

    // Progress bar and extra controls opacity (only visible when expanded)
    final expandedElementsOpacity = Curves.easeIn.transform((t - 0.5).clamp(0, 0.5) * 2);

    // Volume control position
    final volumeTop = expandedControlsTop + 80;

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      bottom: bottomOffset,
      child: GestureDetector(
        onTap: () {
          if (!isExpanded) expand();
        },
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta! < -10 && !isExpanded) {
            expand();
          } else if (details.primaryDelta! > 10 && isExpanded) {
            collapse();
          }
        },
        child: Material(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius!),
          elevation: lerpDouble(4, 0, t)!,
          shadowColor: Colors.black.withOpacity(0.3),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Album art - morphs from left to center
                Positioned(
                  left: artLeft,
                  top: artTop,
                  child: Container(
                    width: artSize,
                    height: artSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(artBorderRadius!),
                      boxShadow: t > 0.3
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3 * t),
                                blurRadius: 24 * t,
                                offset: Offset(0, 8 * t),
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(artBorderRadius),
                      child: imageUrl != null
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              cacheWidth: t > 0.5 ? 1024 : 128,
                              cacheHeight: t > 0.5 ? 1024 : 128,
                              errorBuilder: (_, __, ___) => _buildPlaceholderArt(colorScheme, t),
                            )
                          : _buildPlaceholderArt(colorScheme, t),
                    ),
                  ),
                ),

                // Track title - morphs from beside art to centered below
                Positioned(
                  left: titleLeft,
                  top: titleTop,
                  child: SizedBox(
                    width: titleWidth,
                    child: Text(
                      currentTrack.name,
                      style: TextStyle(
                        color: textColor,
                        fontSize: titleFontSize,
                        fontWeight: t > 0.5 ? FontWeight.bold : FontWeight.w500,
                      ),
                      textAlign: t > 0.5 ? TextAlign.center : TextAlign.left,
                      maxLines: t > 0.5 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

                // Artist name - morphs similarly
                Positioned(
                  left: titleLeft,
                  top: artistTop,
                  child: SizedBox(
                    width: titleWidth,
                    child: Text(
                      currentTrack.artistsString,
                      style: TextStyle(
                        color: textColor.withOpacity(0.7),
                        fontSize: artistFontSize,
                      ),
                      textAlign: t > 0.5 ? TextAlign.center : TextAlign.left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

                // Album name (only visible when expanded)
                if (currentTrack.album != null && t > 0.3)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: artistTop! + 28,
                    child: Opacity(
                      opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: Text(
                        currentTrack.album!.name,
                        style: TextStyle(
                          color: textColor.withOpacity(0.5),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Progress bar (fades in when expanded)
                if (t > 0.5 && currentTrack.duration != null)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: expandedArtistTop + 60,
                    child: Opacity(
                      opacity: expandedElementsOpacity,
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            ),
                            child: Slider(
                              value: (_seekPosition ?? selectedPlayer.currentElapsedTime)
                                  .clamp(0, currentTrack.duration!.inSeconds.toDouble()),
                              max: currentTrack.duration!.inSeconds.toDouble(),
                              onChanged: (value) => setState(() => _seekPosition = value),
                              onChangeStart: (value) => setState(() => _seekPosition = value),
                              onChangeEnd: (value) async {
                                try {
                                  await maProvider.seek(selectedPlayer.playerId, value.round());
                                  await Future.delayed(const Duration(milliseconds: 200));
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error seeking: $e')),
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _seekPosition = null);
                                }
                              },
                              activeColor: primaryColor,
                              inactiveColor: primaryColor.withOpacity(0.24),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration((_seekPosition ?? selectedPlayer.currentElapsedTime).toInt()),
                                  style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 12),
                                ),
                                Text(
                                  _formatDuration(currentTrack.duration!.inSeconds),
                                  style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Playback controls - morph from right side to centered
                // When collapsed: position from right
                // When expanded: center horizontally
                Positioned(
                  left: t > 0.5 ? 0 : null,
                  right: t > 0.5 ? 0 : controlsRight,
                  top: controlsTop,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: t > 0.5 ? MainAxisAlignment.center : MainAxisAlignment.end,
                    children: [
                      // Shuffle button (fades in when expanded)
                      if (t > 0.5)
                        Opacity(
                          opacity: expandedElementsOpacity,
                          child: IconButton(
                            icon: Icon(
                              Icons.shuffle,
                              color: _queue?.shuffle == true ? primaryColor : textColor.withOpacity(0.5),
                            ),
                            iconSize: 24,
                            onPressed: _isLoadingQueue ? null : _toggleShuffle,
                          ),
                        ),
                      if (t > 0.5) const SizedBox(width: 12),

                      // Previous button
                      _buildMorphingControlButton(
                        icon: Icons.skip_previous_rounded,
                        color: textColor,
                        size: skipButtonSize!,
                        onPressed: () => maProvider.previousTrackSelectedPlayer(),
                        useAnimation: t > 0.5,
                      ),
                      SizedBox(width: lerpDouble(0, 12, t)),

                      // Play/Pause button - morphs from simple to circular
                      _buildMorphingPlayButton(
                        isPlaying: selectedPlayer.isPlaying,
                        textColor: textColor,
                        primaryColor: primaryColor,
                        backgroundColor: backgroundColor,
                        size: playButtonSize!,
                        containerSize: playButtonContainerSize!,
                        progress: t,
                        onPressed: () => maProvider.playPauseSelectedPlayer(),
                        onLongPress: () => maProvider.stopPlayer(selectedPlayer.playerId),
                      ),
                      SizedBox(width: lerpDouble(0, 12, t)),

                      // Next button
                      _buildMorphingControlButton(
                        icon: Icons.skip_next_rounded,
                        color: textColor,
                        size: skipButtonSize,
                        onPressed: () => maProvider.nextTrackSelectedPlayer(),
                        useAnimation: t > 0.5,
                      ),

                      // Repeat button (fades in when expanded)
                      if (t > 0.5) const SizedBox(width: 12),
                      if (t > 0.5)
                        Opacity(
                          opacity: expandedElementsOpacity,
                          child: IconButton(
                            icon: Icon(
                              _queue?.repeatMode == 'one' ? Icons.repeat_one : Icons.repeat,
                              color: _queue?.repeatMode != null && _queue!.repeatMode != 'off'
                                  ? primaryColor
                                  : textColor.withOpacity(0.5),
                            ),
                            iconSize: 24,
                            onPressed: _isLoadingQueue ? null : _cycleRepeat,
                          ),
                        ),
                    ],
                  ),
                ),

                // Volume control (fades in when expanded)
                if (t > 0.5)
                  Positioned(
                    left: 40,
                    right: 40,
                    top: volumeTop,
                    child: Opacity(
                      opacity: expandedElementsOpacity,
                      child: const VolumeControl(compact: false),
                    ),
                  ),

                // Collapse button (fades in when expanded)
                if (t > 0.3)
                  Positioned(
                    top: topPadding + 8,
                    left: 8,
                    child: Opacity(
                      opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: IconButton(
                        icon: Icon(Icons.keyboard_arrow_down, color: textColor, size: 32),
                        onPressed: collapse,
                      ),
                    ),
                  ),

                // Queue button (fades in when expanded)
                if (t > 0.3)
                  Positioned(
                    top: topPadding + 8,
                    right: 8,
                    child: Opacity(
                      opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: IconButton(
                        icon: Icon(Icons.queue_music, color: textColor),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const QueueScreen()),
                          );
                        },
                      ),
                    ),
                  ),

                // Player name (fades in when expanded)
                if (t > 0.5)
                  Positioned(
                    top: topPadding + 16,
                    left: 0,
                    right: 0,
                    child: Opacity(
                      opacity: ((t - 0.5) / 0.5).clamp(0.0, 1.0),
                      child: Text(
                        selectedPlayer.name,
                        style: TextStyle(
                          color: textColor.withOpacity(0.7),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderArt(ColorScheme colorScheme, double t) {
    return Container(
      color: Color.lerp(colorScheme.surfaceVariant, const Color(0xFF2a2a2a), t),
      child: Icon(
        Icons.music_note_rounded,
        color: Color.lerp(colorScheme.onSurfaceVariant, Colors.white24, t),
        size: lerpDouble(24, 120, t),
      ),
    );
  }

  Widget _buildMorphingControlButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onPressed,
    required bool useAnimation,
  }) {
    if (useAnimation) {
      return AnimatedIconButton(
        icon: icon,
        color: color,
        iconSize: size,
        onPressed: onPressed,
      );
    }
    return IconButton(
      icon: Icon(icon),
      color: color,
      iconSize: size,
      onPressed: onPressed,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildMorphingPlayButton({
    required bool isPlaying,
    required Color textColor,
    required Color primaryColor,
    required Color backgroundColor,
    required double size,
    required double containerSize,
    required double progress,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
  }) {
    // Interpolate between no background (collapsed) and circular background (expanded)
    final bgColor = Color.lerp(Colors.transparent, primaryColor, progress);
    final iconColor = Color.lerp(textColor, backgroundColor, progress);

    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        width: containerSize,
        height: containerSize,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          color: iconColor,
          iconSize: size,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

double? lerpDouble(double a, double b, double t) {
  return a + (b - a) * t;
}
