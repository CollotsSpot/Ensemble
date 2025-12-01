import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import 'expandable_player.dart';

/// A global key to access the player state from anywhere in the app
final globalPlayerKey = GlobalKey<ExpandablePlayerState>();

/// Key for the overlay state to control visibility
final _overlayStateKey = GlobalKey<_GlobalPlayerOverlayState>();

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
  static void collapsePlayer() {
    globalPlayerKey.currentState?.collapse();
  }

  /// Check if the player is currently expanded
  static bool get isPlayerExpanded =>
      globalPlayerKey.currentState?.isExpanded ?? false;

  /// Hide the mini player temporarily (e.g., when showing device selector)
  static void hidePlayer() {
    _overlayStateKey.currentState?._setHidden(true);
  }

  /// Show the mini player again
  static void showPlayer() {
    _overlayStateKey.currentState?._setHidden(false);
  }
}

class _GlobalPlayerOverlayState extends State<GlobalPlayerOverlay>
    with SingleTickerProviderStateMixin {
  bool _isHidden = false;
  late AnimationController _hideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _hideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1.5), // Slide down below screen
    ).animate(CurvedAnimation(
      parent: _hideController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _hideController.dispose();
    super.dispose();
  }

  void _setHidden(bool hidden) {
    if (_isHidden != hidden) {
      _isHidden = hidden;
      if (hidden) {
        _hideController.forward();
      } else {
        _hideController.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The main app content (Navigator, screens, etc.)
        widget.child,
        // Global player overlay - sits above everything, animates when hidden
        SlideTransition(
          position: _slideAnimation,
          child: Consumer<MusicAssistantProvider>(
            builder: (context, maProvider, _) {
              // Only show player if connected and has a track
              if (!maProvider.isConnected ||
                  maProvider.currentTrack == null ||
                  maProvider.selectedPlayer == null) {
                return const SizedBox.shrink();
              }
              return ExpandablePlayer(key: globalPlayerKey);
            },
          ),
        ),
      ],
    );
  }
}
