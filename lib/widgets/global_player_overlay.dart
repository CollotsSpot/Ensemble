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

class _GlobalPlayerOverlayState extends State<GlobalPlayerOverlay> {
  bool _isHidden = false;

  void _setHidden(bool hidden) {
    if (_isHidden != hidden) {
      setState(() => _isHidden = hidden);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The main app content (Navigator, screens, etc.)
        widget.child,
        // Global player overlay - sits above everything
        if (!_isHidden)
          Consumer<MusicAssistantProvider>(
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
      ],
    );
  }
}
