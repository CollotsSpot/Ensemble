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
/// This widget is designed to be used as a global overlay, positioned above
/// the bottom navigation bar. It uses smooth morphing animations where each
/// element transitions from their mini to full positions.
class ExpandablePlayer extends StatefulWidget {
  const ExpandablePlayer({super.key});

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

  // Dimensions
  static const double _collapsedHeight = 64.0;
  static const double _collapsedMargin = 8.0;
  static const double _collapsedBorderRadius = 16.0;
  static const double _collapsedArtSize = 64.0;
  static const double _bottomNavHeight = 56.0;

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

    // Always position above bottom nav bar
    final bottomNavSpace = _bottomNavHeight + bottomPadding;
    final collapsedBottomOffset = bottomNavSpace + _collapsedMargin;
    // When expanded, stay just above the bottom nav
    final expandedBottomOffset = bottomNavSpace;
    // Height fills from bottom nav to top of screen
    final expandedHeight = screenSize.height - bottomNavSpace;

    final collapsedWidth = screenSize.width - (_collapsedMargin * 2);
    final width = _lerpDouble(collapsedWidth, screenSize.width, t);
    final height = _lerpDouble(_collapsedHeight, expandedHeight, t);
    final horizontalMargin = _lerpDouble(_collapsedMargin, 0, t);
    final bottomOffset = _lerpDouble(collapsedBottomOffset, expandedBottomOffset, t);
    final borderRadius = _lerpDouble(_collapsedBorderRadius, 0, t);

    // Calculate available space for expanded layout
    // Available height = expandedHeight - topPadding - header(60) - bottomPadding(20)
    final availableHeight = expandedHeight - topPadding - 80;

    // Distribute space: art(40%) + info(25%) + controls(20%) + volume(15%)
    final expandedArtSize = (screenSize.width * 0.70).clamp(200.0, 320.0);
    final artSize = _lerpDouble(_collapsedArtSize, expandedArtSize, t);
    final artBorderRadius = _lerpDouble(_collapsedBorderRadius, 16, t);

    // Art position - centered horizontally, positioned with good top margin
    final collapsedArtLeft = 0.0;
    final expandedArtLeft = (screenSize.width - expandedArtSize) / 2;
    final artLeft = _lerpDouble(collapsedArtLeft, expandedArtLeft, t);

    final collapsedArtTop = 0.0;
    // Position art with comfortable top spacing
    final expandedArtTop = topPadding + 56;
    final artTop = _lerpDouble(collapsedArtTop, expandedArtTop, t);

    // Track title morphing - account for 2-line titles (max ~60px height)
    final titleFontSize = _lerpDouble(14.0, 22.0, t);
    final collapsedTitleLeft = _collapsedArtSize + 12;
    final expandedTitleLeft = 24.0;
    final titleLeft = _lerpDouble(collapsedTitleLeft, expandedTitleLeft, t);

    final collapsedTitleTop = (_collapsedHeight - 32) / 2;
    // Space after art for title
    final expandedTitleTop = expandedArtTop + expandedArtSize + 24;
    final titleTop = _lerpDouble(collapsedTitleTop, expandedTitleTop, t);

    final collapsedTitleWidth = screenSize.width - _collapsedArtSize - 150;
    final expandedTitleWidth = screenSize.width - 48;
    final titleWidth = _lerpDouble(collapsedTitleWidth, expandedTitleWidth, t);

    // Artist name morphing - positioned after title with enough gap for 2-line title
    final artistFontSize = _lerpDouble(12.0, 15.0, t);
    final collapsedArtistTop = collapsedTitleTop + 18;
    // Add 56px gap to account for potential 2-line title (22px * 2 + padding)
    final expandedArtistTop = expandedTitleTop + 56;
    final artistTop = _lerpDouble(collapsedArtistTop, expandedArtistTop, t);

    // Album name position (only shown expanded)
    final expandedAlbumTop = expandedArtistTop + 24;

    // Progress bar position
    final expandedProgressTop = expandedAlbumTop + 32;

    // Controls - positioned after progress bar
    final collapsedControlsRight = 8.0;
    final collapsedControlsTop = (_collapsedHeight - 34) / 2 - 6;
    final expandedControlsTop = expandedProgressTop + 56;
    final controlsTop = _lerpDouble(collapsedControlsTop, expandedControlsTop, t);

    final skipButtonSize = _lerpDouble(28, 40, t);
    final playButtonSize = _lerpDouble(34, 40, t);
    final playButtonContainerSize = _lerpDouble(34, 68, t);

    final expandedElementsOpacity = Curves.easeIn.transform((t - 0.5).clamp(0, 0.5) * 2);

    // Volume control - at the bottom with more spacing from controls
    final volumeTop = expandedControlsTop + 100;

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
          borderRadius: BorderRadius.circular(borderRadius),
          elevation: _lerpDouble(4, 0, t),
          shadowColor: Colors.black.withOpacity(0.3),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Album art
                Positioned(
                  left: artLeft,
                  top: artTop,
                  child: Container(
                    width: artSize,
                    height: artSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(artBorderRadius),
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

                // Track title
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

                // Artist name
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

                // Album name (expanded only)
                if (currentTrack.album != null && t > 0.3)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: _lerpDouble(artistTop + 24, expandedAlbumTop, t),
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

                // Progress bar (expanded only)
                if (t > 0.5 && currentTrack.duration != null)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: expandedProgressTop,
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

                // Playback controls
                Positioned(
                  left: t > 0.5 ? 0 : null,
                  right: t > 0.5 ? 0 : collapsedControlsRight,
                  top: controlsTop,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: t > 0.5 ? MainAxisAlignment.center : MainAxisAlignment.end,
                    children: [
                      // Shuffle (expanded only)
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

                      // Previous
                      _buildControlButton(
                        icon: Icons.skip_previous_rounded,
                        color: textColor,
                        size: skipButtonSize,
                        onPressed: () => maProvider.previousTrackSelectedPlayer(),
                        useAnimation: t > 0.5,
                      ),
                      SizedBox(width: _lerpDouble(0, 12, t)),

                      // Play/Pause
                      _buildPlayButton(
                        isPlaying: selectedPlayer.isPlaying,
                        textColor: textColor,
                        primaryColor: primaryColor,
                        backgroundColor: backgroundColor,
                        size: playButtonSize,
                        containerSize: playButtonContainerSize,
                        progress: t,
                        onPressed: () => maProvider.playPauseSelectedPlayer(),
                        onLongPress: () => maProvider.stopPlayer(selectedPlayer.playerId),
                      ),
                      SizedBox(width: _lerpDouble(0, 12, t)),

                      // Next
                      _buildControlButton(
                        icon: Icons.skip_next_rounded,
                        color: textColor,
                        size: skipButtonSize,
                        onPressed: () => maProvider.nextTrackSelectedPlayer(),
                        useAnimation: t > 0.5,
                      ),

                      // Repeat (expanded only)
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

                // Volume control (expanded only)
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

                // Collapse button (expanded only)
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

                // Queue button (expanded only)
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

                // Player name (expanded only)
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
        size: _lerpDouble(24, 120, t),
      ),
    );
  }

  Widget _buildControlButton({
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

  Widget _buildPlayButton({
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

  double _lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
