import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/navigation_provider.dart';
import '../services/settings_service.dart';

import 'expandable_player.dart';
import 'player/mini_player_content.dart' show MiniPlayerLayout;
import 'player/player_reveal_overlay.dart';

/// A global key to access the player state from anywhere in the app
final globalPlayerKey = GlobalKey<ExpandablePlayerState>();

/// Key for the overlay state to control visibility
final _overlayStateKey = GlobalKey<_GlobalPlayerOverlayState>();

/// Constants for bottom UI elements spacing
class BottomSpacing {
  /// Height of the bottom navigation bar
  static const double navBarHeight = 56.0;

  /// Height of mini player when visible (height + 12px margin)
  static double get miniPlayerHeight => MiniPlayerLayout.height + 12.0;

  /// Space needed when only nav bar is visible (with some extra padding)
  static const double navBarOnly = navBarHeight + 16.0;

  /// Space needed when mini player is also visible
  static double get withMiniPlayer => navBarHeight + miniPlayerHeight + 22.0;
}

/// ValueNotifier for player expansion progress (0.0 to 1.0) and colors
class PlayerExpansionState {
  final double progress;
  final Color? backgroundColor;
  final Color? primaryColor;
  PlayerExpansionState(this.progress, this.backgroundColor, this.primaryColor);
}
final playerExpansionNotifier = ValueNotifier<PlayerExpansionState>(PlayerExpansionState(0.0, null, null));

/// Wrapper widget that provides a global player overlay above all navigation.
///
/// This ensures the mini player and expanded player are consistent across
/// all screens (home, library, album details, artist details, etc.) without
/// needing separate player instances in each screen.
class GlobalPlayerOverlay extends StatefulWidget {
  final Widget child;

  GlobalPlayerOverlay({
    required this.child,
  }) : super(key: _overlayStateKey);

  @override
  State<GlobalPlayerOverlay> createState() => _GlobalPlayerOverlayState();

  /// Collapse the player if it's expanded
  /// [withHaptic]: Set to false for Android back gesture (system provides haptic)
  static void collapsePlayer({bool withHaptic = true}) {
    globalPlayerKey.currentState?.collapse(withHaptic: withHaptic);
  }

  /// Force collapse player to mini state, instantly closing queue panel if open.
  /// Used for queue transfer where we want to go directly to mini player.
  static void forceCollapsePlayer() {
    globalPlayerKey.currentState?.forceCollapse();
  }

  /// Check if the player is currently expanded
  static bool get isPlayerExpanded =>
      globalPlayerKey.currentState?.isExpanded ?? false;

  /// Check if the queue panel is currently open (animation value > 0.5)
  static bool get isQueuePanelOpen =>
      globalPlayerKey.currentState?.isQueuePanelOpen ?? false;

  /// Check if the queue panel is intended to be open (target state)
  /// Use this for back gesture handling to avoid timing issues during animations
  static bool get isQueuePanelTargetOpen =>
      globalPlayerKey.currentState?.isQueuePanelTargetOpen ?? false;

  /// Close the queue panel if open
  /// [withHaptic]: Set to false for Android back gesture (system provides haptic)
  static void closeQueuePanel({bool withHaptic = true}) {
    globalPlayerKey.currentState?.closeQueuePanel(withHaptic: withHaptic);
  }

  /// Get the current expansion progress (0.0 to 1.0)
  static double get expansionProgress =>
      globalPlayerKey.currentState?.expansionProgress ?? 0.0;

  /// Get the current expanded background color
  static Color? get expandedBackgroundColor =>
      globalPlayerKey.currentState?.currentExpandedBgColor;

  /// Hide the mini player temporarily (e.g., when showing device selector)
  /// The player slides down off-screen with animation
  static void hidePlayer() {
    _overlayStateKey.currentState?._setHidden(true);
  }

  /// Show the mini player again (slides back up)
  static void showPlayer() {
    _overlayStateKey.currentState?._setHidden(false);
  }

  /// Show the player reveal overlay with bounce animation
  static void showPlayerReveal() {
    _overlayStateKey.currentState?._showPlayerReveal();
  }

  /// Hide the player reveal overlay (no animation - used as callback from overlay)
  static void hidePlayerReveal() {
    _overlayStateKey.currentState?._hidePlayerReveal();
  }

  /// Dismiss the player reveal overlay with animation (for back gesture)
  static void dismissPlayerReveal() {
    _overlayStateKey.currentState?._dismissPlayerReveal();
  }

  /// Trigger single bounce on mini player (called when device selector collapses)
  static void triggerBounce() {
    _overlayStateKey.currentState?._triggerBounce();
  }

  /// Check if the player reveal is currently visible
  static bool get isPlayerRevealVisible =>
      _overlayStateKey.currentState?._isRevealVisible ?? false;

  /// Show player selector for a "Play On" action.
  /// Instead of the default hints, shows a contextual hint like "Select player to play album".
  /// When a player is tapped, calls onPlayerSelected instead of switching to that player.
  static void showPlayerSelectorForAction({
    required String contextHint,
    required void Function(dynamic player) onPlayerSelected,
    IconData? hintIcon,
  }) {
    _overlayStateKey.currentState?._showPlayerSelectorForAction(
      contextHint: contextHint,
      onPlayerSelected: onPlayerSelected,
      hintIcon: hintIcon,
    );
  }
}

class _GlobalPlayerOverlayState extends State<GlobalPlayerOverlay>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  // Single bounce controller for device selector expand/collapse
  late AnimationController _singleBounceController;

  // Double bounce controller for hint
  late AnimationController _doubleBounceController;

  // State for player reveal overlay
  bool _isRevealVisible = false;

  // State for interactive hint mode (blur backdrop + wait for user action)
  bool _isHintModeActive = false;
  Timer? _hintBounceTimer;

  // Track if player reveal was triggered from onboarding (for showing extra hints)
  bool _isOnboardingReveal = false;

  // Bounce offset for mini player (used by both single and double bounce)
  final _bounceOffsetNotifier = ValueNotifier<double>(0.0);

  // Hint system state
  // NOTE: AppStartup now handles the settings loading gate. It waits for:
  // - First-time users: connected + player selected before showing HomeScreen
  // - Returning users: connected before showing HomeScreen
  // This eliminates the race condition that caused home screen flash.
  bool _showHints = true;
  bool _hasCompletedOnboarding = false; // First-use welcome screen
  bool _hintTriggered = false; // Prevent multiple triggers per session
  bool _settingsLoaded = false; // True once settings have been loaded from storage
  bool _miniPlayerHintsReady = false; // True once connected with player (can show hints)
  final _hintOpacityNotifier = ValueNotifier<double>(0.0);

  // Welcome content fade-in animation
  late AnimationController _welcomeFadeController;

  // Key for the reveal overlay
  final _revealKey = GlobalKey<PlayerRevealOverlayState>();

  // State for "Play On" action - stored here so it can be passed to PlayerRevealOverlay
  void Function(dynamic player)? _pendingPlayerAction;
  String? _pendingContextHint;
  IconData? _pendingHintIcon;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Single bounce for device selector expand/collapse
    _singleBounceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _singleBounceController.addListener(() {
      final t = Curves.easeOut.transform(_singleBounceController.value);
      // Single bounce: up to 10px then back to 0
      if (t < 0.5) {
        _bounceOffsetNotifier.value = 10.0 * (t * 2);           // 0 -> 10
      } else {
        _bounceOffsetNotifier.value = 10.0 * ((1.0 - t) * 2);   // 10 -> 0
      }
    });

    // Hint bounce - single gentle bounce to draw attention
    _doubleBounceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _doubleBounceController.addListener(() {
      final t = Curves.easeOut.transform(_doubleBounceController.value);
      // Single bounce: up 20px then back down
      if (t < 0.5) {
        _bounceOffsetNotifier.value = 20.0 * (t * 2);           // 0 -> 20
      } else {
        _bounceOffsetNotifier.value = 20.0 * ((1.0 - t) * 2);   // 20 -> 0
      }
    });

    // Welcome content fade-in
    _welcomeFadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Load hint settings and start welcome immediately if needed
    _loadHintSettings();
  }

  Future<void> _loadHintSettings() async {
    _showHints = await SettingsService.getShowHints();
    _hasCompletedOnboarding = await SettingsService.getHasCompletedOnboarding();
    if (!mounted) return;

    setState(() {
      _settingsLoaded = true;
    });

    // If first-time user and already connected (AppStartup waited for us),
    // start welcome screen immediately - no race condition possible
    if (!_hasCompletedOnboarding && !_hintTriggered) {
      final provider = context.read<MusicAssistantProvider>();
      if (provider.isConnected && provider.selectedPlayer != null) {
        _miniPlayerHintsReady = true;
        _startWelcomeScreen();
        _startMiniPlayerBounce();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if we should enable mini player hints now that we have connection
    _checkConnectionForMiniPlayerHints();
  }

  /// Check connection state and start welcome screen if appropriate.
  /// This is called from multiple places:
  /// 1. didChangeDependencies() - when widget first builds
  /// 2. _loadHintSettings() - when settings finish loading
  /// 3. build() - when provider state changes (via post-frame callback)
  void _checkConnectionForMiniPlayerHints() {
    if (_hintTriggered || !mounted || !_settingsLoaded) return;
    if (_hasCompletedOnboarding) return; // Not first-time user

    final provider = context.read<MusicAssistantProvider>();
    if (provider.isConnected && provider.selectedPlayer != null) {
      // Connected with a player - start welcome screen now
      _miniPlayerHintsReady = true;
      _startWelcomeScreen();
      // Start the bounce animation now that mini player is visible
      _startMiniPlayerBounce();
    }
  }

  /// Start the bounce animation for mini player hints
  void _startMiniPlayerBounce() {
    if (!_isHintModeActive || !mounted) return;
    _doubleBounceController.reset();
    _doubleBounceController.forward();

    // Repeat bounce every 2 seconds
    _hintBounceTimer?.cancel();
    _hintBounceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isHintModeActive && mounted) {
        _doubleBounceController.reset();
        _doubleBounceController.forward();
      }
    });
  }

  /// Start the welcome screen with fade-in animation
  void _startWelcomeScreen() {
    if (_hintTriggered) return;
    _hintTriggered = true;

    // Activate hint mode immediately (blur backdrop visible)
    setState(() {
      _isHintModeActive = true;
    });

    // Fade in welcome content (logo + title)
    _welcomeFadeController.forward();

    // Mini player bounce is started separately once connected via _startMiniPlayerBounce()
  }

  @override
  void dispose() {
    _hintBounceTimer?.cancel();
    _slideController.dispose();
    _singleBounceController.dispose();
    _doubleBounceController.dispose();
    _welcomeFadeController.dispose();
    _bounceOffsetNotifier.dispose();
    _hintOpacityNotifier.dispose();
    super.dispose();
  }

  void _setHidden(bool hidden) {
    if (hidden) {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
  }

  void _showPlayerReveal() {
    if (_isRevealVisible) return;
    if (GlobalPlayerOverlay.isPlayerExpanded) {
      GlobalPlayerOverlay.collapsePlayer();
    }
    HapticFeedback.mediumImpact();

    // Track if coming from hint mode (for onboarding hints in player selector)
    final wasInHintMode = _isHintModeActive;

    // End hint mode if active (user learned the gesture!)
    _hintBounceTimer?.cancel();
    _hintBounceTimer = null;
    _hintOpacityNotifier.value = 0.0;
    _isHintModeActive = false;

    // Mark onboarding as completed if coming from welcome screen
    if (wasInHintMode) {
      SettingsService.setHasCompletedOnboarding(true);
    }

    // Trigger single bounce on expand
    _singleBounceController.reset();
    _singleBounceController.forward();

    setState(() {
      _isRevealVisible = true;
      _isOnboardingReveal = wasInHintMode;
    });
  }

  void _hidePlayerReveal() {
    if (!_isRevealVisible) return;
    _bounceOffsetNotifier.value = 0;
    _clearPendingAction(); // Clear pending action when overlay is dismissed
    setState(() {
      _isRevealVisible = false;
      _isOnboardingReveal = false;
    });
  }

  /// Dismiss with animation (for back gesture) - calls overlay's dismiss method
  void _dismissPlayerReveal() {
    if (!_isRevealVisible) return;
    // Call the overlay's dismiss method which has the slide animation
    _revealKey.currentState?.dismiss();
  }

  /// Trigger single bounce on mini player (called when device selector collapses)
  void _triggerBounce() {
    _singleBounceController.reset();
    _singleBounceController.forward();
  }

  /// Clear pending action state (called when overlay is dismissed)
  void _clearPendingAction() {
    _pendingPlayerAction = null;
    _pendingContextHint = null;
    _pendingHintIcon = null;
  }

  /// Show player selector for a "Play On" action.
  /// Stores the pending action and shows the reveal overlay with context hint.
  void _showPlayerSelectorForAction({
    required String contextHint,
    required void Function(dynamic player) onPlayerSelected,
    IconData? hintIcon,
  }) {
    // Store pending action state
    _pendingPlayerAction = onPlayerSelected;
    _pendingContextHint = contextHint;
    _pendingHintIcon = hintIcon;

    // Show the reveal overlay
    _showPlayerReveal();
  }

  /// End hint mode (called when user taps skip button)
  void _endHintMode() {
    if (!_isHintModeActive) return;
    _hintBounceTimer?.cancel();
    _hintBounceTimer = null;
    _hintOpacityNotifier.value = 0.0;
    _bounceOffsetNotifier.value = 0.0;
    // Mark onboarding as completed (first use only)
    SettingsService.setHasCompletedOnboarding(true);
    setState(() {
      _isHintModeActive = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // PERF: Use select() to only rebuild when connection state or player changes
    final (isConnected, hasSelectedPlayer) = context.select<MusicAssistantProvider, (bool, bool)>(
      (p) => (p.isConnected, p.selectedPlayer != null),
    );

    // Compute whether this is a first-time user ready for welcome screen.
    // This is SYNCHRONOUS - no setState needed - so it works in the same frame.
    final isFirstTimeUserReady = _settingsLoaded &&
        !_hasCompletedOnboarding &&
        isConnected &&
        hasSelectedPlayer;

    // Show welcome backdrop if:
    // 1. Already in hint mode (_isHintModeActive), OR
    // 2. First-time user ready but hint mode not started yet (!_hintTriggered)
    // This ensures backdrop appears IMMEDIATELY when HomeScreen renders,
    // preventing the flash. Welcome content fades in after via animation.
    final shouldShowWelcomeBackdrop = _isHintModeActive ||
        (isFirstTimeUserReady && !_hintTriggered);

    // Trigger hint mode if conditions are met (for animations, bounce, etc)
    if (isFirstTimeUserReady && !_hintTriggered) {
      // Schedule for post-frame to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hintTriggered) {
          _miniPlayerHintsReady = true;
          _startWelcomeScreen();
          _startMiniPlayerBounce();
        }
      });
    }

    // Handle back gesture at top level - dismiss hint mode or device list if visible
    return PopScope(
      canPop: !_isRevealVisible && !_isHintModeActive,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_isHintModeActive) {
            _endHintMode();
          } else if (_isRevealVisible) {
            _dismissPlayerReveal();
          }
        }
      },
      child: Stack(
      children: [
        // The main app content (Navigator, screens, etc.)
        // Add bottom padding to account for bottom nav + mini player
        Padding(
          padding: const EdgeInsets.only(bottom: 0), // Content manages its own padding
          child: widget.child,
        ),
        // BottomNavigationBar is now in HomeScreen's Scaffold.bottomNavigationBar
        // for proper Navigator/Overlay ancestry

        // Blur backdrop for device selector (reveal mode) - static, no animation
        if (_isRevealVisible && !_isHintModeActive)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissPlayerReveal,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                child: Container(
                  color: colorScheme.surface.withOpacity(0.5),
                ),
              ),
            ),
          ),

        // Welcome/hint backdrop - shows IMMEDIATELY when first-time user is ready.
        // Uses computed `shouldShowWelcomeBackdrop` which is true BEFORE _isHintModeActive,
        // preventing the 1-frame gap where home screen would be visible.
        if (shouldShowWelcomeBackdrop)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              // Hold solid for 2s, then fade to 0.5 over 1s
              tween: Tween<double>(begin: 1.0, end: 0.5),
              duration: const Duration(seconds: 3),
              curve: const Interval(0.67, 1.0, curve: Curves.easeOut),
              builder: (context, opacity, child) {
                // Use theme-appropriate background color for seamless transition
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final backdropColor = isDark
                    ? const Color(0xFF1a1a1a)  // Dark theme background
                    : colorScheme.surface;      // Light theme surface
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                  child: Container(
                    color: backdropColor.withOpacity(opacity),
                  ),
                );
              },
            ),
          ),

        // Welcome message during hint mode - two positioned sections with fade-in
        // Top section: Logo and Welcome title (stays fixed at top area)
        if (_isHintModeActive)
          Positioned(
            left: 24,
            right: 24,
            // Position logo section high up - about 1/3 from top
            top: MediaQuery.of(context).size.height * 0.15,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _welcomeFadeController,
                curve: Curves.easeOut,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ensemble logo - same as settings screen
                  Image.asset(
                    'assets/images/ensemble_icon_transparent.png',
                    width: MediaQuery.of(context).size.width * 0.5,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 24),
                  // Welcome title
                  Text(
                    S.of(context)!.welcomeToEnsemble,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

        // Bottom section: Hint text and Skip button (only show once mini player is visible)
        if (_isHintModeActive && _miniPlayerHintsReady)
          Positioned(
            left: 24,
            right: 24,
            // Position so skip button is ~32px above mini player, matching skip-to-miniplayer gap
            // Use viewPadding to match BottomNavigationBar's height calculation
            bottom: BottomSpacing.navBarHeight + BottomSpacing.miniPlayerHeight + MediaQuery.of(context).viewPadding.bottom + 32,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _welcomeFadeController,
                curve: Curves.easeOut,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Hint text
                  Text(
                    S.of(context)!.welcomeMessage,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  // Skip button - same gap above as below to mini player
                  TextButton(
                    onPressed: _endHintMode,
                    child: Text(
                      S.of(context)!.skip,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Player reveal overlay - renders BELOW mini player so cards slide behind it
        if (_isRevealVisible)
          PlayerRevealOverlay(
            key: _revealKey,
            onDismiss: _hidePlayerReveal,
            // Use viewPadding to match BottomNavigationBar's height calculation
            miniPlayerBottom: BottomSpacing.navBarHeight + MediaQuery.of(context).viewPadding.bottom + 12,
            miniPlayerHeight: 64,
            showOnboardingHints: _isOnboardingReveal,
            // Pass pending action parameters for "Play On" functionality
            onPlayerSelected: _pendingPlayerAction,
            contextHint: _pendingContextHint,
            contextHintIcon: _pendingHintIcon,
          ),

        // Global player overlay - renders ON TOP so cards slide behind it
        // Use Selector instead of Consumer to avoid rebuilds during animation
        Selector<MusicAssistantProvider, ({bool isConnected, bool hasPlayer, bool hasTrack})>(
          selector: (_, provider) => (
            isConnected: provider.isConnected,
            hasPlayer: provider.selectedPlayer != null,
            hasTrack: provider.currentTrack != null,
          ),
          builder: (context, state, child) {
            // Only show player if connected and has a selected player
            if (!state.isConnected || !state.hasPlayer) {
              // Reset expansion state to prevent stale values from causing
              // invisible/non-interactive nav bar when connection restores.
              // This fixes a bug where expanded player state persisted after
              // disconnect, making nav bar opacity=0 and ignoring taps.
              if (playerExpansionNotifier.value.progress != 0.0) {
                playerExpansionNotifier.value = PlayerExpansionState(0.0, null, null);
              }
              return const SizedBox.shrink();
            }

            // Combine slide, bounce, and hint animations with ValueListenableBuilders
            // This prevents full widget tree rebuilds - only ExpandablePlayer updates
            return ValueListenableBuilder<double>(
              valueListenable: _bounceOffsetNotifier,
              builder: (context, bounceOffset, _) {
                return ValueListenableBuilder<double>(
                  valueListenable: _hintOpacityNotifier,
                  builder: (context, hintOpacity, _) {
                    return AnimatedBuilder(
                      animation: _slideAnimation,
                      builder: (context, _) {
                        return ExpandablePlayer(
                          key: globalPlayerKey,
                          slideOffset: _slideAnimation.value,
                          bounceOffset: bounceOffset,
                          onRevealPlayers: _showPlayerReveal,
                          isDeviceRevealVisible: _isRevealVisible,
                          isHintVisible: hintOpacity > 0,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ],
      ),
    );
  }
}
