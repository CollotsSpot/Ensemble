import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/timings.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';
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
  /// Slide offset for hiding the mini player (0.0 = visible, 1.0 = hidden below screen)
  final double slideOffset;

  const ExpandablePlayer({
    super.key,
    this.slideOffset = 0.0,
  });

  @override
  State<ExpandablePlayer> createState() => ExpandablePlayerState();
}

class ExpandablePlayerState extends State<ExpandablePlayer>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  // Queue panel slide animation
  late AnimationController _queuePanelController;
  late Animation<double> _queuePanelAnimation;

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
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Queue panel animation
    _queuePanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _queuePanelAnimation = CurvedAnimation(
      parent: _queuePanelController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.forward) {
        _loadQueue();
        _startProgressTimer();
      } else if (status == AnimationStatus.dismissed) {
        _progressTimer?.cancel();
        // Close queue panel when player collapses
        _queuePanelController.reverse();
      }
    });

    // Auto-refresh queue when panel is open
    _queuePanelController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _startQueueRefreshTimer();
      } else if (status == AnimationStatus.dismissed) {
        _stopQueueRefreshTimer();
      }
    });
  }

  Timer? _queueRefreshTimer;

  void _startQueueRefreshTimer() {
    _stopQueueRefreshTimer();
    // Refresh queue at configured interval when panel is open
    _queueRefreshTimer = Timer.periodic(Timings.playerPollingInterval, (_) {
      if (mounted && isQueuePanelOpen) {
        _loadQueue();
      }
    });
  }

  void _stopQueueRefreshTimer() {
    _queueRefreshTimer?.cancel();
    _queueRefreshTimer = null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _queuePanelController.dispose();
    _progressTimer?.cancel();
    _queueRefreshTimer?.cancel();
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
    // Use local player report interval for progress updates (1 second)
    _progressTimer = Timer.periodic(Timings.localPlayerReportInterval, (_) {
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

        // Share adaptive colors globally via ThemeProvider
        final themeProvider = context.read<ThemeProvider>();
        themeProvider.updateAdaptiveColors(colorSchemes.$1, colorSchemes.$2);
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

  void _toggleQueuePanel() {
    if (_queuePanelController.isAnimating) return;
    if (_queuePanelController.value == 0) {
      _queuePanelController.forward();
    } else {
      _queuePanelController.reverse();
    }
  }

  bool get isQueuePanelOpen => _queuePanelController.value > 0.5;

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
          animation: Listenable.merge([_expandAnimation, _queuePanelAnimation]),
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

    // Color transitions - mini player uses adaptive primaryContainer (darker tinted color)
    final collapsedBg = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.primaryContainer
        : colorScheme.primaryContainer;
    final expandedBg = adaptiveScheme?.surface ?? const Color(0xFF121212);
    final backgroundColor = Color.lerp(collapsedBg, expandedBg, t)!;

    final collapsedTextColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.onPrimaryContainer
        : colorScheme.onPrimaryContainer;
    final expandedTextColor = adaptiveScheme?.onSurface ?? Colors.white;
    final textColor = Color.lerp(collapsedTextColor, expandedTextColor, t)!;

    final primaryColor = adaptiveScheme?.primary ?? Colors.white;

    // Always position above bottom nav bar
    final bottomNavSpace = _bottomNavHeight + bottomPadding;
    final collapsedBottomOffset = bottomNavSpace + _collapsedMargin;
    final expandedBottomOffset = bottomNavSpace;
    final expandedHeight = screenSize.height - bottomNavSpace;

    // Apply slide offset to hide mini player (slides down off-screen)
    // Only apply when collapsed (t == 0), don't affect expanded state
    final slideDownAmount = widget.slideOffset * (_collapsedHeight + collapsedBottomOffset + 20);
    final slideAdjustedBottomOffset = t < 0.1
        ? collapsedBottomOffset - slideDownAmount
        : _lerpDouble(collapsedBottomOffset, expandedBottomOffset, t);

    final collapsedWidth = screenSize.width - (_collapsedMargin * 2);
    final width = _lerpDouble(collapsedWidth, screenSize.width, t);
    final height = _lerpDouble(_collapsedHeight, expandedHeight, t);
    final horizontalMargin = _lerpDouble(_collapsedMargin, 0, t);
    // Use slide-adjusted offset when collapsed, normal lerp otherwise
    final bottomOffset = slideAdjustedBottomOffset;
    final borderRadius = _lerpDouble(_collapsedBorderRadius, 0, t);

    // ===========================================
    // EXPANDED LAYOUT - Vertical rhythm based design
    // ===========================================
    // Using 8px grid for consistent spacing
    // Header: 48px (player name area)
    // Art: proportional to screen, centered
    // Track info: clear hierarchy with breathing room
    // Progress: slim, elegant
    // Controls: generously spaced
    // Volume: bottom anchored

    final headerHeight = 48.0;
    final contentPadding = 32.0; // horizontal padding for content

    // Art sizing - larger on bigger screens, max 85% of width
    final maxArtSize = screenSize.width - (contentPadding * 2);
    final expandedArtSize = (maxArtSize * 0.92).clamp(280.0, 400.0);
    final artSize = _lerpDouble(_collapsedArtSize, expandedArtSize, t);
    final artBorderRadius = _lerpDouble(0, 12, t); // Square in mini player, rounded when expanded

    // Art position
    final collapsedArtLeft = 0.0;
    final expandedArtLeft = (screenSize.width - expandedArtSize) / 2;
    final artLeft = _lerpDouble(collapsedArtLeft, expandedArtLeft, t);

    final collapsedArtTop = 0.0;
    final expandedArtTop = topPadding + headerHeight + 16;
    final artTop = _lerpDouble(collapsedArtTop, expandedArtTop, t);

    // Typography - clear hierarchy
    // Title: bold, prominent (24px)
    // Artist: medium weight, secondary (16px)
    // Album: light, tertiary (13px)
    final titleFontSize = _lerpDouble(16.0, 24.0, t);
    final artistFontSize = _lerpDouble(14.0, 16.0, t);

    final collapsedTitleLeft = _collapsedArtSize + 12;
    final expandedTitleLeft = contentPadding;
    final titleLeft = _lerpDouble(collapsedTitleLeft, expandedTitleLeft, t);

    final collapsedTitleTop = (_collapsedHeight - 32) / 2;
    final expandedTitleTop = expandedArtTop + expandedArtSize + 28;
    final titleTop = _lerpDouble(collapsedTitleTop, expandedTitleTop, t);

    final collapsedTitleWidth = screenSize.width - _collapsedArtSize - 150;
    final expandedTitleWidth = screenSize.width - (contentPadding * 2);
    final titleWidth = _lerpDouble(collapsedTitleWidth, expandedTitleWidth, t);

    // Measure actual title height for dynamic layout
    final titleStyle = TextStyle(
      fontSize: 24.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 1.2,
    );
    final titlePainter = TextPainter(
      text: TextSpan(text: currentTrack.name, style: titleStyle),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: expandedTitleWidth);
    final expandedTitleHeight = titlePainter.height;

    // Artist positioned dynamically based on actual title height
    final collapsedArtistTop = collapsedTitleTop + 18;
    final expandedArtistTop = expandedTitleTop + expandedTitleHeight + 8;
    final artistTop = _lerpDouble(collapsedArtistTop, expandedArtistTop, t);

    // Album - subtle, below artist
    final expandedAlbumTop = expandedArtistTop + 24;

    // Progress bar - with generous spacing
    final expandedProgressTop = expandedAlbumTop + 36;

    // Controls - main row with comfortable touch targets
    final collapsedControlsRight = 8.0;
    final collapsedControlsTop = (_collapsedHeight - 34) / 2 - 6;
    final expandedControlsTop = expandedProgressTop + 64;
    final controlsTop = _lerpDouble(collapsedControlsTop, expandedControlsTop, t);

    // Button sizes - larger in expanded for better touch targets
    final skipButtonSize = _lerpDouble(28, 36, t);
    final playButtonSize = _lerpDouble(34, 44, t);
    final playButtonContainerSize = _lerpDouble(34, 72, t);

    final expandedElementsOpacity = Curves.easeIn.transform((t - 0.5).clamp(0, 0.5) * 2);

    // Volume - anchored near bottom with breathing room
    final volumeTop = expandedControlsTop + 88;

    // Queue panel slide amount (0 = hidden, 1 = fully visible)
    final queueT = _queuePanelAnimation.value;

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      bottom: bottomOffset,
      child: GestureDetector(
        // Use translucent to allow child widgets (like buttons) to receive taps
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (!isExpanded) expand();
        },
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta! < -10 && !isExpanded) {
            expand();
          } else if (details.primaryDelta! > 10 && isExpanded && !isQueuePanelOpen) {
            collapse();
          }
        },
        onHorizontalDragEnd: isExpanded ? (details) {
          // Swipe left to open queue, swipe right to close
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < -300 && !isQueuePanelOpen) {
              _toggleQueuePanel();
            } else if (details.primaryVelocity! > 300 && isQueuePanelOpen) {
              _toggleQueuePanel();
            }
          }
        } : null,
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
                        fontWeight: t > 0.5 ? FontWeight.w600 : FontWeight.w500,
                        letterSpacing: t > 0.5 ? -0.5 : 0,
                        height: 1.2,
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
                        color: textColor.withOpacity(t > 0.5 ? 0.7 : 0.6),
                        fontSize: artistFontSize,
                        fontWeight: t > 0.5 ? FontWeight.w400 : FontWeight.normal,
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
                    left: contentPadding,
                    right: contentPadding,
                    top: _lerpDouble(artistTop + 24, expandedAlbumTop, t),
                    child: Opacity(
                      opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: Text(
                        currentTrack.album!.name,
                        style: TextStyle(
                          color: textColor.withOpacity(0.45),
                          fontSize: 13,
                          fontWeight: FontWeight.w300,
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
                    left: contentPadding,
                    right: contentPadding,
                    top: expandedProgressTop,
                    child: Opacity(
                      opacity: expandedElementsOpacity,
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                              trackShape: const RoundedRectSliderTrackShape(),
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
                              inactiveColor: primaryColor.withOpacity(0.2),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration((_seekPosition ?? selectedPlayer.currentElapsedTime).toInt()),
                                  style: TextStyle(
                                    color: textColor.withOpacity(0.5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text(
                                  _formatDuration(currentTrack.duration!.inSeconds),
                                  style: TextStyle(
                                    color: textColor.withOpacity(0.5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
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
                          child: _buildSecondaryButton(
                            icon: Icons.shuffle_rounded,
                            color: _queue?.shuffle == true ? primaryColor : textColor.withOpacity(0.5),
                            onPressed: _isLoadingQueue ? null : _toggleShuffle,
                          ),
                        ),
                      if (t > 0.5) SizedBox(width: _lerpDouble(0, 20, t)),

                      // Previous
                      _buildControlButton(
                        icon: Icons.skip_previous_rounded,
                        color: textColor,
                        size: skipButtonSize,
                        onPressed: () => maProvider.previousTrackSelectedPlayer(),
                        useAnimation: t > 0.5,
                      ),
                      SizedBox(width: _lerpDouble(0, 20, t)),

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
                      SizedBox(width: _lerpDouble(0, 20, t)),

                      // Next
                      _buildControlButton(
                        icon: Icons.skip_next_rounded,
                        color: textColor,
                        size: skipButtonSize,
                        onPressed: () => maProvider.nextTrackSelectedPlayer(),
                        useAnimation: t > 0.5,
                      ),

                      // Repeat (expanded only)
                      if (t > 0.5) SizedBox(width: _lerpDouble(0, 20, t)),
                      if (t > 0.5)
                        Opacity(
                          opacity: expandedElementsOpacity,
                          child: _buildSecondaryButton(
                            icon: _queue?.repeatMode == 'one' ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                            color: _queue?.repeatMode != null && _queue!.repeatMode != 'off'
                                ? primaryColor
                                : textColor.withOpacity(0.5),
                            onPressed: _isLoadingQueue ? null : _cycleRepeat,
                          ),
                        ),
                    ],
                  ),
                ),

                // Volume control (expanded only)
                if (t > 0.5)
                  Positioned(
                    left: 48,
                    right: 48,
                    top: volumeTop,
                    child: Opacity(
                      opacity: expandedElementsOpacity,
                      child: const VolumeControl(compact: false),
                    ),
                  ),

                // Collapse button (expanded only)
                if (t > 0.3)
                  Positioned(
                    top: topPadding + 4,
                    left: 4,
                    child: Opacity(
                      opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: IconButton(
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor, size: 28),
                        onPressed: collapse,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),

                // Queue button (expanded only) - hide when queue panel is open
                if (t > 0.3 && queueT < 0.5)
                  Positioned(
                    top: topPadding + 4,
                    right: 4,
                    child: Opacity(
                      opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0) * (1 - queueT * 2).clamp(0.0, 1.0),
                      child: IconButton(
                        icon: Icon(Icons.queue_music_rounded, color: textColor, size: 24),
                        onPressed: _toggleQueuePanel,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),

                // Player name (expanded only)
                if (t > 0.5)
                  Positioned(
                    top: topPadding + 12,
                    left: 56,
                    right: 56,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: ((t - 0.5) / 0.5).clamp(0.0, 1.0),
                        child: Text(
                          selectedPlayer.name,
                          style: TextStyle(
                            color: textColor.withOpacity(0.6),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),

                // Queue panel (slides in from right)
                if (t > 0.5 && queueT > 0)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(_queuePanelAnimation),
                        child: _buildQueuePanel(
                          maProvider,
                          selectedPlayer,
                          textColor,
                          primaryColor,
                          topPadding,
                          expandedBg,
                        ),
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

  Widget _buildQueuePanel(
    MusicAssistantProvider maProvider,
    dynamic selectedPlayer,
    Color textColor,
    Color primaryColor,
    double topPadding,
    Color backgroundColor,
  ) {
    return Container(
      color: backgroundColor,
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(top: topPadding + 4, left: 4, right: 16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 24),
                  onPressed: _toggleQueuePanel,
                  padding: const EdgeInsets.all(12),
                ),
                const Spacer(),
                Text(
                  'Queue',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.refresh_rounded, color: textColor.withOpacity(0.7), size: 22),
                  onPressed: _loadQueue,
                  padding: const EdgeInsets.all(12),
                ),
              ],
            ),
          ),

          // Queue content
          Expanded(
            child: _isLoadingQueue
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : _queue == null || _queue!.items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.queue_music, size: 64, color: textColor.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            Text(
                              'Queue is empty',
                              style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : _buildQueueList(maProvider, textColor, primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList(
    MusicAssistantProvider maProvider,
    Color textColor,
    Color primaryColor,
  ) {
    final currentIndex = _queue!.currentIndex ?? 0;
    final items = _queue!.items;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      cacheExtent: 500, // Pre-render items off-screen for smoother scrolling
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isCurrentItem = index == currentIndex;
        final isPastItem = index < currentIndex;
        final imageUrl = maProvider.api?.getImageUrl(item.track, size: 80);

        return Opacity(
          opacity: isPastItem ? 0.5 : 1.0,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: isCurrentItem ? primaryColor.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              dense: true,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: textColor.withOpacity(0.1),
                            child: Icon(Icons.music_note, color: textColor.withOpacity(0.3), size: 20),
                          ),
                        )
                      : Container(
                          color: textColor.withOpacity(0.1),
                          child: Icon(Icons.music_note, color: textColor.withOpacity(0.3), size: 20),
                        ),
                ),
              ),
              title: Text(
                item.track.name,
                style: TextStyle(
                  color: isCurrentItem ? primaryColor : textColor,
                  fontSize: 14,
                  fontWeight: isCurrentItem ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: item.track.artists != null && item.track.artists!.isNotEmpty
                  ? Text(
                      item.track.artists!.first.name,
                      style: TextStyle(
                        color: textColor.withOpacity(0.6),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: isCurrentItem
                  ? Icon(Icons.play_arrow_rounded, color: primaryColor, size: 20)
                  : null,
              onTap: () {
                // TODO: Jump to this track in queue
              },
            ),
          ),
        );
      },
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

  Widget _buildSecondaryButton({
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon),
        color: color,
        iconSize: 22,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
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
