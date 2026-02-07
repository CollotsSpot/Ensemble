/// Utility methods for queue playback controls.
///
/// Extracted from MusicAssistantProvider to isolate queue control logic.
class QueueControls {
  /// Get the next repeat mode in the cycle.
  ///
  /// Cycle order: off → all → one → off
  static String getNextRepeatMode(String? currentMode) {
    switch (currentMode) {
      case 'off':
      case null:
        return 'all';
      case 'all':
        return 'one';
      case 'one':
        return 'off';
      default:
        return 'off';
    }
  }

  /// Check if a repeat mode is valid.
  static bool isValidRepeatMode(String? mode) {
    return mode == 'off' || mode == 'all' || mode == 'one';
  }
}
