import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/timings.dart';
import '../utils/duration_formatter.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/navigation_provider.dart';
import '../models/player.dart';
import '../models/media_item.dart';
import '../services/animation_debugger.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../l10n/app_localizations.dart';
import '../services/settings_service.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import '../screens/artist_details_screen.dart';
import '../screens/album_details_screen.dart';
import '../utils/page_transitions.dart';
import 'animated_icon_button.dart';
import 'global_player_overlay.dart';
import 'provider_icon.dart';
import 'volume_control.dart';
import 'player/player_widgets.dart';
import 'player/mini_player_content.dart';

/// A unified player widget that seamlessly expands from mini to full-screen.
///
/// This widget is designed to be used as a global overlay, positioned above
/// the bottom navigation bar. It uses smooth morphing animations where each
/// element transitions from their mini to full positions.
class ExpandablePlayer extends StatefulWidget {
  /// Slide offset for hiding the mini player (0.0 = visible, 1.0 = hidden below screen)
  final double slideOffset;

  /// Bounce offset for the player reveal animation (moves mini player down slightly)
  final double bounceOffset;

  /// Callback when swipe-down gesture triggers player reveal
  final VoidCallback? onRevealPlayers;

  /// Whether the device reveal overlay is currently visible
  /// When true, shows player name instead of track name in collapsed state
  final bool isDeviceRevealVisible;

  /// Whether the hint text should be shown
  /// When true, shows "Pull to select players" instead of track info
  final bool isHintVisible;

  const ExpandablePlayer({
    super.key,
    this.slideOffset = 0.0,
    this.bounceOffset = 0.0,
    this.onRevealPlayers,
    this.isDeviceRevealVisible = false,
    this.isHintVisible = false,
  });

  @override
  State<ExpandablePlayer> createState() => ExpandablePlayerState();
}

class ExpandablePlayerState extends State<ExpandablePlayer>
    with TickerProviderStateMixin {
  final DebugLogger _logger = DebugLogger();

  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  // Queue panel slide animation
  late AnimationController _queuePanelController;
  late Animation<double> _queuePanelAnimation;
  // Cached slide position animation (avoids recreating Tween.animate every frame)
  late Animation<Offset> _queueSlideAnimation;

  // Adaptive theme colors extracted from album art
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  String? _lastImageUrl;

  // Queue state
  PlayerQueue? _queue;
  String? _queuePlayerId; // Track which player the queue belongs to
  bool _isLoadingQueue = false;
  bool _isQueueDragging = false; // True while queue item is being dragged
  bool _queuePanelTargetOpen = false; // Target state for queue panel (separate from animation value)

  // Sleep timer panel animation
  late AnimationController _sleepTimerPanelController;
  late Animation<Offset> _sleepTimerSlideAnimation;
  bool _sleepTimerPanelVisible = false; // Track visibility state explicitly
  bool _sleepTimerPanelTargetOpen = false; // Target state for back gesture handling
  bool _isClosingSleepTimerPanel = false; // Guard against double back gesture

  // Lyrics panel animation
  late AnimationController _lyricsPanelController;
  late Animation<Offset> _lyricsSlideAnimation;
  bool _lyricsPanelVisible = false;
  bool _lyricsPanelTargetOpen = false; // Target state for back gesture handling
  bool _isClosingLyricsPanel = false; // Guard against double back gesture
  String? _currentLyrics; // Cached lyrics for current track
  bool _isLoadingLyrics = false;
  String? _lyricsTrackId; // Track ID for which lyrics were fetched
  List<_LyricLine>? _parsedLyrics; // Parsed synced lyrics with timestamps
  int _currentLyricIndex = -1; // Currently active lyric line
  final ScrollController _lyricsScrollController = ScrollController();
  StreamSubscription<Duration>? _lyricsPositionSubscription;
  bool _userScrollingLyrics = false; // True when user is manually scrolling
  bool _isLyricsAtTop = true; // Track scroll position for swipe-to-close
  bool _wasLyricsAtTopOnSwipeStart = true; // Capture scroll position when swipe starts
  Offset? _lyricsSwipeStart; // Starting position of swipe gesture
  bool _isSwipingLyricsContent = false; // True during active swipe-to-close gesture

  // Progress tracking - uses PositionTracker stream as single source of truth
  StreamSubscription<Duration>? _positionSubscription;
  // Queue items subscription - refreshes queue when MA pushes updates (e.g., radio mode adds tracks)
  StreamSubscription<Map<String, dynamic>>? _queueItemsSubscription;
  final ValueNotifier<int> _progressNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double?> _seekPositionNotifier = ValueNotifier<double?>(null);
  bool _isSeeking = false; // Debounce flag to prevent rapid-fire seeks

  // Pre-computed static colors to avoid object creation during animation frames
  static const Color _shadowColor = Color(0x4D000000); // Colors.black.withOpacity(0.3)

  // PERF Phase 1: Cached SliderThemeData - created once, reused every frame
  static const SliderThemeData _sliderTheme = SliderThemeData(
    trackHeight: 4,
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
    overlayShape: RoundSliderOverlayShape(overlayRadius: 20),
    trackShape: RoundedRectSliderTrackShape(),
  );

  // Dimensions
  static double get _collapsedHeight => MiniPlayerLayout.height;
  static const double _collapsedMargin = 12.0; // Increased from 8 to 12 (4px more gap above nav bar)
  static const double _collapsedBorderRadius = 16.0;
  static double get _collapsedArtSize => MiniPlayerLayout.artSize;
  static const double _bottomNavHeight = 56.0;
  static const double _edgeDeadZone = 40.0; // Dead zone for Android back gesture

  // Pastel yellow for grouped players (matches PlayerCard.groupBorderColor)
  static const Color _groupBorderColor = Color(0xFFFFF59D);

  // Track horizontal drag start position
  double? _horizontalDragStartX;

  // Track vertical drag start position (for bottom dead zone - Android app switcher)
  double? _verticalDragStartY;
  static const _bottomDeadZone = 80.0; // Dead zone for Android nav gestures

  // Slide animation for device switching - now supports finger-following
  late AnimationController _slideController;
  // ValueNotifier avoids setState during high-frequency drag updates
  final ValueNotifier<double> _slideOffsetNotifier = ValueNotifier(0.0);
  double get _slideOffset => _slideOffsetNotifier.value;
  set _slideOffset(double value) => _slideOffsetNotifier.value = value;
  bool _isSliding = false;
  bool _isDragging = false; // True while finger is actively dragging

  // For peek preview - track which player we'd switch to
  dynamic _peekPlayer; // The player that would be selected if swipe commits
  String? _peekImageUrl; // Image URL for peek player's current track

  // Flag to indicate we're in the middle of a player switch transition
  // When true, we hide main content and show peek content at center
  bool _inTransition = false;

  // Volume swipe state (only active when device reveal is visible)
  bool _isDraggingVolume = false;
  double _dragVolumeLevel = 0.0;
  int _lastVolumeUpdateTime = 0;
  int _lastVolumeDragEndTime = 0; // Track when last drag ended for consecutive swipes
  bool _hasLocalVolumeOverride = false; // True if we've set volume locally
  static const int _volumeThrottleMs = 150; // Only send volume updates every 150ms
  static const int _precisionThrottleMs = 50; // Faster updates in precision mode
  static const int _consecutiveSwipeWindowMs = 5000; // 5 seconds - extended window for consecutive swipes

  // Volume precision mode state
  bool _inVolumePrecisionMode = false;
  Timer? _volumePrecisionTimer;
  Offset? _lastVolumeDragPosition;
  double _lastVolumeLocalX = 0.0; // Last local X position during drag
  bool _volumePrecisionModeEnabled = true; // From settings
  double _volumePrecisionZoomCenter = 0.0; // Volume level when precision mode started
  double _volumePrecisionStartX = 0.0; // Finger X position when precision mode started
  static const int _precisionTriggerMs = 800; // Hold still for 800ms to enter precision mode
  static const double _precisionStillnessThreshold = 5.0; // Max pixels of movement considered "still"
  static const double _precisionSensitivity = 0.1; // Zoomed range (10% = left edge to right edge)

  // Track favorite state for current track
  bool _isCurrentTrackFavorite = false;
  String? _lastTrackUri; // Track which track we last checked favorite status for

  // Track active ImageStream listeners for proper cleanup on dispose
  final Map<ImageStream, ImageStreamListener> _activeImageStreams = {};

  // Cached title height to avoid TextPainter.layout() every animation frame
  // Only invalidate when track name changes (screen width doesn't change during animation)
  double? _cachedExpandedTitleHeight;
  String? _lastMeasuredTrackName;

  // PERF: Cached MaterialRectCenterArcTween for art animation
  // Recreated only when screen dimensions change, not every frame
  MaterialRectCenterArcTween? _artRectTween;
  Size? _lastScreenSize;
  double? _lastTopPadding;

  // PERF: Pre-cached BoxShadow objects to avoid allocation per frame
  static const BoxShadow _miniPlayerShadow = BoxShadow(
    color: Color(0x4D000000), // 30% black
    blurRadius: 8,
    offset: Offset(0, 2),
  );
  static const BoxShadow _artShadowExpanded = BoxShadow(
    color: Color(0x40000000), // 25% black
    blurRadius: 20,
    offset: Offset(0, 8),
  );

  // PERF Phase 5: Cached fade animations - created once, reused every frame
  // These replace inline .drive(Tween().chain(CurveTween())) which created new objects per frame
  late Animation<double> _fadeIn50to100;  // Fades in during second half of animation

  // Gesture-driven expansion state
  bool _isVerticalDragging = false;
  double _dragStartY = 0;
  double _dragStartValue = 0;

  // Maximum drag distance for full expand/collapse
  static const double _maxDragDistance = 300.0;

  // Thresholds for committing expand/collapse
  static const double _commitPositionThreshold = 0.3; // 30% progress
  static const double _commitVelocityThreshold = 800.0; // px/s

  @override
  void initState() {
    super.initState();

    // Reset expansion notifier to match initial controller state (0.0)
    // This fixes a bug where stale progress values from a previous widget instance
    // caused the nav bar to be invisible on app restart/widget recreation
    playerExpansionNotifier.value = PlayerExpansionState(0.0, null, null);

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Simple curved animation - performant and smooth
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // PERF Phase 5: Cache fade animation - avoids creating Tween/CurveTween objects every frame
    // Used for elements that fade in during second half of expansion (t=0.5 to t=1.0)
    _fadeIn50to100 = _expandAnimation.drive(
      Tween<double>(begin: 0.0, end: 1.0).chain(
        CurveTween(curve: const Interval(0.5, 1.0, curve: Curves.easeIn)),
      ),
    );

    // Notify listeners of expansion progress changes
    _controller.addListener(_notifyExpansionProgress);

    // Animation debugging - record every frame
    _controller.addListener(_recordAnimationFrame);

    // Queue panel animation - uses spring physics directly (no CurvedAnimation)
    // Spring simulation already provides natural physics-based easing
    // CurvedAnimation would distort the spring output and cause jerky motion during swipe
    _queuePanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    // Use controller directly - spring physics provide the easing
    _queuePanelAnimation = _queuePanelController;
    // Cache the slide animation to avoid recreating Tween.animate() every frame
    // Queue slides up from bottom (0, 1) instead of from right (1, 0)
    _queueSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(_queuePanelController);

    // Sleep timer panel animation - uses same spring physics as queue panel
    _sleepTimerPanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    // Ensure value is exactly 0 when dismissed (spring may not settle exactly)
    _sleepTimerPanelController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _sleepTimerPanelController.value != 0) {
        _sleepTimerPanelController.value = 0;
      }
    });
    // Use controller directly - spring physics provide the easing (same as queue)
    _sleepTimerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(_sleepTimerPanelController);

    // Lyrics panel animation - same mechanics as sleep timer and queue
    _lyricsPanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _lyricsSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(_lyricsPanelController);

    // Track lyrics scroll position for swipe-to-close (only allowed at top)
    _lyricsScrollController.addListener(_onLyricsScroll);

    // Slide animation for device switching - used for snap/spring animations
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _controller.addStatusListener((status) {
      // PERF: Load queue after animation completes, not during
      // This prevents network I/O from competing with animation frames
      if (status == AnimationStatus.completed) {
        _loadQueue();
      } else if (status == AnimationStatus.dismissed) {
        // Close queue panel when player collapses
        _queuePanelController.duration = _queueCloseDuration;
        _queuePanelController.reverse();
      }
    });

    // Subscribe to position tracker stream - single source of truth for playback position
    _subscribeToPositionTracker();

    // Subscribe to queue_items_updated events from Music Assistant
    // This keeps queue in sync when MA pushes changes (e.g., radio mode adds tracks)
    _subscribeToQueueEvents();

    // Auto-refresh queue when panel is open
    _queuePanelController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _startQueueRefreshTimer();
      } else if (status == AnimationStatus.dismissed) {
        _stopQueueRefreshTimer();
      }
    });

    // Load precision mode setting
    _loadVolumePrecisionModeSetting();
  }

  Future<void> _loadVolumePrecisionModeSetting() async {
    final enabled = await SettingsService.getVolumePrecisionMode();
    if (mounted) {
      _volumePrecisionModeEnabled = enabled;
    }
  }

  @override
  void didUpdateWidget(ExpandablePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload precision mode setting when device reveal becomes visible
    // This ensures the setting is fresh after the user may have changed it
    if (widget.isDeviceRevealVisible && !oldWidget.isDeviceRevealVisible) {
      _loadVolumePrecisionModeSetting();
    }
  }

  void _enterVolumePrecisionMode() {
    if (_inVolumePrecisionMode) return;
    HapticFeedback.mediumImpact(); // Vibrate to indicate precision mode
    setState(() {
      _inVolumePrecisionMode = true;
      _volumePrecisionZoomCenter = _dragVolumeLevel; // Capture current volume as zoom center
      _volumePrecisionStartX = _lastVolumeLocalX; // Capture finger position at entry
    });
  }

  void _exitVolumePrecisionMode() {
    _volumePrecisionTimer?.cancel();
    _volumePrecisionTimer = null;
    if (!_inVolumePrecisionMode) return;
    setState(() {
      _inVolumePrecisionMode = false;
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
    // Explicitly remove listeners before disposing controllers
    // (Controllers remove listeners on dispose, but explicit removal is clearer)
    _controller.removeListener(_notifyExpansionProgress);
    _controller.removeListener(_recordAnimationFrame);
    _lyricsScrollController.removeListener(_onLyricsScroll);

    _controller.dispose();
    _queuePanelController.dispose();
    _sleepTimerPanelController.dispose();
    _lyricsPanelController.dispose();
    _slideController.dispose();
    _slideOffsetNotifier.dispose();
    _positionSubscription?.cancel();
    _queueItemsSubscription?.cancel();
    _lyricsPositionSubscription?.cancel();
    _lyricsScrollController.dispose();
    _queueRefreshTimer?.cancel();
    _volumePrecisionTimer?.cancel();
    _progressNotifier.dispose();
    _seekPositionNotifier.dispose();
    // Clean up any active ImageStream listeners to prevent memory leaks
    for (final entry in _activeImageStreams.entries) {
      entry.key.removeListener(entry.value);
    }
    _activeImageStreams.clear();
    super.dispose();
  }

  void _recordAnimationFrame() {
    AnimationDebugger.recordFrame(_controller.value);
  }

  // Animation durations - asymmetric for snappier collapse
  static const Duration _expandDuration = Duration(milliseconds: 280);
  static const Duration _collapseDuration = Duration(milliseconds: 200);
  static const Duration _queueOpenDuration = Duration(milliseconds: 320);
  static const Duration _queueCloseDuration = Duration(milliseconds: 220);

  // Spring description for queue panel animations
  // Higher damping ratio prevents oscillation and ensures clean settling
  // Critical damping = 2 * sqrt(stiffness * mass) = 2 * sqrt(550) ≈ 47
  // Using damping slightly above critical for overdamped (no bounce) behavior
  // PERF: Increased stiffness from 400→550 for snappier animation
  static const SpringDescription _queueSpring = SpringDescription(
    mass: 1.0,
    stiffness: 550.0,
    damping: 50.0, // Overdamped - no oscillation, clean settle
  );

  void expand() {
    if (_isVerticalDragging) return;
    HapticFeedback.lightImpact();
    AnimationDebugger.startSession('playerExpand');
    _controller.duration = _expandDuration;
    _controller.forward().then((_) {
      AnimationDebugger.endSession();
    });
  }

  void collapse({bool withHaptic = true}) {
    _logger.log('🔙 collapse() called with withHaptic=$withHaptic');
    if (_isVerticalDragging) return;
    // If any panel is still animating closed, don't collapse yet
    // This prevents double back gesture from closing both panel and player
    // Uses animation value (not boolean flag) because animation lags behind flag
    // Note: withHaptic: false prevents double haptic when back gesture is used rapidly
    if (_lyricsPanelController.value > 0.1) {
      _closeLyricsPanel(withHaptic: false);
      return;
    }
    if (_sleepTimerPanelController.value > 0.1) {
      _closeSleepTimerPanel(withHaptic: false);
      return;
    }
    if (isQueuePanelOpen) {
      closeQueuePanel(withHaptic: false);
      return;
    }
    if (withHaptic) {
      _logger.log('🔙 collapse() triggering haptic');
      HapticFeedback.lightImpact();
    }
    AnimationDebugger.startSession('playerCollapse');
    // Instantly hide queue panel when collapsing to avoid visual glitches
    // during Android's predictive back gesture (only reached if queue already closed)
    _queuePanelController.value = 0;
    _queuePanelTargetOpen = false;
    _controller.duration = _collapseDuration;
    _controller.reverse().then((_) {
      AnimationDebugger.endSession();
      // Ensure notifier is reset even if animation was already at 0
      // This fixes a bug where stale notifier values cause invisible nav bar
      if (playerExpansionNotifier.value.progress != 0.0) {
        playerExpansionNotifier.value = PlayerExpansionState(0.0, null, null);
      }
    });
  }

  /// Force collapse player to mini state, instantly closing queue panel if open.
  /// Used for queue transfer where we want to go directly to mini player.
  void forceCollapse() {
    if (_isVerticalDragging) return;
    // Instantly close queue panel without animation
    _queuePanelController.value = 0;
    _queuePanelTargetOpen = false;
    // Collapse player
    _controller.duration = _collapseDuration;
    _controller.reverse().then((_) {
      // Ensure notifier is reset even if animation was already at 0
      if (playerExpansionNotifier.value.progress != 0.0) {
        playerExpansionNotifier.value = PlayerExpansionState(0.0, null, null);
      }
    });
  }

  /// Handle vertical drag start - begin gesture-driven expansion
  void _handleVerticalDragStart(DragStartDetails details) {
    _isVerticalDragging = true;
    _dragStartY = details.globalPosition.dy;
    _dragStartValue = _controller.value;
    _controller.stop(); // Stop any running animation
  }

  /// Handle vertical drag update - finger tracking
  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isVerticalDragging) return;

    final dragDelta = _dragStartY - details.globalPosition.dy;
    // Swipe up = positive delta = expand (increase value)
    // Swipe down = negative delta = collapse (decrease value)
    final normalizedDelta = dragDelta / _maxDragDistance;
    final newValue = (_dragStartValue + normalizedDelta).clamp(0.0, 1.0);

    _controller.value = newValue;
  }

  /// Handle vertical drag end - decide to commit or snap back
  void _handleVerticalDragEnd(DragEndDetails details) {
    if (!_isVerticalDragging) return;
    _isVerticalDragging = false;

    final velocity = details.primaryVelocity ?? 0;
    final currentValue = _controller.value;

    // Determine direction based on velocity first, then position
    bool shouldExpand;
    if (velocity.abs() > _commitVelocityThreshold) {
      // High velocity: use velocity direction (negative = swipe up = expand)
      shouldExpand = velocity < 0;
    } else if (currentValue > _commitPositionThreshold && currentValue < (1 - _commitPositionThreshold)) {
      // In the middle zone: use velocity direction if any, otherwise snap to nearest
      shouldExpand = velocity < 0 || (velocity == 0 && currentValue > 0.5);
    } else {
      // Near edges: commit to nearest endpoint
      shouldExpand = currentValue > 0.5;
    }

    // Animate to target with appropriate duration
    if (shouldExpand) {
      if (currentValue < 1.0) {
        HapticFeedback.lightImpact();
        AnimationDebugger.startSession('playerExpand');
        _controller.duration = _expandDuration;
        _controller.forward().then((_) {
          AnimationDebugger.endSession();
        });
      }
    } else {
      if (currentValue > 0.0) {
        HapticFeedback.lightImpact();
        AnimationDebugger.startSession('playerCollapse');
        _queuePanelController.value = 0;
        _queuePanelTargetOpen = false;
        // Close sleep timer panel when collapsing
        if (_sleepTimerPanelVisible) {
          _sleepTimerPanelVisible = false;
          _sleepTimerPanelTargetOpen = false;
          _sleepTimerPanelController.value = 0;
        }
        // Close lyrics panel when collapsing
        if (_lyricsPanelVisible) {
          _stopLyricsSync();
          _lyricsPanelVisible = false;
          _lyricsPanelTargetOpen = false;
          _lyricsPanelController.value = 0;
        }
        _controller.duration = _collapseDuration;
        _controller.reverse().then((_) {
          AnimationDebugger.endSession();
        });
      }
    }
  }

  bool get isExpanded => _controller.value > 0.5;

  double get expansionProgress => _controller.value;

  Color? _currentExpandedBgColor;
  Color? get currentExpandedBgColor => _currentExpandedBgColor;
  Color? _currentExpandedPrimaryColor;

  // PERF Phase 4: Track last notified value to avoid unnecessary object creation
  double _lastNotifiedProgress = -1;

  void _notifyExpansionProgress() {
    final progress = _controller.value;
    // PERF Phase 4: Only notify when progress changes by at least 0.01 (1%)
    // This reduces object allocation while maintaining smooth visual transitions
    if ((progress - _lastNotifiedProgress).abs() >= 0.01 ||
        progress == 0.0 || progress == 1.0) {
      _lastNotifiedProgress = progress;
      playerExpansionNotifier.value = PlayerExpansionState(
        progress,
        _currentExpandedBgColor,
        _currentExpandedPrimaryColor,
      );
    }
  }

  void _subscribeToPositionTracker() {
    _logger.log('📊 _subscribeToPositionTracker called, existing subscription=${_positionSubscription != null}');
    _positionSubscription?.cancel();
    // Subscribe to position tracker stream - single source of truth
    // This eliminates race conditions between multiple timers
    final maProvider = context.read<MusicAssistantProvider>();
    _logger.log('📊 Subscribing to positionStream for progress bar');
    _positionSubscription = maProvider.positionTracker.positionStream.listen((position) {
      if (!mounted) return;
      _logger.log('📊 Progress received position: ${position.inSeconds}s');
      _progressNotifier.value = position.inSeconds;
    });
  }

  void _subscribeToQueueEvents() {
    _queueItemsSubscription?.cancel();
    final maProvider = context.read<MusicAssistantProvider>();
    final api = maProvider.api;
    if (api == null) return;

    // Subscribe to queue_items_updated events from Music Assistant
    // This keeps queue UI in sync when MA adds/removes items (e.g., radio mode)
    _queueItemsSubscription = api.queueItemsUpdatedEvents.listen((event) {
      if (!mounted) return;
      final playerId = event['queue_id'] as String?;
      final selectedPlayer = maProvider.selectedPlayer;
      // Only refresh if the event is for our current player
      if (playerId != null && selectedPlayer != null && playerId == selectedPlayer.playerId) {
        _loadQueue();
      }
    });
  }

  Future<void> _loadQueue() async {
    if (_isLoadingQueue) return;

    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      if (mounted) setState(() => _isLoadingQueue = false);
      return;
    }

    // Clear queue if player changed (e.g., after queue transfer)
    if (_queuePlayerId != null && _queuePlayerId != player.playerId) {
      _queue = null;
      _queuePlayerId = player.playerId;
    }

    // 1. Show cached queue immediately (if available)
    // Only load from cache if we don't already have a queue (preserves optimistic updates)
    if (_queue == null) {
      _queuePlayerId = player.playerId;
      final cachedQueue = await maProvider.getCachedQueue(player.playerId);
      if (cachedQueue != null && cachedQueue.items.isNotEmpty && mounted) {
        setState(() {
          _queue = cachedQueue;
          _isLoadingQueue = false;
        });
      } else {
        setState(() => _isLoadingQueue = true);
      }
    }

    // 2. Fetch fresh queue in background
    if (maProvider.api != null) {
      try {
        final freshQueue = await maProvider.getQueue(player.playerId);
        if (mounted && freshQueue != null) {
          // Check if queue items were reordered by comparing first few item IDs
          bool itemsReordered = false;
          if (_queue != null && _queue!.items.isNotEmpty && freshQueue.items.isNotEmpty) {
            // Compare first 3 items to detect reordering (shuffle changes item order)
            final maxCheck = (_queue!.items.length < 3 ? _queue!.items.length : 3).clamp(1, freshQueue.items.length);
            for (int i = 0; i < maxCheck; i++) {
              if (_queue!.items[i].queueItemId != freshQueue.items[i].queueItemId) {
                itemsReordered = true;
                break;
              }
            }
          }
          // Update if queue metadata or item order changed
          final queueChanged = _queue == null ||
              _queue!.items.length != freshQueue.items.length ||
              _queue!.currentIndex != freshQueue.currentIndex ||
              _queue!.shuffle != freshQueue.shuffle ||
              itemsReordered;
          if (queueChanged) {
            setState(() {
              _queue = freshQueue;
              _queuePlayerId = player.playerId;
              _isLoadingQueue = false;
            });
          }
        }
      } catch (e) {
        // Silent failure - keep showing cached queue
      }
    }

    if (mounted && _isLoadingQueue) {
      setState(() => _isLoadingQueue = false);
    }
  }

  Future<void> _extractColors(String imageUrl) async {
    if (_lastImageUrl == imageUrl) return;
    _lastImageUrl = imageUrl;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        CachedNetworkImageProvider(imageUrl),
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
      // Silently ignore color extraction errors
    }
  }

  Future<void> _toggleShuffle() async {
    if (_queue == null) return;
    final newShuffleState = !_queue!.shuffle;

    // Optimistically update local state for immediate visual feedback
    setState(() {
      _queue = PlayerQueue(
        playerId: _queue!.playerId,
        items: _queue!.items,
        currentIndex: _queue!.currentIndex,
        shuffleEnabled: newShuffleState,
        repeatMode: _queue!.repeatMode,
      );
    });

    final maProvider = context.read<MusicAssistantProvider>();
    // Toggle: if currently shuffled, disable; if not shuffled, enable
    await maProvider.toggleShuffle(_queue!.playerId, newShuffleState);
    // Small delay to allow server to finish reordering queue items
    await Future.delayed(const Duration(milliseconds: 150));
    await _loadQueue();
  }

  Future<void> _cycleRepeat() async {
    if (_queue == null) return;

    // Calculate next repeat mode: off -> all -> one -> off
    String nextMode;
    switch (_queue!.repeatMode) {
      case 'off':
      case null:
        nextMode = 'all';
        break;
      case 'all':
        nextMode = 'one';
        break;
      case 'one':
        nextMode = 'off';
        break;
      default:
        nextMode = 'off';
    }

    // Optimistically update local state for immediate visual feedback
    setState(() {
      _queue = PlayerQueue(
        playerId: _queue!.playerId,
        items: _queue!.items,
        currentIndex: _queue!.currentIndex,
        shuffleEnabled: _queue!.shuffleEnabled,
        repeatMode: nextMode,
      );
    });

    final maProvider = context.read<MusicAssistantProvider>();
    await maProvider.setRepeatMode(_queue!.playerId, nextMode);
    await _loadQueue();
  }

  void _toggleQueuePanel() {
    if (_queuePanelController.isAnimating) return;
    // Use threshold check instead of exact equality (spring may not land exactly at 0/1)
    if (_queuePanelController.value < 0.1) {
      _openQueuePanelWithSpring();
    } else {
      _closeQueuePanelWithSpring();
    }
  }

  /// Open queue panel with spring physics for natural feel
  void _openQueuePanelWithSpring() {
    HapticFeedback.lightImpact();
    // Close sleep timer panel instantly if open
    if (_sleepTimerPanelVisible) {
      _sleepTimerPanelVisible = false;
      _sleepTimerPanelTargetOpen = false;
      _sleepTimerPanelController.value = 0;
    }
    // Close lyrics panel instantly if open
    if (_lyricsPanelVisible) {
      _stopLyricsSync();
      _lyricsPanelVisible = false;
      _lyricsPanelTargetOpen = false;
      _lyricsPanelController.value = 0;
    }
    // setState ensures PopScope rebuilds with correct canPop value
    setState(() {
      _queuePanelTargetOpen = true;
    });
    // Use overdamped spring - settles cleanly without oscillation or snap
    final simulation = SpringSimulation(
      _queueSpring,
      _queuePanelController.value,
      1.0,
      0.0, // velocity
    );
    _queuePanelController.animateWith(simulation);
  }

  /// Close queue panel with spring physics
  /// [withHaptic]: Set to false for Android back gesture (system provides haptic)
  void _closeQueuePanelWithSpring({double velocity = 0.0, bool withHaptic = true}) {
    // setState ensures PopScope rebuilds with correct canPop value
    setState(() {
      _queuePanelTargetOpen = false;
    });
    if (withHaptic) {
      HapticFeedback.lightImpact();
    }
    // Use overdamped spring for snappy close without oscillation
    // Slightly stiffer than open spring for quicker settle
    // PERF: Increased stiffness from 450→600 for snappier close
    const closeSpring = SpringDescription(
      mass: 1.0,
      stiffness: 600.0,
      damping: 52.0, // Overdamped - no bounce, clean settle
    );
    final simulation = SpringSimulation(
      closeSpring,
      _queuePanelController.value,
      0.0,
      velocity,
    );
    _queuePanelController.animateWith(simulation);
  }

  bool get isQueuePanelOpen => _queuePanelController.value > 0.5;

  /// Whether queue panel is intended to be open (target state, not animation value)
  /// Use this for back gesture handling to avoid timing issues during animations
  bool get isQueuePanelTargetOpen => _queuePanelTargetOpen;

  // Sleep timer panel controls
  bool get isSleepTimerPanelOpen => _sleepTimerPanelVisible;

  void _toggleSleepTimerPanel() {
    // Don't check isAnimating - allow toggle even during animation
    // The state variable tracks intent, animation will catch up
    if (!_sleepTimerPanelVisible) {
      _openSleepTimerPanel();
    } else {
      _closeSleepTimerPanel();
    }
  }

  void _openSleepTimerPanel() {
    HapticFeedback.lightImpact();
    // Close queue panel instantly if open
    if (_queuePanelTargetOpen) {
      _queuePanelTargetOpen = false;
      _queuePanelController.value = 0;
    }
    // Close lyrics panel instantly if open
    if (_lyricsPanelTargetOpen) {
      _stopLyricsSync();
      _lyricsPanelTargetOpen = false;
      _lyricsPanelVisible = false;
      _lyricsPanelController.value = 0;
    }
    setState(() {
      _sleepTimerPanelVisible = true;
      _sleepTimerPanelTargetOpen = true;
    });
    // Use same spring physics as queue panel
    final simulation = SpringSimulation(
      _queueSpring,
      _sleepTimerPanelController.value,
      1.0,
      0.0,
    );
    _sleepTimerPanelController.animateWith(simulation);
  }

  void _closeSleepTimerPanel({double velocity = 0.0, bool withHaptic = true}) {
    // Set guard flag immediately to prevent double back gesture
    _isClosingSleepTimerPanel = true;
    setState(() {
      _sleepTimerPanelVisible = false;
      _sleepTimerPanelTargetOpen = false;
    });
    if (withHaptic) {
      HapticFeedback.lightImpact();
    }
    // Use same spring physics as queue panel close
    const closeSpring = SpringDescription(
      mass: 1.0,
      stiffness: 600.0,
      damping: 52.0,
    );
    final simulation = SpringSimulation(
      closeSpring,
      _sleepTimerPanelController.value,
      0.0,
      velocity,
    );
    _sleepTimerPanelController.animateWith(simulation);
    // Clear guard flag when animation completes
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.dismissed) {
        _isClosingSleepTimerPanel = false;
        _sleepTimerPanelController.removeStatusListener(onStatus);
      }
    }
    _sleepTimerPanelController.addStatusListener(onStatus);
  }

  // Lyrics panel controls
  bool get isLyricsPanelOpen => _lyricsPanelVisible;

  void _toggleLyricsPanel() {
    if (!_lyricsPanelVisible) {
      _openLyricsPanel();
    } else {
      _closeLyricsPanel();
    }
  }

  void _openLyricsPanel() {
    HapticFeedback.lightImpact();
    // Close queue panel instantly if open
    if (_queuePanelTargetOpen) {
      _queuePanelTargetOpen = false;
      _queuePanelController.value = 0;
    }
    // Close sleep timer panel if open
    if (_sleepTimerPanelTargetOpen) {
      _sleepTimerPanelTargetOpen = false;
      _sleepTimerPanelVisible = false;
      _sleepTimerPanelController.value = 0;
    }
    setState(() {
      _lyricsPanelVisible = true;
      _lyricsPanelTargetOpen = true;
    });
    // Fetch lyrics for current track if not already loaded
    _fetchLyricsIfNeeded();
    // Start sync if lyrics are already loaded
    if (_hasSyncedLyrics) {
      _startLyricsSync();
    }
    // Use same spring physics as queue panel
    final simulation = SpringSimulation(
      _queueSpring,
      _lyricsPanelController.value,
      1.0,
      0.0,
    );
    _lyricsPanelController.animateWith(simulation);
  }

  void _closeLyricsPanel({double velocity = 0.0, bool withHaptic = true}) {
    // Set guard flag immediately to prevent double back gesture
    _isClosingLyricsPanel = true;
    // Stop lyrics sync
    _stopLyricsSync();
    setState(() {
      _lyricsPanelVisible = false;
      _lyricsPanelTargetOpen = false;
    });
    if (withHaptic) {
      HapticFeedback.lightImpact();
    }
    const closeSpring = SpringDescription(
      mass: 1.0,
      stiffness: 600.0,
      damping: 52.0,
    );
    final simulation = SpringSimulation(
      closeSpring,
      _lyricsPanelController.value,
      0.0,
      velocity,
    );
    _lyricsPanelController.animateWith(simulation);
    // Clear guard flag when animation completes
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.dismissed) {
        _isClosingLyricsPanel = false;
        _lyricsPanelController.removeStatusListener(onStatus);
      }
    }
    _lyricsPanelController.addStatusListener(onStatus);
  }

  Future<void> _fetchLyricsIfNeeded() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final currentTrack = maProvider.currentTrack;
    if (currentTrack == null) return;

    final trackId = currentTrack.uri ?? currentTrack.itemId;

    // Skip if already loaded for this track
    if (_lyricsTrackId == trackId && _currentLyrics != null) return;

    setState(() {
      _isLoadingLyrics = true;
      _currentLyrics = null;
      _parsedLyrics = null;
      _currentLyricIndex = -1;
    });

    try {
      // Try to fetch lyrics via Music Assistant API first
      String? lyrics = await maProvider.api?.getTrackLyrics(
        currentTrack.toJson(),
      );

      // If MA didn't return lyrics, try LRCLIB as fallback
      if (lyrics == null || lyrics.isEmpty) {
        final artistName = currentTrack.artists?.firstOrNull?.name ?? '';
        final albumName = currentTrack.album?.name;
        final durationSeconds = currentTrack.duration?.inSeconds;

        if (artistName.isNotEmpty) {
          final lrclibResult = await MetadataService.getTrackLyrics(
            trackName: currentTrack.name,
            artistName: artistName,
            albumName: albumName,
            durationSeconds: durationSeconds,
          );

          if (lrclibResult != null) {
            // Prefer synced lyrics, fall back to plain
            final (plainLyrics, syncedLyrics) = lrclibResult;
            lyrics = syncedLyrics ?? plainLyrics;
          }
        }
      }

      if (mounted) {
        final parsed = lyrics != null ? _parseLyrics(lyrics) : null;
        setState(() {
          _currentLyrics = lyrics;
          _parsedLyrics = parsed;
          _lyricsTrackId = trackId;
          _isLoadingLyrics = false;
          _currentLyricIndex = -1;
        });
        // Start syncing if we have synced lyrics
        if (parsed != null) {
          _startLyricsSync();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentLyrics = null;
          _parsedLyrics = null;
          _lyricsTrackId = trackId;
          _isLoadingLyrics = false;
        });
      }
    }
  }

  /// Parse LRC formatted lyrics into structured data with timestamps
  /// Returns null if lyrics are not in synced LRC format
  List<_LyricLine>? _parseLyrics(String lyrics) {
    final timestampPattern = RegExp(r'^\[(\d{2}):(\d{2})\.(\d{2,3})\]\s*(.*)$');
    final lines = lyrics.split('\n');
    final parsed = <_LyricLine>[];

    for (final line in lines) {
      final match = timestampPattern.firstMatch(line.trim());
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisStr = match.group(3)!;
        // Handle both 2-digit (centiseconds) and 3-digit (milliseconds) formats
        final millis = millisStr.length == 2
            ? int.parse(millisStr) * 10
            : int.parse(millisStr);
        final text = match.group(4)!.trim();

        // Skip empty lines (instrumental breaks)
        if (text.isNotEmpty) {
          parsed.add(_LyricLine(
            timestamp: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
            text: text,
          ));
        }
      }
    }

    // Return null if no synced lines found (plain lyrics)
    return parsed.isEmpty ? null : parsed;
  }

  /// Check if lyrics have sync data
  bool get _hasSyncedLyrics => _parsedLyrics != null && _parsedLyrics!.isNotEmpty;

  /// Start listening to playback position for lyrics sync
  void _startLyricsSync() {
    _logger.log('🎤 _startLyricsSync called, _hasSyncedLyrics=$_hasSyncedLyrics');
    if (!_hasSyncedLyrics) return;
    _stopLyricsSync(); // Clean up any existing subscription

    final maProvider = context.read<MusicAssistantProvider>();
    _logger.log('🎤 Subscribing to positionStream for lyrics');
    _lyricsPositionSubscription = maProvider.positionTracker.positionStream.listen((position) {
      _logger.log('🎤 Lyrics received position: ${position.inSeconds}s, mounted=$mounted, panelVisible=$_lyricsPanelVisible');
      if (!mounted || !_lyricsPanelVisible || _parsedLyrics == null) return;
      _updateCurrentLyricLine(position);
    });

    // Also update immediately with current position
    final currentPos = maProvider.positionTracker.currentPosition;
    _logger.log('🎤 Lyrics initial position: ${currentPos.inSeconds}s');
    _updateCurrentLyricLine(currentPos);
  }

  /// Stop lyrics sync subscription
  void _stopLyricsSync() {
    _logger.log('🎤 _stopLyricsSync called, subscription was ${_lyricsPositionSubscription != null ? "active" : "null"}');
    _lyricsPositionSubscription?.cancel();
    _lyricsPositionSubscription = null;
  }

  /// Track lyrics scroll position for swipe-to-close gesture
  void _onLyricsScroll() {
    final atTop = !_lyricsScrollController.hasClients || _lyricsScrollController.offset <= 0;
    if (atTop != _isLyricsAtTop) {
      setState(() {
        _isLyricsAtTop = atTop;
      });
    }
  }

  /// Check if lyrics panel swipe-to-close should be allowed
  /// Returns true when: no lyrics content, plain lyrics (no scroll tracking), or synced lyrics at top
  bool get _canSwipeCloseLyrics {
    // No lyrics - allow swipe
    if (_currentLyrics == null) return true;
    // Plain lyrics (SingleChildScrollView) - always allow (starts at top)
    if (!_hasSyncedLyrics) return true;
    // Synced lyrics (ListView) - only when at top
    return _isLyricsAtTop;
  }

  /// Find and highlight the current lyric line based on playback position
  void _updateCurrentLyricLine(Duration position) {
    if (_parsedLyrics == null || _parsedLyrics!.isEmpty) {
      _logger.log('🎤 _updateCurrentLyricLine: No parsed lyrics (null=${_parsedLyrics == null})');
      return;
    }

    // Find the last line whose timestamp is <= current position
    int newIndex = -1;
    for (int i = 0; i < _parsedLyrics!.length; i++) {
      if (_parsedLyrics![i].timestamp <= position) {
        newIndex = i;
      } else {
        break; // Lines are sorted by timestamp
      }
    }

    if (newIndex != _currentLyricIndex) {
      _logger.log('🎤 Lyrics index changed: $_currentLyricIndex -> $newIndex at ${position.inSeconds}s');
      setState(() {
        _currentLyricIndex = newIndex;
      });

      // Auto-scroll to current line if not user scrolling
      if (!_userScrollingLyrics && newIndex >= 0 && _lyricsScrollController.hasClients) {
        _scrollToLyricLine(newIndex);
      }
    }
  }

  /// Scroll to center the given lyric line
  void _scrollToLyricLine(int index) {
    if (!_lyricsScrollController.hasClients) return;

    // Each line is approximately 48 pixels (fontSize 18 + padding)
    const lineHeight = 52.0;
    final targetOffset = index * lineHeight;

    // Get the viewport height to center the line
    final viewportHeight = _lyricsScrollController.position.viewportDimension;
    final centeredOffset = (targetOffset - viewportHeight / 2 + lineHeight / 2)
        .clamp(0.0, _lyricsScrollController.position.maxScrollExtent);

    _lyricsScrollController.animateTo(
      centeredOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  /// Close queue panel if open (for external access via GlobalPlayerOverlay)
  /// [withHaptic]: Set to false for Android back gesture (system provides haptic)
  void closeQueuePanel({bool withHaptic = true}) {
    // Use target state, not animation value, to handle rapid open-close
    // Allow closing even during animation by stopping it first
    if (_queuePanelTargetOpen) {
      if (_queuePanelController.isAnimating) {
        _queuePanelController.stop();
      }
      _closeQueuePanelWithSpring(withHaptic: withHaptic);
    }
  }

  /// Update favorite status when track changes
  void _updateFavoriteStatus(dynamic currentTrack) {
    if (currentTrack == null) {
      _isCurrentTrackFavorite = false;
      _lastTrackUri = null;
      return;
    }

    final trackUri = currentTrack.uri as String?;
    if (trackUri != _lastTrackUri) {
      _lastTrackUri = trackUri;
      _isCurrentTrackFavorite = currentTrack.favorite == true;
    }
  }

  /// Toggle favorite status for current track (with offline queuing support)
  Future<void> _toggleCurrentTrackFavorite(dynamic currentTrack) async {
    if (currentTrack == null) return;

    final maProvider = context.read<MusicAssistantProvider>();

    try {
      bool success;

      if (_isCurrentTrackFavorite) {
        // Remove from favorites - need library_item_id (numeric)
        int? libraryItemId;

        if (currentTrack.provider == 'library') {
          // If provider is library, itemId is the library ID
          libraryItemId = int.tryParse(currentTrack.itemId.toString());
        } else if (currentTrack.providerMappings != null) {
          // Find the library mapping to get the library ID
          final mappings = currentTrack.providerMappings as List<dynamic>?;
          if (mappings != null) {
            for (final mapping in mappings) {
              if (mapping.providerInstance == 'library') {
                libraryItemId = int.tryParse(mapping.itemId.toString());
                break;
              }
            }
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromFavorites(
            mediaType: 'track',
            libraryItemId: libraryItemId,
          );
        } else {
          throw Exception('Could not determine library ID for this track');
        }
      } else {
        // Add to favorites - use the source provider (not library)
        String actualProvider = currentTrack.provider?.toString() ?? 'library';
        String actualItemId = currentTrack.itemId?.toString() ?? '';

        if (currentTrack.providerMappings != null) {
          final mappings = currentTrack.providerMappings as List<dynamic>?;
          if (mappings != null && mappings.isNotEmpty) {
            // Find a non-library provider mapping
            // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
            for (final mapping in mappings) {
              if (mapping.available == true && mapping.providerInstance != 'library') {
                actualProvider = mapping.providerDomain;
                actualItemId = mapping.itemId;
                break;
              }
            }
            // Fallback to first available if no non-library found
            if (actualProvider == 'library') {
              for (final mapping in mappings) {
                if (mapping.available == true) {
                  actualProvider = mapping.providerDomain;
                  actualItemId = mapping.itemId;
                  break;
                }
              }
            }
          }
        }

        success = await maProvider.addToFavorites(
          mediaType: 'track',
          itemId: actualItemId,
          provider: actualProvider,
        );
      }

      if (success) {
        // Toggle local state
        setState(() {
          _isCurrentTrackFavorite = !_isCurrentTrackFavorite;
        });

        // Invalidate home cache so favorites are updated
        maProvider.invalidateHomeCache();

        // Show feedback (different message if offline)
        if (mounted) {
          final isOffline = !maProvider.isConnected;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOffline
                    ? S.of(context)!.actionQueuedForSync
                    : (_isCurrentTrackFavorite ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      // Show error feedback
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

  /// Navigate to artist details screen
  void _navigateToArtist(MusicAssistantProvider maProvider, dynamic currentTrack) {
    if (currentTrack == null) return;

    // Skip for podcasts/audiobooks - they show author/podcast name but navigation isn't applicable
    if (maProvider.isPlayingPodcast || maProvider.isPlayingAudiobook) return;

    // For regular tracks, navigate to first artist
    final artists = currentTrack.artists;
    if (artists != null && artists is List && artists.isNotEmpty) {
      final artist = artists.first;
      if (artist is Artist) {
        // Collapse player first, then navigate using global navigator key
        collapse();
        navigationProvider.navigatorKey.currentState?.push(
          FadeSlidePageRoute(
            child: ArtistDetailsScreen(artist: artist),
          ),
        );
      }
    }
  }

  /// Navigate to album details screen
  void _navigateToAlbum(dynamic currentTrack) {
    if (currentTrack == null) return;

    final album = currentTrack.album;
    if (album != null && album is Album) {
      // Collapse player first, then navigate using global navigator key
      collapse();
      navigationProvider.navigatorKey.currentState?.push(
        FadeSlidePageRoute(
          child: AlbumDetailsScreen(album: album),
        ),
      );
    }
  }

  /// Show fullscreen album art overlay
  void _showFullscreenArt(BuildContext context, String? imageUrl) {
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
                  child: Hero(
                    tag: 'fullscreen_album_art',
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
            ),
          );
        },
      ),
    );
  }

  /// Get available players sorted alphabetically (consistent with device selector)
  List<dynamic> _getAvailablePlayersSorted(MusicAssistantProvider maProvider) {
    // Use the provider's already-sorted list, filter for available only
    return maProvider.availablePlayers.where((p) => p.available).toList();
  }

  /// Get the next or previous player relative to current selection
  dynamic _getAdjacentPlayer(MusicAssistantProvider maProvider, {required bool next}) {
    final players = _getAvailablePlayersSorted(maProvider);
    if (players.length <= 1) return null;

    final selectedPlayerId = maProvider.selectedPlayer?.playerId;
    final currentIndex = players.indexWhere((p) => p.playerId == selectedPlayerId);

    if (currentIndex == -1) return players[0];

    int adjacentIndex;
    if (next) {
      adjacentIndex = currentIndex >= players.length - 1 ? 0 : currentIndex + 1;
    } else {
      adjacentIndex = currentIndex <= 0 ? players.length - 1 : currentIndex - 1;
    }

    return players[adjacentIndex];
  }

  // Cache for peek track data
  dynamic _peekTrack;

  /// Cycle to the next available player (for swipe gesture)
  void _cycleToNextPlayer(MusicAssistantProvider maProvider, {bool reverse = false}) {
    final players = _getAvailablePlayersSorted(maProvider);
    if (players.length <= 1) return;

    final selectedPlayerId = maProvider.selectedPlayer?.playerId;
    final currentIndex = players.indexWhere((p) => p.playerId == selectedPlayerId);

    // If current player not found in list, start from beginning
    if (currentIndex == -1) {
      HapticFeedback.mediumImpact();
      maProvider.selectPlayer(players[0]);
      return;
    }

    int nextIndex;
    if (reverse) {
      nextIndex = currentIndex <= 0 ? players.length - 1 : currentIndex - 1;
    } else {
      nextIndex = currentIndex >= players.length - 1 ? 0 : currentIndex + 1;
    }

    // Haptic feedback on device switch
    HapticFeedback.mediumImpact();

    // Animate slide transition
    _animateSlide(reverse ? 1 : -1, () {
      maProvider.selectPlayer(players[nextIndex]);
    });
  }

  /// Handle real-time drag updates for finger-following swipe
  void _handleHorizontalDragUpdate(DragUpdateDetails details, MusicAssistantProvider maProvider, double containerWidth) {
    if (_isSliding) return;

    // Start tracking if not already
    if (!_isDragging) {
      _isDragging = true;
      _peekPlayer = null;
      _peekImageUrl = null;
      _peekTrack = null;
    }

    // Calculate normalized offset (-1 to 1 range)
    // Negative = dragging left (showing next player from right)
    // Positive = dragging right (showing previous player from left)
    final delta = details.primaryDelta ?? 0;
    final normalizedDelta = delta / containerWidth;
    final newSlideOffset = (_slideOffset + normalizedDelta).clamp(-1.0, 1.0);

    // Update slideOffset via ValueNotifier (no setState needed - avoids 60fps rebuilds)
    _slideOffset = newSlideOffset;

    // Only trigger setState when peek player changes (not every frame)
    if (_slideOffset != 0) {
      _updatePeekPlayerState(maProvider, _slideOffset);
    }
  }

  /// Update peek player state variables - only calls setState when peek player changes
  void _updatePeekPlayerState(MusicAssistantProvider maProvider, double dragDirection) {
    // dragDirection < 0 means swiping left (next player)
    // dragDirection > 0 means swiping right (previous player)
    final isNext = dragDirection < 0;
    final newPeekPlayer = _getAdjacentPlayer(maProvider, next: isNext);

    // Only setState when peek player actually changes (prevents unnecessary rebuilds)
    if (newPeekPlayer?.playerId != _peekPlayer?.playerId) {
      setState(() {
        _peekPlayer = newPeekPlayer;
        // Get the peek player's current track image if available
        if (_peekPlayer != null) {
          _peekTrack = maProvider.getCachedTrackForPlayer(_peekPlayer.playerId);
          _peekImageUrl = _peekTrack != null ? maProvider.getImageUrl(_peekTrack, size: 512) : null;
        } else {
          _peekTrack = null;
          _peekImageUrl = null;
        }
      });
    }
  }

  /// Handle drag end - either commit to next player or snap back
  void _handleHorizontalDragEnd(DragEndDetails details, MusicAssistantProvider maProvider) {
    if (!_isDragging || _isSliding) {
      _isDragging = false;
      return;
    }

    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0;

    // Thresholds for committing the swipe
    const commitThreshold = 0.3; // 30% of width
    const velocityThreshold = 500.0; // px/s

    final shouldCommit = _slideOffset.abs() > commitThreshold || velocity.abs() > velocityThreshold;
    final direction = _slideOffset != 0 ? _slideOffset.sign : (velocity != 0 ? -velocity.sign : 0);

    if (shouldCommit && _peekPlayer != null && direction != 0) {
      // Commit: animate to full slide, switch player, then reset
      // Note: Don't clear _peekPlayer here - let _animateCommit handle cleanup
      // so the peek content can remain visible during the transition
      _animateCommit(direction.toInt(), () {
        HapticFeedback.mediumImpact();
        maProvider.selectPlayer(_peekPlayer);
      });
    } else {
      // Cancel: spring back to center
      _animateSnapBack();
    }
  }

  /// Animate committing to the next/previous player
  void _animateCommit(int direction, VoidCallback onSwitch) {
    if (_isSliding) return;

    // Mark transition state in setState to ensure rebuilds happen properly
    setState(() {
      _isSliding = true;
      // Mark transition BEFORE animation - this keeps peek content visible
      // and hides main content to prevent any flash
      _inTransition = true;
    });

    final startOffset = _slideOffset;
    final targetOffset = direction < 0 ? -1.0 : 1.0;

    _slideController.reset();

    void animateToTarget() {
      if (!mounted) return;
      final curvedValue = Curves.easeOutCubic.transform(_slideController.value);
      // ValueNotifier triggers AnimatedBuilder rebuild - no setState needed
      _slideOffset = startOffset + (targetOffset - startOffset) * curvedValue;
    }

    _slideController.addListener(animateToTarget);
    _slideController.duration = const Duration(milliseconds: 150);

    _slideController.forward().then((_) {
      if (!mounted) return;

      _slideController.removeListener(animateToTarget);

      // Cache the peek data BEFORE switching - we'll use this to crossfade
      final cachedPeekPlayer = _peekPlayer;
      final cachedPeekTrack = _peekTrack;
      final cachedPeekImageUrl = _peekImageUrl;

      // Switch the player - this sets currentTrack from cache in the provider
      onSwitch();

      // Get the new track state
      final maProvider = context.read<MusicAssistantProvider>();
      final newTrack = maProvider.currentTrack;

      // Move peek content to center position (slideOffset = 0) while keeping it visible.
      // The main content is hidden via _inTransition flag.
      // This creates a seamless visual - peek content is already at center.
      _slideOffset = 0.0; // ValueNotifier triggers AnimatedBuilder rebuild
      setState(() {
        _isSliding = false;
        // Keep _inTransition = true and peek data intact
      });

      if (newTrack != null) {
        // Switching to a playing player - need to wait for image to be ready
        // before showing main content and hiding peek
        final newImageUrl = maProvider.getImageUrl(newTrack, size: 512);

        if (newImageUrl != null && newImageUrl == cachedPeekImageUrl) {
          // Same image - can transition immediately
          _completeTransition();
        } else if (newImageUrl != null) {
          // Different image - precache it first, then transition
          _precacheAndTransition(newImageUrl);
        } else {
          // No image - transition after frame
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _completeTransition();
          });
        }
      } else {
        // Switching to non-playing player - DeviceSelectorBar will show
        // Wait for it to render, then complete transition
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _completeTransition();
          });
        });
      }

      _slideController.duration = const Duration(milliseconds: 250); // Reset default
    });
  }

  /// Precache an image and then complete the transition
  void _precacheAndTransition(String imageUrl) {
    // Use CachedNetworkImage's cache to ensure image is ready
    final imageProvider = CachedNetworkImageProvider(imageUrl);
    final imageStream = imageProvider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;

    void cleanupListener() {
      imageStream.removeListener(listener);
      _activeImageStreams.remove(imageStream);
    }

    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        cleanupListener();
        if (mounted) {
          // Image is now in memory cache - safe to transition
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _completeTransition();
          });
        }
      },
      onError: (exception, stackTrace) {
        cleanupListener();
        // Even on error, complete the transition
        if (mounted) _completeTransition();
      },
    );

    // Track the listener for cleanup on dispose
    _activeImageStreams[imageStream] = listener;
    imageStream.addListener(listener);

    // Safety timeout - don't wait forever
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _inTransition && _activeImageStreams.containsKey(imageStream)) {
        cleanupListener();
        _completeTransition();
      }
    });
  }

  /// Complete the transition by hiding peek content and showing main content
  void _completeTransition() {
    if (!mounted) return;
    setState(() {
      _inTransition = false;
      _peekPlayer = null;
      _peekTrack = null;
      _peekImageUrl = null;
    });
  }

  /// Animate snapping back to center (cancelled swipe)
  void _animateSnapBack() {
    if (_isSliding) return;
    _isSliding = true;

    final startOffset = _slideOffset;
    _slideController.reset();

    void animateBack() {
      if (!mounted) return;
      final curvedValue = Curves.easeOutBack.transform(_slideController.value);
      // ValueNotifier triggers AnimatedBuilder rebuild - no setState needed
      _slideOffset = startOffset * (1.0 - curvedValue);
    }

    _slideController.addListener(animateBack);
    _slideController.duration = const Duration(milliseconds: 220); // Snappier snap-back

    _slideController.forward().then((_) {
      if (!mounted) return;
      _slideController.removeListener(animateBack);
      // Update slideOffset via ValueNotifier (triggers rebuild)
      _slideOffset = 0.0;
      // Other state changes still need setState
      setState(() {
        _isSliding = false;
        _peekPlayer = null;
        _peekImageUrl = null;
      });
      _slideController.duration = const Duration(milliseconds: 250); // Reset default
    });
  }

  /// Legacy method - now calls new commit animation
  void _animateSlide(int direction, VoidCallback onComplete) {
    _animateCommit(direction, onComplete);
  }

  @override
  Widget build(BuildContext context) {
    // PERF: Use select() to only rebuild when adaptive theme setting changes
    final adaptiveTheme = context.select<ThemeProvider, bool>((p) => p.adaptiveTheme);
    // Get full themeProvider for methods that need adaptive color schemes
    final themeProvider = context.read<ThemeProvider>();

    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final selectedPlayer = maProvider.selectedPlayer;
        final currentTrack = maProvider.currentTrack;

        // Don't show if no player selected
        if (selectedPlayer == null) {
          return const SizedBox.shrink();
        }

        // Get image URL for current track
        final imageUrl = currentTrack != null
            ? maProvider.getImageUrl(currentTrack, size: 512)
            : null;

        // Extract colors for adaptive theme
        if (adaptiveTheme && imageUrl != null) {
          _extractColors(imageUrl);
        }

        // Update favorite status when track changes
        _updateFavoriteStatus(currentTrack);

        // Sync progress notifier with position tracker
        // This ensures the progress bar shows correct position on expand,
        // after seek, or when switching players
        final currentPosition = maProvider.positionTracker.currentPosition.inSeconds;
        if (_progressNotifier.value != currentPosition) {
          // Use addPostFrameCallback to avoid updating during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _progressNotifier.value = currentPosition;
            }
          });
        }

        // Handle Android back button - close panels first, then collapse player
        // Priority: queue panel > lyrics panel > sleep timer panel > collapse player
        // Use target states (intent) instead of animation values for reliable back handling
        // This prevents race conditions where state changes during gesture processing
        return PopScope(
          canPop: !_queuePanelTargetOpen && !_lyricsPanelTargetOpen && !_sleepTimerPanelTargetOpen && !isExpanded,
          onPopInvokedWithResult: (didPop, result) {
            _logger.log('🔙 PopScope onPopInvokedWithResult: didPop=$didPop, isExpanded=$isExpanded, isAnimating=${_controller.isAnimating}');
            if (!didPop) {
              // Ignore back events while a panel is closing
              // Guard flags are set immediately when close starts, before animation
              // This prevents double back gesture from closing both panel and player
              if (_isClosingLyricsPanel || _isClosingSleepTimerPanel) {
                _logger.log('🔙 PopScope: Ignoring - panel is closing');
                return;
              }

              if (_queuePanelTargetOpen) {
                // Always close queue panel on back, even if animating
                // Stop any existing animation and start close
                if (_queuePanelController.isAnimating) {
                  _queuePanelController.stop();
                }
                // No haptic - Android back gesture provides its own haptic feedback
                _closeQueuePanelWithSpring(withHaptic: false);
              } else if (_lyricsPanelTargetOpen) {
                // Close lyrics panel (no haptic - Android provides its own)
                _closeLyricsPanel(withHaptic: false);
              } else if (_sleepTimerPanelTargetOpen) {
                // Close sleep timer panel (no haptic - Android provides its own)
                _closeSleepTimerPanel(withHaptic: false);
              } else if (isExpanded) {
                // Only collapse if not already animating
                // No haptic - Android back gesture provides its own
                if (!_controller.isAnimating) {
                  collapse(withHaptic: false);
                }
              }
            }
          },
          child: AnimatedBuilder(
            // PERF: Only include _expandAnimation and _slideOffsetNotifier
            // Queue panel has its own AnimatedBuilder - don't rebuild entire player on queue animation
            animation: Listenable.merge([_expandAnimation, _slideOffsetNotifier]),
            builder: (context, _) {
              // If no track is playing, show device selector bar
              if (currentTrack == null) {
                return _buildDeviceSelectorBar(context, maProvider, selectedPlayer, themeProvider);
              }
              return _buildMorphingPlayer(
                context,
                maProvider,
                selectedPlayer,
                currentTrack,
                imageUrl,
                themeProvider,
              );
            },
          ),
        );
      },
    );
  }

  /// Build a compact device selector bar when no track is playing
  Widget _buildDeviceSelectorBar(
    BuildContext context,
    MusicAssistantProvider maProvider,
    dynamic selectedPlayer,
    ThemeProvider themeProvider,
  ) {
    // PERF Phase 1: Batch MediaQuery and Theme lookups
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    // Use viewPadding to match BottomNavigationBar's height calculation
    final bottomPadding = mediaQuery.viewPadding.bottom;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Get adaptive colors if available
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    final backgroundColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.primaryContainer
        : colorScheme.primaryContainer;
    final textColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.onPrimaryContainer
        : colorScheme.onPrimaryContainer;

    final bottomNavSpace = _bottomNavHeight + bottomPadding;
    final bottomOffset = bottomNavSpace + _collapsedMargin;
    final width = screenSize.width - (_collapsedMargin * 2);

    // Apply slide offset for hiding and bounce offset for reveal animation
    final slideDownAmount = widget.slideOffset * (_collapsedHeight + bottomOffset + 20);
    final bounceDownAmount = widget.bounceOffset;
    final adjustedBottomOffset = bottomOffset - slideDownAmount - bounceDownAmount;

    final availablePlayers = _getAvailablePlayersSorted(maProvider);
    final hasMultiplePlayers = availablePlayers.length > 1;

    return Positioned(
      left: _collapsedMargin,
      right: _collapsedMargin,
      bottom: adjustedBottomOffset,
      child: GestureDetector(
        // Tap to dismiss player reveal (matching _buildMorphingPlayer behavior)
        onTap: widget.isDeviceRevealVisible ? GlobalPlayerOverlay.dismissPlayerReveal : null,
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta! > 5 && widget.onRevealPlayers != null) {
            widget.onRevealPlayers!();
          }
        },
        child: DeviceSelectorBar(
        selectedPlayer: selectedPlayer,
        peekPlayer: _peekPlayer,
        hasMultiplePlayers: hasMultiplePlayers,
        backgroundColor: backgroundColor,
        textColor: textColor,
        width: width,
        height: _collapsedHeight,
        borderRadius: _collapsedBorderRadius,
        slideOffset: _slideOffset,
        onHorizontalDragStart: (details) {
          _horizontalDragStartX = details.globalPosition.dx;
        },
        onHorizontalDragUpdate: (details) {
          // Check for edge dead zone
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          if (startedInDeadZone) return;

          _handleHorizontalDragUpdate(details, maProvider, width);
        },
        onHorizontalDragEnd: (details) {
          // Check for edge dead zone
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          _horizontalDragStartX = null;

          if (startedInDeadZone) return;

          _handleHorizontalDragEnd(details, maProvider);
        },
        onPowerToggle: () => maProvider.togglePower(selectedPlayer.playerId),
      ),
      ),
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
    // PERF Phase 1: Batch MediaQuery lookups - single InheritedWidget lookup
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    // Use viewPadding (not padding) to match BottomNavigationBar's height calculation
    // viewPadding represents permanent system UI, padding can change (e.g., keyboard)
    final bottomPadding = mediaQuery.viewPadding.bottom;
    final topPadding = mediaQuery.padding.top;
    // PERF Phase 1: Batch Theme lookups
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

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
    // Create a darker shade for the "unplayed" portion of progress bar
    final collapsedBgUnplayed = Color.lerp(collapsedBg, Colors.black, 0.3)!;
    final expandedBg = adaptiveScheme?.surface ?? const Color(0xFF121212);
    final expandedPrimary = adaptiveScheme?.primary;
    // Always update to current value - don't preserve stale adaptive colors
    _currentExpandedBgColor = expandedBg;
    _currentExpandedPrimaryColor = expandedPrimary;
    // When collapsed, use the darker unplayed color as base (progress bar will overlay the played portion)
    // When expanded, transition to the normal background
    final backgroundColor = Color.lerp(t < 0.5 ? collapsedBgUnplayed : collapsedBg, expandedBg, t)!;

    // Update system nav bar to match player background when expanding
    // Use post-frame callback to avoid setting state during build
    if (t > 0.5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final iconBrightness = backgroundColor.computeLuminance() > 0.5
            ? Brightness.dark
            : Brightness.light;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            systemNavigationBarColor: backgroundColor,
            systemNavigationBarIconBrightness: iconBrightness,
          ),
        );
      });
    }

    final collapsedTextColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.onPrimaryContainer
        : colorScheme.onPrimaryContainer;
    // Use colorScheme.onSurface as fallback instead of Colors.white for light theme support
    final expandedTextColor = adaptiveScheme?.onSurface ?? colorScheme.onSurface;
    final textColor = Color.lerp(collapsedTextColor, expandedTextColor, t)!;

    // Use colorScheme.primary as fallback instead of Colors.white for light theme support
    final primaryColor = adaptiveScheme?.primary ?? colorScheme.primary;

    // PERF Phase 4: Pre-compute commonly used color opacities to reduce withOpacity() allocations per frame
    // These are used multiple times throughout the widget tree during animation
    final textColor50 = textColor.withOpacity(0.5);
    final textColor60 = textColor.withOpacity(MiniPlayerLayout.secondaryTextOpacity);
    final textColor70 = textColor.withOpacity(0.7);
    final textColor45 = textColor.withOpacity(0.45);
    final primaryColor20 = primaryColor.withOpacity(0.2);
    final primaryColor70 = primaryColor.withOpacity(0.7);

    // PERF Phase 5: Pre-compute Alignment and FontWeight to avoid lerp calls per text element
    // These are used by title, artist, and player name text elements
    final textAlignment = Alignment.lerp(Alignment.centerLeft, Alignment.center, t)!;
    final titleFontWeight = FontWeight.lerp(MiniPlayerLayout.primaryFontWeight, FontWeight.w600, t);

    // Collapsed: position above bottom nav bar
    // Expanded: extend to very bottom (behind system nav bar) for seamless edge-to-edge
    final bottomNavSpace = _bottomNavHeight + bottomPadding;
    final collapsedBottomOffset = bottomNavSpace + _collapsedMargin;
    final expandedBottomOffset = 0.0; // Extend behind system nav bar
    final expandedHeight = screenSize.height; // Full screen height for edge-to-edge

    // Apply slide offset to hide mini player (slides down off-screen)
    // Apply bounce offset for reveal animation (small downward movement)
    // Smoothly fade out offsets as animation progresses (continuous, no discontinuity)
    final slideDownAmount = widget.slideOffset * (_collapsedHeight + collapsedBottomOffset + 20);
    final bounceDownAmount = widget.bounceOffset;
    // Fade out slide/bounce effects smoothly over first 15% of animation
    final offsetFade = (1.0 - (t / 0.15)).clamp(0.0, 1.0);
    final baseBottomOffset = _lerpDouble(collapsedBottomOffset, expandedBottomOffset, t);
    final slideAdjustedBottomOffset = baseBottomOffset - (slideDownAmount + bounceDownAmount) * offsetFade;

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
    final artBorderRadius = _lerpDouble(0, 12, t); // Square in mini player, rounded when expanded

    // Art position - uses MaterialRectCenterArcTween for Hero-like curved arc path
    // This creates a natural arc trajectory instead of straight diagonal movement
    // PERF: Cache the tween - only recreate when screen dimensions change
    final collapsedArtLeft = 0.0;
    final collapsedArtTop = (_collapsedHeight - _collapsedArtSize) / 2;
    final expandedArtLeft = (screenSize.width - expandedArtSize) / 2;
    final expandedArtTop = topPadding + headerHeight + 16;

    if (_artRectTween == null || _lastScreenSize != screenSize || _lastTopPadding != topPadding) {
      final collapsedArtRect = Rect.fromLTWH(collapsedArtLeft, collapsedArtTop, _collapsedArtSize, _collapsedArtSize);
      final expandedArtRect = Rect.fromLTWH(expandedArtLeft, expandedArtTop, expandedArtSize, expandedArtSize);
      _artRectTween = MaterialRectCenterArcTween(begin: collapsedArtRect, end: expandedArtRect);
      _lastScreenSize = screenSize;
      _lastTopPadding = topPadding;
    }
    final artRect = _artRectTween!.lerp(t)!;
    final artLeft = artRect.left;
    final artTop = artRect.top;
    final artSize = artRect.width;

    // Typography - uses shared MiniPlayerLayout constants for collapsed state
    final titleFontSize = _lerpDouble(MiniPlayerLayout.primaryFontSize, 24.0, t);
    final artistFontSize = _lerpDouble(MiniPlayerLayout.secondaryFontSize, 18.0, t);

    // Text position - left edge position (alignment handles centering smoothly)
    final expandedTitleLeft = contentPadding;
    final titleLeft = _lerpDouble(MiniPlayerLayout.textLeft, expandedTitleLeft, t);

    final collapsedTitleTop = MiniPlayerLayout.primaryTop;

    // Controls: 36 (prev) + 34 (play) + 36 (next) + 8 (right margin) = 114px from widget right
    // For 8px gap: text ends at widgetWidth - 114 - 8 = widgetWidth - 122
    final collapsedTitleWidth = collapsedWidth - MiniPlayerLayout.textLeft - 122;
    final expandedTitleWidth = screenSize.width - (contentPadding * 2);
    final titleWidth = _lerpDouble(collapsedTitleWidth, expandedTitleWidth, t);

    // Measure actual title height for dynamic layout (CACHED to avoid layout every frame)
    final titleStyle = TextStyle(
      fontSize: 24.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 1.2,
    );
    // Only recalculate when track changes (screen width doesn't change during animation)
    if (_lastMeasuredTrackName != currentTrack.name ||
        _cachedExpandedTitleHeight == null) {
      final titlePainter = TextPainter(
        text: TextSpan(text: currentTrack.name, style: titleStyle),
        maxLines: 2,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: expandedTitleWidth);
      _cachedExpandedTitleHeight = titlePainter.height;
      _lastMeasuredTrackName = currentTrack.name;
    }
    final expandedTitleHeight = _cachedExpandedTitleHeight!;

    // Calculate track info block height (title + gap + artist + gap + album)
    final titleToArtistGap = 12.0;
    final artistToAlbumGap = 8.0;
    final artistHeight = 22.0; // Approximate height for 18px font
    // Album/chapter line visibility must match render condition:
    // Show when: (album exists OR audiobook) AND NOT podcast
    final showAlbumLine = (currentTrack.album != null || maProvider.isPlayingAudiobook) && !maProvider.isPlayingPodcast;
    final albumHeight = showAlbumLine ? 20.0 : 0.0;
    final trackInfoBlockHeight = expandedTitleHeight + titleToArtistGap + artistHeight +
        (showAlbumLine ? artistToAlbumGap + albumHeight : 0.0);

    // Controls section heights (from bottom up):
    // - Volume slider: 48px
    // - Gap: 40px (was 88-48=40 from volumeTop calculation)
    // - Controls row: ~70px (centered at expandedControlsTop)
    // - Gap: 64px (from expandedControlsTop = expandedProgressTop + 64)
    // - Progress bar + times: ~70px
    // Total from bottom edge: ~48 + 40 + 70 + 64 = 222, plus safe area padding
    // Position progress bar so controls section is anchored at bottom
    // PERF Phase 1: Use already-batched bottomPadding instead of separate MediaQuery lookup
    final bottomSafeArea = bottomPadding;
    final controlsSectionHeight = 222.0; // Total height of progress + controls + volume
    final playButtonHalfHeight = 36.0; // Half of the 72px play button container
    final expandedProgressTop = screenSize.height - bottomSafeArea - controlsSectionHeight - 24 - playButtonHalfHeight;

    // Calculate available space between art bottom and progress bar
    final artBottom = expandedArtTop + expandedArtSize;
    final availableSpace = expandedProgressTop - artBottom;

    // Center the track info block in available space
    final trackInfoTopMargin = (availableSpace - trackInfoBlockHeight) / 2;
    final expandedTitleTop = artBottom + trackInfoTopMargin;
    final titleTop = _lerpDouble(collapsedTitleTop, expandedTitleTop, t);

    // Artist positioned dynamically based on actual title height
    final collapsedArtistTop = MiniPlayerLayout.secondaryTop;
    final expandedArtistTop = expandedTitleTop + expandedTitleHeight + titleToArtistGap;
    final artistTop = _lerpDouble(collapsedArtistTop, expandedArtistTop, t);

    // Player name - animated to move with other text elements
    // Starts at tertiary position, animates toward artist position as it fades out
    final collapsedPlayerNameTop = MiniPlayerLayout.tertiaryTop;
    final expandedPlayerNameTop = expandedArtistTop; // Animates toward artist final position
    final playerNameTop = _lerpDouble(collapsedPlayerNameTop, expandedPlayerNameTop, t);

    // Album - subtle, below artist
    final expandedAlbumTop = expandedArtistTop + artistHeight + artistToAlbumGap;

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

    // Utility buttons - below volume control
    final utilityButtonsTop = volumeTop + 56;

    // Check if we have multiple players for swipe gesture
    final availablePlayers = _getAvailablePlayersSorted(maProvider);
    final hasMultiplePlayers = availablePlayers.length > 1;
    final selectedPlayerId = selectedPlayer.playerId;

    // Calculate slide offset for mini player content (only when collapsed)
    // Smoothly fade out horizontal slide offset (for device switching) as animation progresses
    final miniPlayerSlideOffset = _slideOffset * collapsedWidth * offsetFade;

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      bottom: bottomOffset,
      child: GestureDetector(
        // Use translucent to allow child widgets (like buttons) to receive taps
        behavior: HitTestBehavior.translucent,
        // Handle tap: when device list is visible, dismiss it; when collapsed, expand
        onTap: isExpanded ? null : (widget.isDeviceRevealVisible ? GlobalPlayerOverlay.dismissPlayerReveal : expand),
        onVerticalDragStart: (details) {
          // Track start position for bottom dead zone detection
          _verticalDragStartY = details.globalPosition.dy;
          // Ignore while queue item is being dragged
          if (_isQueueDragging) return;
          // For expanded player or queue panel: start tracking immediately
          // For collapsed player: defer decision until we know swipe direction
          if (isExpanded || isQueuePanelOpen) {
            _handleVerticalDragStart(details);
          }
        },
        onVerticalDragUpdate: (details) {
          // Ignore while queue item is being dragged
          if (_isQueueDragging) return;

          final delta = details.primaryDelta ?? 0;

          // Handle queue panel close
          if (isQueuePanelOpen && delta > 0) {
            _toggleQueuePanel();
            return;
          }

          // Collapsed + not yet tracking: decide based on direction
          if (!isExpanded && !_isVerticalDragging) {
            if (delta > 5 && widget.onRevealPlayers != null) {
              // Swipe down → show player reveal
              widget.onRevealPlayers!();
              return;
            } else if (delta < -5) {
              // Swipe up → start expand tracking
              _handleVerticalDragStart(DragStartDetails(
                globalPosition: details.globalPosition,
                localPosition: details.localPosition,
              ));
            } else {
              // Not enough movement yet, wait for more
              return;
            }
          }

          // Gesture-driven expand/collapse
          _handleVerticalDragUpdate(details);
        },
        onVerticalDragEnd: (details) {
          // Ignore while queue item is being dragged
          if (_isQueueDragging) return;

          // Check if swipe started in bottom dead zone (Android app switcher gesture area)
          final screenHeight = MediaQuery.of(context).size.height;
          final startedInBottomDeadZone = _verticalDragStartY != null &&
              _verticalDragStartY! > screenHeight - _bottomDeadZone;
          _verticalDragStartY = null;

          // Expanded mode: swipe UP to open queue (but not from bottom dead zone)
          if (isExpanded && !isQueuePanelOpen && !startedInBottomDeadZone && details.primaryVelocity != null) {
            if (details.primaryVelocity! < -300) {
              _toggleQueuePanel();
              return;
            }
          }

          // Finish gesture-driven expansion
          _handleVerticalDragEnd(details);
        },
        onVerticalDragCancel: () {
          // Reset state if gesture is cancelled (e.g., system takes over)
          _isVerticalDragging = false;
          _verticalDragStartY = null;
        },
        onHorizontalDragStart: (details) {
          _horizontalDragStartX = details.globalPosition.dx;
          // Queue panel swipe is handled by QueuePanel's Listener (bypasses gesture arena)
          // Start volume drag if device reveal is visible
          if (widget.isDeviceRevealVisible && !isExpanded) {
            // For consecutive swipes, use local volume (API may not have updated player state yet)
            final now = DateTime.now().millisecondsSinceEpoch;
            final timeSinceLastDrag = now - _lastVolumeDragEndTime;
            final isWithinWindow = timeSinceLastDrag < _consecutiveSwipeWindowMs;

            // Use local volume if we have an override AND within window
            final useLocalVolume = _hasLocalVolumeOverride && isWithinWindow;

            final startVolume = useLocalVolume
                ? _dragVolumeLevel // Continue from where last swipe ended
                : (selectedPlayer.volumeLevel ?? 0).toDouble() / 100.0; // Fresh from player

            setState(() {
              _isDraggingVolume = true;
              _dragVolumeLevel = startVolume;
            });
            _lastVolumeDragPosition = details.globalPosition;
            HapticFeedback.lightImpact();
          }
        },
        onHorizontalDragUpdate: (details) {
          // Queue panel swipe is handled by QueuePanel's Listener (bypasses gesture arena)
          // Volume swipe when device reveal is visible
          if (widget.isDeviceRevealVisible && _isDraggingVolume && !isExpanded) {
            // Check for stillness to trigger precision mode (only if enabled in settings)
            final currentPosition = details.globalPosition;
            if (_volumePrecisionModeEnabled && _lastVolumeDragPosition != null) {
              final movement = (currentPosition - _lastVolumeDragPosition!).distance;

              if (movement < _precisionStillnessThreshold) {
                // Finger is still - start precision timer if not already running
                if (_volumePrecisionTimer == null && !_inVolumePrecisionMode) {
                  _volumePrecisionTimer = Timer(
                    Duration(milliseconds: _precisionTriggerMs),
                    _enterVolumePrecisionMode,
                  );
                }
              } else {
                // Finger moved - cancel timer (but don't exit precision mode if already in it)
                _volumePrecisionTimer?.cancel();
                _volumePrecisionTimer = null;
              }
            }
            _lastVolumeDragPosition = currentPosition;
            _lastVolumeLocalX = details.localPosition.dx;

            double newVolume;

            if (_inVolumePrecisionMode) {
              // PRECISION MODE: Movement from entry point maps to zoomed range
              // Full width of movement = precisionSensitivity (10%) change
              // e.g., at 40% center: moving full width right = 50%, full width left = 30%
              final offsetX = details.localPosition.dx - _volumePrecisionStartX;
              final normalizedOffset = offsetX / collapsedWidth; // -1.0 to +1.0 range
              final volumeChange = normalizedOffset * _precisionSensitivity;
              newVolume = (_volumePrecisionZoomCenter + volumeChange).clamp(0.0, 1.0);
            } else {
              // NORMAL MODE: Delta-based movement (full width = 100%)
              final dragDelta = details.delta.dx;
              final volumeDelta = dragDelta / collapsedWidth;
              newVolume = (_dragVolumeLevel + volumeDelta).clamp(0.0, 1.0);
            }

            if ((newVolume - _dragVolumeLevel).abs() > 0.001) {
              setState(() {
                _dragVolumeLevel = newVolume;
              });
              // Throttle API calls to prevent flooding (faster in precision mode)
              final now = DateTime.now().millisecondsSinceEpoch;
              final throttleMs = _inVolumePrecisionMode ? _precisionThrottleMs : _volumeThrottleMs;
              if (now - _lastVolumeUpdateTime >= throttleMs) {
                _lastVolumeUpdateTime = now;
                maProvider.setVolume(selectedPlayer.playerId, (newVolume * 100).round());
              }
            }
            return;
          }

          // Only handle player swipe in collapsed mode with multiple players
          if (isExpanded || !hasMultiplePlayers) return;

          // Ignore drags that started in the edge dead zone
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          if (startedInDeadZone) return;

          _handleHorizontalDragUpdate(details, maProvider, collapsedWidth);
        },
        onHorizontalDragEnd: (details) {
          // Queue panel swipe is handled by QueuePanel's Listener (bypasses gesture arena)
          // End volume drag
          if (_isDraggingVolume) {
            // Send final volume on release
            maProvider.setVolume(selectedPlayer.playerId, (_dragVolumeLevel * 100).round());
            _lastVolumeDragEndTime = DateTime.now().millisecondsSinceEpoch; // Track for consecutive swipes
            _hasLocalVolumeOverride = true; // Mark that we have a local volume value
            _exitVolumePrecisionMode();
            _lastVolumeDragPosition = null;
            setState(() {
              _isDraggingVolume = false;
            });
            HapticFeedback.lightImpact();
            _horizontalDragStartX = null;
            return;
          }

          // Ignore swipes that started near the edges (Android back gesture zone)
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          _horizontalDragStartX = null;

          if (startedInDeadZone) return;

          if (!isExpanded && hasMultiplePlayers) {
            // Collapsed mode: use finger-following handler
            _handleHorizontalDragEnd(details, maProvider);
          }
        },
        onHorizontalDragCancel: () {
          // Reset state if gesture is cancelled (e.g., system takes over)
          _horizontalDragStartX = null;
          // Queue panel swipe is handled by QueuePanel's Listener
          if (_isDraggingVolume) {
            _exitVolumePrecisionMode();
            _lastVolumeDragPosition = null;
            setState(() => _isDraggingVolume = false);
          }
          if (_isDragging) {
            _isDragging = false;
            _slideOffset = 0.0;
            setState(() {
              _peekPlayer = null;
              _peekImageUrl = null;
              _peekTrack = null;
            });
          }
        },
        child: Container(
          // PERF Phase 4: Only show shadow when meaningfully visible (t < 0.5)
          // This avoids BoxDecoration allocation for majority of animation frames
          // Shadow fades out quickly during first half of expansion
          decoration: t < 0.5 ? BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: const [_miniPlayerShadow],
          ) : null,
          // Use foregroundDecoration for border so it renders ON TOP of content
          // This prevents the album art from clipping the yellow synced border
          foregroundDecoration: maProvider.isPlayerManuallySynced(selectedPlayer.playerId) && t < 0.5
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(color: _groupBorderColor, width: 1.5),
                )
              : null,
          child: Material(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(borderRadius),
            elevation: 0, // PERF Phase 3: Fixed elevation, shadow handled by Container
            // Use hardEdge when fully expanded (no border radius) to avoid anti-alias artifacts
            // Use antiAlias when collapsed/animating to smooth rounded corners
            clipBehavior: borderRadius > 0.5 ? Clip.antiAlias : Clip.hardEdge,
            child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Mini player progress bar background (collapsed only)
                // Shows played portion with brighter color, unplayed with darker
                // Starts after album art so progress is visible
                // Slides with content during swipe, hidden during transition if peek available
                // GPU PERF: Use conditional rendering + color alpha instead of Opacity
                // to avoid double saveLayer (Opacity + ClipRRect)
                if (t < 0.5 && currentTrack?.duration != null && !(_inTransition && t < 0.1 && _peekPlayer != null))
                  Positioned(
                      left: _collapsedArtSize + miniPlayerSlideOffset,
                      top: 0,
                      width: width - _collapsedArtSize,
                      bottom: 0,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _progressNotifier,
                        builder: (context, elapsedSeconds, _) {
                          final totalSeconds = currentTrack!.duration!.inSeconds;
                          if (totalSeconds <= 0) return const SizedBox.shrink();
                          final progress = (elapsedSeconds / totalSeconds).clamp(0.0, 1.0);
                          // Fade out as we expand - use color alpha instead of Opacity widget
                          final progressOpacity = (1.0 - (t / 0.5)).clamp(0.0, 1.0);
                          final progressAreaWidth = width - _collapsedArtSize;
                          // RepaintBoundary isolates frequent progress updates from parent animation
                          return RepaintBoundary(
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(borderRadius),
                                bottomRight: Radius.circular(borderRadius),
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: progressAreaWidth * progress,
                                  height: height,
                                  color: collapsedBg.withOpacity(progressOpacity),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                // Peek player content (shows when dragging OR during transition)
                // Show when: actively dragging (slideOffset != 0) OR in transition state
                // Must have peek data to render
                if (t < 0.1 && _peekPlayer != null && (_slideOffset.abs() > 0.01 || _inTransition))
                  _buildPeekContent(
                    context: context,
                    peekPlayer: _peekPlayer,
                    peekImageUrl: _peekImageUrl,
                    slideOffset: _slideOffset,
                    containerWidth: collapsedWidth,
                    backgroundColor: collapsedBg,
                    textColor: textColor,
                  ),

                // Album art - with slide animation when collapsed
                // Hidden during transition to prevent flash (peek content shows instead)
                // FALLBACK: Show main content if transition is active but peek content unavailable
                // This prevents showing only the progress bar with no content
                // GPU PERF: Use conditional instead of Opacity to avoid saveLayer
                // PERF Phase 4: Use Transform.translate for slide offset (GPU-accelerated)
                if (!(_inTransition && t < 0.1 && _peekPlayer != null))
                  Positioned(
                    left: artLeft,
                    top: artTop,
                    child: Transform.translate(
                      offset: Offset(miniPlayerSlideOffset, 0),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // Use onTapUp instead of onTap - resolves immediately and wins
                        // the gesture arena against the outer vertical drag detector
                        onTapUp: t > 0.5 ? (_) => _showFullscreenArt(context, imageUrl) : null,
                        child: Container(
                          width: artSize,
                          height: artSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(artBorderRadius),
                            // PERF Phase 4: Only show shadow when near-expanded (t > 0.7)
                            // Avoids BoxShadow allocation during most of animation
                            boxShadow: t > 0.7 ? const [_artShadowExpanded] : null,
                          ),
                          // Use RepaintBoundary to isolate art repaints during animation
                          child: RepaintBoundary(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(artBorderRadius),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  imageUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          fit: BoxFit.cover,
                                          // Fixed cache size to avoid mid-animation cache thrashing
                                          memCacheWidth: 512,
                                          memCacheHeight: 512,
                                          fadeInDuration: Duration.zero,
                                          fadeOutDuration: Duration.zero,
                                          placeholderFadeInDuration: Duration.zero,
                                          placeholder: (_, __) => _buildPlaceholderArt(colorScheme, t),
                                          errorWidget: (_, __, ___) => _buildPlaceholderArt(colorScheme, t),
                                        )
                                      : _buildPlaceholderArt(colorScheme, t),
                                  // Provider icon overlay (only show when expanded enough)
                                  if (t > 0.5 && currentTrack.providerMappings?.isNotEmpty == true)
                                    ProviderIconOverlay(
                                      domain: currentTrack.providerMappings!.first.providerDomain,
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
                  ),

                // Track title - with slide animation when collapsed
                // When hint is visible, show lightbulb icon + "Pull to select players"
                // When device reveal is visible, show player name instead of track name
                // Hidden during transition to prevent flash
                // FALLBACK: Show if transition active but no peek content available
                // GPU PERF: Use conditional instead of Opacity to avoid saveLayer
                // Hint text - vertically centered in mini player
                // PERF Phase 4: Use Transform.translate for slide offset (GPU-accelerated)
                if (widget.isHintVisible && t < 0.5 && !(_inTransition && t < 0.1 && _peekPlayer != null))
                  Positioned(
                    left: titleLeft,
                    // Center vertically: (64 - ~20) / 2 = 22
                    top: (MiniPlayerLayout.height - 20) / 2,
                    child: Transform.translate(
                      offset: Offset(miniPlayerSlideOffset, 0),
                      child: SizedBox(
                        width: titleWidth,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 16,
                              color: textColor,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                S.of(context)!.pullToSelectPlayers,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: titleFontSize,
                                  fontWeight: MiniPlayerLayout.primaryFontWeight,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Track title - with slide animation when collapsed
                // Hidden when hint is visible
                // Uses Align.lerp for smooth left-to-center transition (textAlign can't be animated)
                // PERF Phase 4: Use Transform.translate for slide offset (GPU-accelerated)
                if (!(widget.isHintVisible && t < 0.5) && !(_inTransition && t < 0.1 && _peekPlayer != null))
                  Positioned(
                    left: titleLeft,
                    top: titleTop,
                    child: Transform.translate(
                      offset: Offset(miniPlayerSlideOffset, 0),
                      child: SizedBox(
                        width: titleWidth,
                        child: Align(
                          // PERF Phase 5: Use pre-computed alignment
                          alignment: textAlignment,
                          child: Text(
                            currentTrack.name,
                            style: TextStyle(
                              color: textColor,
                              fontSize: titleFontSize,
                              // PERF Phase 5: Use pre-computed font weight
                              fontWeight: titleFontWeight,
                              // Lerp letter spacing smoothly (0 to -0.5)
                              letterSpacing: _lerpDouble(0, -0.5, t),
                              // Lerp line height smoothly (1.0 default to 1.2)
                              height: _lerpDouble(1.0, 1.2, t),
                            ),
                            textAlign: TextAlign.left, // Keep static, Align handles centering
                            // Use 1 line when collapsed to prevent overlap with artist line,
                            // expand to 2 lines during animation for long titles
                            maxLines: t > 0.3 ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Artist/Author name - with slide animation when collapsed
                // When hint is visible, show blank line
                // When device reveal is visible, show "Now Playing" hint
                // For audiobooks: show author from audiobook context
                // Hidden during transition to prevent flash
                // FALLBACK: Show if transition active but no peek content available
                // Uses Align.lerp for smooth left-to-center transition
                // PERF Phase 4: Use Transform.translate for slide offset (GPU-accelerated)
                if (!(_inTransition && t < 0.1 && _peekPlayer != null) && !(widget.isHintVisible && t < 0.5))
                  Positioned(
                    left: titleLeft,
                    top: artistTop,
                    child: Transform.translate(
                      offset: Offset(miniPlayerSlideOffset, 0),
                      child: SizedBox(
                        width: titleWidth,
                        child: Align(
                          // PERF Phase 5: Use pre-computed alignment
                          alignment: textAlignment,
                          child: GestureDetector(
                            onTap: t > 0.8 ? () => _navigateToArtist(maProvider, currentTrack) : null,
                            child: Text(
                              // Always show artist/author/podcast name (was showing "Now Playing" when device reveal visible)
                              maProvider.isPlayingAudiobook
                                  ? (maProvider.currentAudiobook?.authorsString ?? S.of(context)!.unknownAuthor)
                                  : maProvider.isPlayingPodcast
                                      ? (maProvider.currentPodcastName ?? S.of(context)!.podcasts)
                                      : currentTrack.artistsString,
                              style: TextStyle(
                                // PERF Phase 4: Use Color.lerp between pre-computed colors
                                color: Color.lerp(textColor60, textColor70, t),
                                fontSize: artistFontSize,
                              ),
                              textAlign: TextAlign.left, // Keep static, Align handles centering
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Player name - third line, fades out during first half of expansion
                // Uses staggered opacity: fully visible at t=0, fully faded at t=0.4
                // Position animates smoothly throughout
                // PERF Phase 4: Use Transform.translate for slide offset (GPU-accelerated)
                if (t < 0.5 && !(_inTransition && t < 0.1 && _peekPlayer != null) && !(widget.isHintVisible && t < 0.5))
                  Positioned(
                    left: titleLeft,
                    top: playerNameTop,
                    child: Transform.translate(
                      offset: Offset(miniPlayerSlideOffset, 0),
                      child: SizedBox(
                        width: titleWidth,
                        child: Align(
                          // PERF Phase 5: Use pre-computed alignment
                          alignment: textAlignment,
                          child: Text(
                            selectedPlayer.name,
                            style: TextStyle(
                              // Staggered fade: 1.0 at t=0, 0.0 at t=0.4
                              color: textColor.withOpacity((1.0 - t / 0.4).clamp(0.0, 1.0)),
                              fontSize: MiniPlayerLayout.tertiaryFontSize,
                            ),
                            textAlign: TextAlign.left, // Keep static, Align handles centering
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Album name OR Chapter name (expanded only)
                // GPU PERF: Use color alpha instead of Opacity widget
                // For audiobooks: show current chapter; for music: show album
                // For podcasts: hide album line since podcast name is already shown in artist position
                if (t > 0.3 && (currentTrack.album != null || maProvider.isPlayingAudiobook) && !maProvider.isPlayingPodcast)
                  Positioned(
                    left: contentPadding,
                    right: contentPadding,
                    top: _lerpDouble(artistTop + 24, expandedAlbumTop, t),
                    child: maProvider.isPlayingAudiobook
                        ? _buildChapterInfo(maProvider, textColor, t)
                        : GestureDetector(
                            onTap: t > 0.8 ? () => _navigateToAlbum(currentTrack) : null,
                            child: Text(
                              currentTrack.album!.name,
                              style: TextStyle(
                                color: textColor.withOpacity(0.45 * ((t - 0.3) / 0.7).clamp(0.0, 1.0)),
                                fontSize: 15,
                                fontWeight: FontWeight.w300,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                  ),

                // Audio source/format info (expanded only, when Sendspin active)
                // Shows "Playing from Sendspin" and audio format
                if (t > 0.5 && maProvider.isSendspinConnected)
                  Positioned(
                    left: contentPadding,
                    right: contentPadding,
                    top: expandedAlbumTop + (maProvider.isPlayingAudiobook ? 24 : (currentTrack.album != null ? 32 : 0)),
                    child: FadeTransition(
                      // PERF Phase 5: Use cached animation instead of creating new Tween every frame
                      opacity: _fadeIn50to100,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.graphic_eq_rounded,
                            size: 14,
                            color: primaryColor70, // PERF: Use cached color
                          ),
                          const SizedBox(width: 6),
                          Text(
                            maProvider.currentAudioFormat ?? S.of(context)!.pcmAudio,
                            style: TextStyle(
                              color: primaryColor70, // PERF: Use cached color
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Progress bar (expanded only)
                // GPU PERF: Use FadeTransition instead of Opacity
                if (t > 0.5 && currentTrack.duration != null)
                  Positioned(
                    left: contentPadding,
                    right: contentPadding,
                    top: expandedProgressTop,
                    child: FadeTransition(
                      // PERF Phase 5: Use cached animation instead of creating new Tween every frame
                      opacity: _fadeIn50to100,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _progressNotifier,
                        builder: (context, elapsedTime, child) {
                          return ValueListenableBuilder<double?>(
                            valueListenable: _seekPositionNotifier,
                            builder: (context, seekPosition, child) {
                              final currentProgress = seekPosition ?? elapsedTime.toDouble();
                              return Column(
                                children: [
                                  SizedBox(
                                    height: 48, // Increase touch target height
                                    child: _buildProgressSlider(
                                      context,
                                      currentProgress,
                                      currentTrack.duration!.inSeconds.toDouble(),
                                      primaryColor,
                                      primaryColor20,
                                      maProvider,
                                      selectedPlayer.playerId,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          formatDurationSeconds(currentProgress.toInt()),
                                          style: TextStyle(
                                            color: textColor50, // PERF: Use cached color
                                            fontSize: 13, // Increased from 11 to 13
                                            fontWeight: FontWeight.w500,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                        Text(
                                          formatDurationSeconds(currentTrack.duration!.inSeconds),
                                          style: TextStyle(
                                            color: textColor50, // PERF: Use cached color
                                            fontSize: 13, // Increased from 11 to 13
                                            fontWeight: FontWeight.w500,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                // Playback controls - with slide animation when collapsed
                // Uses curved interpolation to smoothly transition from right-aligned to centered
                // Use skip 30s controls for audiobooks and podcasts
                Positioned(
                  // Full width positioning, alignment handled by child Align widget
                  left: 0,
                  right: 0,
                  top: controlsTop,
                  child: (maProvider.isPlayingAudiobook || maProvider.isPlayingPodcast)
                      // When device reveal is visible (player list shown), use compact controls
                      // for audiobooks/podcasts: Play, Forward 30, Power
                      ? widget.isDeviceRevealVisible && t < 0.5
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Play/Pause - compact like PlayerCard
                                Transform.translate(
                                  offset: const Offset(3, 0),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: IconButton(
                                      icon: Icon(
                                        selectedPlayer.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: textColor,
                                        size: 28,
                                      ),
                                      onPressed: () => maProvider.playPauseSelectedPlayer(),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                // Forward 30 seconds
                                Transform.translate(
                                  offset: const Offset(6, 0),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.forward_30_rounded,
                                      color: textColor,
                                      size: 28,
                                    ),
                                    onPressed: () => maProvider.seekRelative(selectedPlayer.playerId, 30),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                                // Power button
                                IconButton(
                                  icon: Icon(
                                    Icons.power_settings_new_rounded,
                                    color: selectedPlayer.powered ? textColor : textColor50,
                                    size: 20,
                                  ),
                                  onPressed: () => maProvider.togglePower(selectedPlayer.playerId),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 4),
                              ],
                            )
                          : _buildAudiobookControls(
                              maProvider: maProvider,
                              selectedPlayer: selectedPlayer,
                              textColor: textColor,
                              primaryColor: primaryColor,
                              backgroundColor: backgroundColor,
                              skipButtonSize: skipButtonSize,
                              playButtonSize: playButtonSize,
                              playButtonContainerSize: playButtonContainerSize,
                              t: t,
                              expandedElementsOpacity: expandedElementsOpacity,
                            )
                      // When device reveal is visible (player list shown), use compact controls
                      // like PlayerCard: Play, Next, Power - matching other players in the list
                      : widget.isDeviceRevealVisible && t < 0.5
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Play/Pause - compact like PlayerCard
                                // Touch target increased to 44dp for accessibility
                                Transform.translate(
                                  offset: const Offset(3, 0),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: IconButton(
                                      icon: Icon(
                                        selectedPlayer.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: textColor,
                                        size: 28,
                                      ),
                                      onPressed: () => maProvider.playPauseSelectedPlayer(),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                // Skip next - nudged right like PlayerCard
                                Transform.translate(
                                  offset: const Offset(6, 0),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.skip_next_rounded,
                                      color: textColor,
                                      size: 28,
                                    ),
                                    onPressed: () => maProvider.nextTrackSelectedPlayer(),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                                // Power button - smallest, like PlayerCard
                                IconButton(
                                  icon: Icon(
                                    Icons.power_settings_new_rounded,
                                    color: selectedPlayer.powered ? textColor : textColor50,
                                    size: 20,
                                  ),
                                  onPressed: () => maProvider.togglePower(selectedPlayer.playerId),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 4),
                              ],
                            )
                          // Wrap in Align for smooth transition from right to center
                          : Align(
                    // Smooth alignment: lerp from right (1.0) to center (0.0)
                    alignment: Alignment.lerp(
                      Alignment(1.0 - (collapsedControlsRight / (width / 2)), 0), // Right with margin
                      Alignment.center,
                      t,
                    )!,
                    child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Shuffle - animate size from 0 to prevent jerk when appearing
                      // Always render but with animated width to smoothly grow into place
                      SizedBox(
                        width: _lerpDouble(0, 44, t), // Animate width from 0 to 44
                        height: 44,
                        child: t > 0.3 ? Opacity(
                          opacity: expandedElementsOpacity,
                          child: _buildSecondaryButton(
                            icon: Icons.shuffle_rounded,
                            color: _queue?.shuffle == true ? primaryColor : textColor50,
                            onPressed: _isLoadingQueue ? null : _toggleShuffle,
                          ),
                        ) : null,
                      ),
                      SizedBox(width: _lerpDouble(0, 20, t)),

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

                      // Repeat - animate size from 0 to prevent jerk when appearing
                      SizedBox(width: _lerpDouble(0, 20, t)),
                      SizedBox(
                        width: _lerpDouble(0, 44, t), // Animate width from 0 to 44
                        height: 44,
                        child: t > 0.3 ? Opacity(
                          opacity: expandedElementsOpacity,
                          child: _buildSecondaryButton(
                            icon: _queue?.repeatMode == 'one' ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                            color: _queue?.repeatMode != null && _queue!.repeatMode != 'off'
                                ? primaryColor
                                : textColor50,
                            onPressed: _isLoadingQueue ? null : _cycleRepeat,
                          ),
                        ) : null,
                      ),
                    ],
                  ),
                ),
                ),

                // Volume control (expanded only)
                // GPU PERF: Use FadeTransition instead of Opacity
                if (t > 0.5)
                  Positioned(
                    left: 48,
                    right: 48,
                    top: volumeTop,
                    child: FadeTransition(
                      // PERF Phase 5: Use cached animation instead of creating new Tween every frame
                      opacity: _fadeIn50to100,
                      child: VolumeControl(compact: false, accentColor: primaryColor),
                    ),
                  ),

                // Utility row - positioned from top like volume, rises with player expansion
                // Contains favourite, lyrics, queue, sleep buttons (alphabetical order)
                if (t > 0.5)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: utilityButtonsTop,
                    child: Opacity(
                      opacity: expandedElementsOpacity,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Favourite button
                          _buildUtilityButton(
                            icon: _isCurrentTrackFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            label: 'Favourite',
                            isActive: _isCurrentTrackFavorite,
                            activeColor: Colors.red,
                            textColor: textColor,
                            onPressed: () => _toggleCurrentTrackFavorite(currentTrack),
                          ),
                          // Lyrics button
                          _buildUtilityButton(
                            icon: Icons.lyrics_outlined,
                            label: 'Lyrics',
                            isActive: isLyricsPanelOpen,
                            activeColor: primaryColor,
                            textColor: textColor,
                            onPressed: _toggleLyricsPanel,
                          ),
                          // Queue button
                          _buildUtilityButton(
                            icon: Icons.queue_music_rounded,
                            label: 'Queue',
                            isActive: isQueuePanelOpen,
                            activeColor: primaryColor,
                            textColor: textColor,
                            onPressed: _toggleQueuePanel,
                          ),
                          // Sleep timer button
                          _buildUtilityButton(
                            icon: maProvider.sleepTimerActive ? Icons.timer : Icons.timer_outlined,
                            label: 'Sleep',
                            isActive: maProvider.sleepTimerActive || isSleepTimerPanelOpen,
                            activeColor: primaryColor,
                            textColor: textColor,
                            onPressed: _toggleSleepTimerPanel,
                          ),
                        ],
                      ),
                    ),
                  ),

                // Sleep timer panel - slides up from bottom (same mechanics as queue)
                if (t > 0.5)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _sleepTimerPanelController,
                      builder: (context, child) {
                        final progress = _sleepTimerPanelController.value;
                        // Use state variable for IgnorePointer (immediate response)
                        // Use animation value for Offstage (visual during animation)
                        return IgnorePointer(
                          ignoring: !_sleepTimerPanelVisible,
                          child: Offstage(
                            offstage: progress < 0.01 && !_sleepTimerPanelVisible,
                            child: child,
                          ),
                        );
                      },
                      child: GestureDetector(
                        onTap: _closeSleepTimerPanel, // Tap outside to close
                        behavior: HitTestBehavior.opaque,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: GestureDetector(
                            onTap: () {}, // Prevent tap from closing when tapping panel
                            onVerticalDragEnd: (details) {
                              // Swipe down to close (same logic as queue)
                              final velocity = details.primaryVelocity ?? 0;
                              if (velocity > 150) {
                                _closeSleepTimerPanel(velocity: velocity / 1000);
                              }
                            },
                            child: RepaintBoundary(
                              child: SlideTransition(
                                position: _sleepTimerSlideAnimation,
                                child: _buildSleepTimerPanel(maProvider, primaryColor, textColor, expandedBg, topPadding),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Lyrics panel - slides up from bottom (same mechanics as queue/sleep timer)
                if (t > 0.5)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _lyricsPanelController,
                      builder: (context, child) {
                        final progress = _lyricsPanelController.value;
                        return IgnorePointer(
                          ignoring: !_lyricsPanelVisible,
                          child: Offstage(
                            offstage: progress < 0.01 && !_lyricsPanelVisible,
                            child: child,
                          ),
                        );
                      },
                      child: GestureDetector(
                        onTap: _closeLyricsPanel, // Tap outside to close
                        behavior: HitTestBehavior.opaque,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: GestureDetector(
                            onTap: () {}, // Prevent tap from closing when tapping panel
                            behavior: HitTestBehavior.opaque, // Capture all touches in panel area
                            // Swipe down to close from header/non-scrollable areas
                            // Content area swipes are handled by Listener in _buildLyricsPanel
                            onVerticalDragEnd: (details) {
                              final velocity = details.primaryVelocity ?? 0;
                              if (velocity > 150) {
                                _closeLyricsPanel(velocity: velocity / 1000);
                              }
                            },
                            child: RepaintBoundary(
                              child: SlideTransition(
                                position: _lyricsSlideAnimation,
                                child: _buildLyricsPanel(maProvider, primaryColor, textColor, expandedBg, topPadding),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Collapse button (expanded only)
                // GPU PERF: Use icon color alpha instead of Opacity
                if (t > 0.3)
                  Positioned(
                    top: topPadding - 4,
                    left: 4,
                    child: IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: textColor.withOpacity(((t - 0.3) / 0.7).clamp(0.0, 1.0)),
                        size: 28,
                      ),
                      onPressed: collapse,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),

                // Player name (expanded only)
                // GPU PERF: Use text color alpha instead of Opacity
                if (t > 0.5)
                  Positioned(
                    top: topPadding + 6,
                    left: 56,
                    right: 56,
                    child: IgnorePointer(
                      child: Text(
                        selectedPlayer.name,
                        style: TextStyle(
                          color: textColor.withOpacity(0.6 * ((t - 0.5) / 0.5).clamp(0.0, 1.0)),
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Queue/Chapters panel (slides in from right)
                // For audiobooks: show chapters panel
                // For music: show queue panel
                // PERF: Own AnimatedBuilder - only rebuilds queue panel section on queue animation
                // Main player doesn't rebuild when queue slides in/out
                if (t > 0.5)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _queuePanelAnimation,
                      builder: (context, child) {
                        final queueProgress = _queuePanelAnimation.value;
                        return Offstage(
                          offstage: queueProgress == 0,
                          child: child,
                        );
                      },
                      // PERF: Child is not rebuilt - only Offstage wrapper updates
                      child: RepaintBoundary(
                        child: SlideTransition(
                          // PERF: Use cached animation instead of Tween.animate() every frame
                          position: _queueSlideAnimation,
                          child: maProvider.isPlayingAudiobook
                              ? ChaptersPanel(
                                  maProvider: maProvider,
                                  audiobook: maProvider.currentAudiobook,
                                  textColor: textColor,
                                  primaryColor: primaryColor,
                                  backgroundColor: expandedBg,
                                  topPadding: topPadding,
                                  onClose: _toggleQueuePanel,
                                )
                              : QueuePanel(
                                  maProvider: maProvider,
                                  queue: _queue,
                                  isLoading: _isLoadingQueue,
                                  textColor: textColor,
                                  primaryColor: primaryColor,
                                  backgroundColor: expandedBg,
                                  topPadding: topPadding,
                                  onClose: _toggleQueuePanel,
                                  onRefresh: _loadQueue,
                                  onDraggingChanged: (isDragging) {
                                    _isQueueDragging = isDragging;
                                  },
                                  onSwipeStart: () {
                                    // Haptic feedback when swipe gesture recognized
                                    HapticFeedback.selectionClick();
                                  },
                                  onSwipeUpdate: (_) {
                                    // No finger tracking - just wait for swipe end
                                    // This avoids jank from direct value manipulation
                                  },
                                  onSwipeEnd: (velocity, totalDy) {
                                    // Decide based on velocity and total vertical displacement
                                    final screenHeight = MediaQuery.of(context).size.height;
                                    final swipeProgress = totalDy / screenHeight;
                                    final shouldClose = velocity > 150 || swipeProgress > 0.15;

                                    if (shouldClose) {
                                      _closeQueuePanelWithSpring();
                                    }
                                    // If not closing, panel stays open (no snap-back needed since we didn't move it)
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),

                // Volume swipe overlay (covers entire mini player when dragging volume)
                // Only visible when device reveal is open and user is dragging
                // Positioned last in Stack so it renders ON TOP of all content
                // Uses AnimatedOpacity for smooth fade in/out transition
                if (t < 0.5)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_isDraggingVolume,
                      child: AnimatedOpacity(
                        opacity: _isDraggingVolume ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 120),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(borderRadius),
                          child: Stack(
                            children: [
                              // Unfilled (darker) background
                              Container(color: collapsedBgUnplayed),
                              // Filled (lighter) portion based on volume
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: _dragVolumeLevel.clamp(0.0, 1.0),
                                  heightFactor: 1.0,
                                  child: Container(color: collapsedBg),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  /// Build the peek player content that slides in from the edge during drag
  /// Uses shared MiniPlayerContent for consistency
  Widget _buildPeekContent({
    required BuildContext context,
    required dynamic peekPlayer,
    required String? peekImageUrl,
    required double slideOffset,
    required double containerWidth,
    required Color backgroundColor,
    required Color textColor,
  }) {
    // Calculate sliding position
    double peekBaseOffset;

    if (_inTransition && slideOffset.abs() < 0.01) {
      peekBaseOffset = 0.0;
    } else {
      final isFromRight = slideOffset < 0;
      final peekProgress = slideOffset.abs();
      peekBaseOffset = isFromRight
          ? containerWidth * (1 - peekProgress)
          : -containerWidth * (1 - peekProgress);
    }

    // Check if peek player has a track
    final hasTrack = _peekTrack != null && peekImageUrl != null;
    final peekTrackName = hasTrack ? _peekTrack!.name : (peekPlayer?.name ?? S.of(context)!.unknown);
    final peekArtistName = hasTrack ? (_peekTrack!.artistsString ?? '') : S.of(context)!.swipeToSwitchDevice;
    // Show player name as third line only when playing
    final peekPlayerName = hasTrack ? (peekPlayer?.name ?? '') : null;

    return Transform.translate(
      offset: Offset(peekBaseOffset, 0),
      child: MiniPlayerContent(
        primaryText: peekTrackName,
        secondaryText: peekArtistName,
        tertiaryText: peekPlayerName,
        imageUrl: hasTrack ? peekImageUrl : null,
        playerName: peekPlayer?.name ?? '',
        backgroundColor: backgroundColor,
        textColor: textColor,
        width: containerWidth,
        slideOffset: 0, // Transform handles positioning
      ),
    );
  }


  /// Build peek player progress bar that slides in during swipe
  Widget _buildPeekProgressBar({
    required double slideOffset,
    required bool inTransition,
    required double collapsedWidth,
    required double progressAreaWidth,
    required double height,
    required double borderRadius,
    required Color color,
  }) {
    // Calculate peek progress bar position (mirrors _buildPeekContent positioning)
    double peekProgressLeft;
    if (inTransition && slideOffset.abs() < 0.01) {
      peekProgressLeft = _collapsedArtSize;
    } else {
      final isFromRight = slideOffset < 0;
      final peekProgress = slideOffset.abs();
      peekProgressLeft = _collapsedArtSize + (isFromRight
          ? collapsedWidth * (1 - peekProgress)
          : -collapsedWidth * (1 - peekProgress));
    }

    // Get peek player's elapsed time - safely handle null/invalid values
    final peekElapsed = _peekPlayer?.currentElapsed ?? 0.0;
    final peekTotal = _peekTrack?.duration?.inSeconds ?? 0;
    if (peekTotal <= 0) return const SizedBox.shrink();
    final peekProgressValue = (peekElapsed / peekTotal).clamp(0.0, 1.0);

    return Positioned(
      left: peekProgressLeft,
      top: 0,
      width: progressAreaWidth,
      bottom: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(borderRadius),
          bottomRight: Radius.circular(borderRadius),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: progressAreaWidth * peekProgressValue,
            height: height,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderArt(ColorScheme colorScheme, double t) {
    // Use theme-aware colors for both collapsed and expanded states
    final expandedBgColor = colorScheme.surfaceContainerHighest;
    final expandedIconColor = colorScheme.onSurface.withOpacity(0.24);
    return Container(
      color: Color.lerp(colorScheme.surfaceVariant, expandedBgColor, t),
      child: Icon(
        Icons.music_note_rounded,
        color: Color.lerp(colorScheme.onSurfaceVariant, expandedIconColor, t),
        size: _lerpDouble(24, 120, t),
      ),
    );
  }

  /// Build chapter info display for audiobooks
  Widget _buildChapterInfo(MusicAssistantProvider maProvider, Color textColor, double t) {
    final chapter = maProvider.getCurrentChapter();
    final chapterIndex = maProvider.getCurrentChapterIndex();
    final totalChapters = maProvider.currentAudiobook?.chapters?.length ?? 0;

    if (chapter == null) {
      return const SizedBox.shrink();
    }

    final chapterText = totalChapters > 0
        ? 'Chapter ${chapterIndex + 1}/$totalChapters: ${chapter.title}'
        : chapter.title;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bookmark_outline_rounded,
          size: 14,
          color: textColor.withOpacity(0.45 * ((t - 0.3) / 0.7).clamp(0.0, 1.0)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            chapterText,
            style: TextStyle(
              color: textColor.withOpacity(0.45 * ((t - 0.3) / 0.7).clamp(0.0, 1.0)),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Build audiobook-specific playback controls
  /// Collapsed: [-30s] [Play/Pause] [+30s]
  /// Expanded: [Prev Chapter] [-30s] [-10s] [Play/Pause] [+10s] [+30s] [Next Chapter]
  Widget _buildAudiobookControls({
    required MusicAssistantProvider maProvider,
    required dynamic selectedPlayer,
    required Color textColor,
    required Color primaryColor,
    required Color backgroundColor,
    required double skipButtonSize,
    required double playButtonSize,
    required double playButtonContainerSize,
    required double t,
    required double expandedElementsOpacity,
  }) {
    final hasChapters = maProvider.currentAudiobook?.chapters?.isNotEmpty ?? false;
    final isExpanded = t > 0.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: isExpanded ? MainAxisAlignment.center : MainAxisAlignment.end,
      children: [
        // Previous Chapter (expanded only, if chapters available)
        if (isExpanded && expandedElementsOpacity > 0.1 && hasChapters)
          _buildSecondaryButton(
            icon: Icons.skip_previous_rounded,
            color: textColor.withOpacity(expandedElementsOpacity),
            onPressed: () => maProvider.seekToPreviousChapter(selectedPlayer.playerId),
          ),
        if (isExpanded && hasChapters) SizedBox(width: _lerpDouble(0, 12, t)),

        // Rewind 30 seconds
        _buildControlButton(
          icon: Icons.replay_30_rounded,
          color: textColor,
          size: skipButtonSize,
          onPressed: () => maProvider.seekRelative(selectedPlayer.playerId, -30),
          useAnimation: isExpanded,
        ),

        // Rewind 10 seconds (expanded only, same size as 30s)
        if (isExpanded) ...[
          SizedBox(width: _lerpDouble(0, 8, t)),
          _buildControlButton(
            icon: Icons.replay_10_rounded,
            color: textColor,
            size: skipButtonSize,
            onPressed: () => maProvider.seekRelative(selectedPlayer.playerId, -10),
            useAnimation: true,
          ),
        ],
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

        // Forward 10 seconds (expanded only, same size as 30s)
        if (isExpanded) ...[
          _buildControlButton(
            icon: Icons.forward_10_rounded,
            color: textColor,
            size: skipButtonSize,
            onPressed: () => maProvider.seekRelative(selectedPlayer.playerId, 10),
            useAnimation: true,
          ),
          SizedBox(width: _lerpDouble(0, 8, t)),
        ],

        // Forward 30 seconds
        _buildControlButton(
          icon: Icons.forward_30_rounded,
          color: textColor,
          size: skipButtonSize,
          onPressed: () => maProvider.seekRelative(selectedPlayer.playerId, 30),
          useAnimation: isExpanded,
        ),

        // Next Chapter (expanded only, if chapters available)
        if (isExpanded && hasChapters) SizedBox(width: _lerpDouble(0, 12, t)),
        if (isExpanded && expandedElementsOpacity > 0.1 && hasChapters)
          _buildSecondaryButton(
            icon: Icons.skip_next_rounded,
            color: textColor.withOpacity(expandedElementsOpacity),
            onPressed: () => maProvider.seekToNextChapter(selectedPlayer.playerId),
          ),
      ],
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
      child: AnimatedIconButton(
        icon: icon,
        color: color,
        iconSize: 22,
        onPressed: onPressed,
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

  Widget _buildUtilityButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required Color textColor,
    required VoidCallback onPressed,
  }) {
    final color = isActive ? activeColor : textColor.withOpacity(0.7);
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepTimerPanel(MusicAssistantProvider maProvider, Color primaryColor, Color textColor, Color backgroundColor, double topPadding) {
    final remaining = maProvider.sleepTimerRemaining;
    final currentMinutes = maProvider.sleepTimerMinutes;

    // Format remaining time
    String? remainingText;
    if (remaining != null && currentMinutes != -1) {
      final mins = remaining.inMinutes;
      final secs = remaining.inSeconds % 60;
      if (mins > 0) {
        remainingText = '$mins:${secs.toString().padLeft(2, '0')} remaining';
      } else {
        remainingText = '$secs sec remaining';
      }
    } else if (currentMinutes == -1) {
      remainingText = 'Will stop after this track';
    }

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with handle and close button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor, size: 28),
                    onPressed: _closeSleepTimerPanel,
                    padding: const EdgeInsets.all(8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sleep Timer',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (remainingText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        remainingText,
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Timer options as list tiles
            _buildTimerOption(maProvider, 'Off', null, primaryColor, textColor),
            _buildTimerOption(maProvider, '15 minutes', 15, primaryColor, textColor),
            _buildTimerOption(maProvider, '30 minutes', 30, primaryColor, textColor),
            _buildTimerOption(maProvider, '45 minutes', 45, primaryColor, textColor),
            _buildTimerOption(maProvider, '1 hour', 60, primaryColor, textColor),
            _buildTimerOption(maProvider, '2 hours', 120, primaryColor, textColor),
            _buildTimerOption(maProvider, 'End of track', -1, primaryColor, textColor),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerOption(MusicAssistantProvider maProvider, String label, int? minutes, Color primaryColor, Color textColor) {
    final currentMinutes = maProvider.sleepTimerMinutes;
    final isSelected = currentMinutes == minutes;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? primaryColor : textColor,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: primaryColor, size: 24)
          : null,
      onTap: () {
        maProvider.setSleepTimer(minutes);
        _closeSleepTimerPanel();
      },
    );
  }

  Widget _buildLyricsPanel(MusicAssistantProvider maProvider, Color primaryColor, Color textColor, Color backgroundColor, double topPadding) {
    final currentTrack = maProvider.currentTrack;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.7, // 70% of screen height
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header (matches queue and sleep timer style)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor, size: 28),
                    onPressed: _closeLyricsPanel,
                    padding: const EdgeInsets.all(8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Lyrics',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 16),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(color: textColor.withOpacity(0.1), height: 1),
            // Lyrics content
            Expanded(
              child: _isLoadingLyrics
                  ? Center(
                      child: CircularProgressIndicator(
                        color: primaryColor,
                        strokeWidth: 2,
                      ),
                    )
                  : _currentLyrics != null
                      ? _hasSyncedLyrics
                          // Synced lyrics - show as list with highlighting
                          // Wrapped with Listener for swipe-to-close when scrolled to top
                          ? Listener(
                              onPointerDown: (event) {
                                _lyricsSwipeStart = event.position;
                                _wasLyricsAtTopOnSwipeStart = _isLyricsAtTop;
                              },
                              onPointerMove: (event) {
                                if (_lyricsSwipeStart == null) return;
                                final dy = event.position.dy - _lyricsSwipeStart!.dy;
                                final dx = (event.position.dx - _lyricsSwipeStart!.dx).abs();
                                // Only trigger swipe-to-close if at top when started and swiping down
                                if (dy > 20 && dy > dx * 1.5 && _wasLyricsAtTopOnSwipeStart && !_isSwipingLyricsContent) {
                                  _isSwipingLyricsContent = true;
                                }
                              },
                              onPointerUp: (event) {
                                if (_isSwipingLyricsContent && _lyricsSwipeStart != null) {
                                  final dy = event.position.dy - _lyricsSwipeStart!.dy;
                                  if (dy > 50) {
                                    // Calculate velocity (simplified)
                                    final velocity = dy / 200; // Approximate velocity
                                    _closeLyricsPanel(velocity: velocity);
                                  }
                                }
                                _lyricsSwipeStart = null;
                                _isSwipingLyricsContent = false;
                              },
                              onPointerCancel: (_) {
                                _lyricsSwipeStart = null;
                                _isSwipingLyricsContent = false;
                              },
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  // Detect user scrolling to pause auto-scroll
                                  if (notification is ScrollStartNotification &&
                                      notification.dragDetails != null) {
                                    _userScrollingLyrics = true;
                                  } else if (notification is ScrollEndNotification) {
                                    // Resume auto-scroll after a delay
                                    Future.delayed(const Duration(seconds: 3), () {
                                      if (mounted) _userScrollingLyrics = false;
                                    });
                                  }
                                  return false;
                                },
                                child: ListView.builder(
                                  controller: _lyricsScrollController,
                                  padding: const EdgeInsets.only(top: 16, bottom: 100, left: 24, right: 24),
                                  itemCount: _parsedLyrics!.length,
                                  itemBuilder: (context, index) {
                                    final line = _parsedLyrics![index];
                                    final isActive = index == _currentLyricIndex;
                                    final isPast = index < _currentLyricIndex;

                                    return GestureDetector(
                                      onTap: () {
                                        // Tap to seek to this line
                                        final maProvider = context.read<MusicAssistantProvider>();
                                        final player = maProvider.selectedPlayer;
                                        if (player != null) {
                                          maProvider.api?.seek(player.playerId, line.timestamp.inSeconds);
                                        }
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        child: Text(
                                          line.text,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: isActive
                                                ? primaryColor
                                                : isPast
                                                    ? textColor.withOpacity(0.4)
                                                    : textColor.withOpacity(0.7),
                                            fontSize: isActive ? 20 : 18,
                                            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            )
                          // Plain lyrics - show as scrollable text
                          // Wrapped with Listener for swipe-to-close (always at "top" for plain text)
                          : Listener(
                              onPointerDown: (event) {
                                _lyricsSwipeStart = event.position;
                                _wasLyricsAtTopOnSwipeStart = true; // Plain lyrics always count as at top
                              },
                              onPointerMove: (event) {
                                if (_lyricsSwipeStart == null) return;
                                final dy = event.position.dy - _lyricsSwipeStart!.dy;
                                final dx = (event.position.dx - _lyricsSwipeStart!.dx).abs();
                                // Only trigger swipe-to-close if swiping down
                                if (dy > 20 && dy > dx * 1.5 && _wasLyricsAtTopOnSwipeStart && !_isSwipingLyricsContent) {
                                  _isSwipingLyricsContent = true;
                                }
                              },
                              onPointerUp: (event) {
                                if (_isSwipingLyricsContent && _lyricsSwipeStart != null) {
                                  final dy = event.position.dy - _lyricsSwipeStart!.dy;
                                  if (dy > 50) {
                                    // Calculate velocity (simplified)
                                    final velocity = dy / 200; // Approximate velocity
                                    _closeLyricsPanel(velocity: velocity);
                                  }
                                }
                                _lyricsSwipeStart = null;
                                _isSwipingLyricsContent = false;
                              },
                              onPointerCancel: (_) {
                                _lyricsSwipeStart = null;
                                _isSwipingLyricsContent = false;
                              },
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _currentLyrics!,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                    height: 1.8,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lyrics_outlined,
                                  color: textColor.withOpacity(0.3),
                                  size: 64,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No lyrics available',
                                  style: TextStyle(
                                    color: textColor.withOpacity(0.5),
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Lyrics may not be available for this track',
                                  style: TextStyle(
                                    color: textColor.withOpacity(0.3),
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Custom progress slider that doesn't require Overlay widget
  /// (Flutter 3.38's Material 3 Slider uses OverlayPortal which fails in our overlay context)
  Widget _buildProgressSlider(
    BuildContext context,
    double currentProgress,
    double maxProgress,
    Color activeColor,
    Color inactiveColor,
    MusicAssistantProvider maProvider,
    String playerId,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final progress = maxProgress > 0 ? (currentProgress / maxProgress).clamp(0.0, 1.0) : 0.0;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            final newProgress = (details.localPosition.dx / width).clamp(0.0, 1.0);
            _seekPositionNotifier.value = newProgress * maxProgress;
          },
          onHorizontalDragUpdate: (details) {
            final newProgress = (details.localPosition.dx / width).clamp(0.0, 1.0);
            _seekPositionNotifier.value = newProgress * maxProgress;
          },
          onHorizontalDragCancel: () {
            _seekPositionNotifier.value = null;
          },
          onHorizontalDragEnd: (details) async {
            final seekPosition = _seekPositionNotifier.value;
            if (seekPosition != null && !_isSeeking) {
              _isSeeking = true;
              try {
                await maProvider.seek(playerId, seekPosition.round());
                // Wait for server to process seek before allowing another
                await Future.delayed(const Duration(milliseconds: 1500));
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(S.of(context)!.errorSeeking(e.toString()))),
                  );
                }
              } finally {
                _isSeeking = false;
                if (mounted) {
                  _seekPositionNotifier.value = null;
                }
              }
            }
          },
          onTapUp: (details) async {
            if (_isSeeking) return; // Ignore if already seeking

            // Calculate position from tap location
            final newProgress = (details.localPosition.dx / width).clamp(0.0, 1.0);
            final seekPosition = newProgress * maxProgress;
            _seekPositionNotifier.value = seekPosition;
            _isSeeking = true;

            try {
              await maProvider.seek(playerId, seekPosition.round());
              // Wait for server to process seek before allowing another
              await Future.delayed(const Duration(milliseconds: 1500));
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(S.of(context)!.errorSeeking(e.toString()))),
                );
              }
            } finally {
              _isSeeking = false;
              if (mounted) {
                _seekPositionNotifier.value = null;
              }
            }
          },
          child: SizedBox(
            height: 48,
            child: Center(
              child: SizedBox(
                height: 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Inactive track (full width, thinner)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 8.5,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: inactiveColor,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ),
                    // Active track
                    Positioned(
                      left: 0,
                      top: 7,
                      child: Container(
                        width: width * progress,
                        height: 6,
                        decoration: BoxDecoration(
                          color: activeColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    // Thumb
                    Positioned(
                      left: (width * progress) - 7,
                      top: 3,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: activeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Represents a single line of synced lyrics with timestamp
class _LyricLine {
  final Duration timestamp;
  final String text;

  const _LyricLine({required this.timestamp, required this.text});
}
