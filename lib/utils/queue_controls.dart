import '../constants/timings.dart';

/// Utility methods for queue playback controls.
///
/// Extracted from MusicAssistantProvider to isolate queue control logic.
class QueueControls {
  /// Get the next repeat mode in the cycle.
  ///
  /// Cycle order: off → all → one → off
  static String getNextRepeatMode(String? currentMode) {
    switch (currentMode) {
      case RepeatModes.off:
      case null:
        return RepeatModes.all;
      case RepeatModes.all:
        return RepeatModes.one;
      case RepeatModes.one:
        return RepeatModes.off;
      default:
        return RepeatModes.off;
    }
  }

  /// Check if a repeat mode is valid.
  static bool isValidRepeatMode(String? mode) {
    return mode == RepeatModes.off ||
        mode == RepeatModes.all ||
        mode == RepeatModes.one;
  }
}
