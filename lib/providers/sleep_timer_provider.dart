import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/debug_logger.dart';

/// Callback type for when sleep timer expires and should pause playback
typedef OnSleepTimerExpired = void Function();

/// Provider for sleep timer functionality.
///
/// Extracted from MusicAssistantProvider to reduce complexity and improve testability.
/// This provider manages:
/// - Timed sleep (pause after X minutes)
/// - End of track sleep (pause when current track ends)
class SleepTimerProvider with ChangeNotifier {
  final DebugLogger _logger = DebugLogger();

  Timer? _sleepTimer;
  DateTime? _sleepTimerEndTime;
  int? _sleepTimerMinutes; // null = off, -1 = end of track, positive = minutes
  Timer? _sleepTimerDisplayTimer;
  bool _disposed = false;

  /// Callback to pause playback when timer expires
  OnSleepTimerExpired? onExpired;

  // ============================================================================
  // GETTERS
  // ============================================================================

  /// Whether a sleep timer is currently active
  bool get isActive => _sleepTimerMinutes != null;

  /// Current timer setting: null = off, -1 = end of track, positive = minutes
  int? get minutes => _sleepTimerMinutes;

  /// Time remaining until sleep timer expires (null if end-of-track mode or inactive)
  Duration? get remaining {
    if (_sleepTimerEndTime == null) return null;
    final remaining = _sleepTimerEndTime!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ============================================================================
  // TIMER CONTROL
  // ============================================================================

  /// Set sleep timer. Pass null to turn off, -1 for end of track, or minutes.
  void setTimer(int? minutes) {
    // Cancel any existing timer
    _cancelInternal();

    _sleepTimerMinutes = minutes;

    if (minutes == null) {
      // Timer off
      _logger.log('😴 Sleep timer: OFF');
      notifyListeners();
      return;
    }

    if (minutes == -1) {
      // End of track - handled in player state updates
      _sleepTimerEndTime = null; // No fixed end time
      _logger.log('😴 Sleep timer: End of track');
      notifyListeners();
      return;
    }

    // Set timer for specified minutes
    _sleepTimerEndTime = DateTime.now().add(Duration(minutes: minutes));
    _logger.log('😴 Sleep timer: $minutes minutes (until $_sleepTimerEndTime)');

    // Create the actual timer
    _sleepTimer = Timer(Duration(minutes: minutes), _onTimerExpired);

    // Start display update timer (every second for countdown)
    _sleepTimerDisplayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_disposed) {
        notifyListeners(); // Update UI with remaining time
      }
    });

    notifyListeners();
  }

  /// Cancel sleep timer
  void cancel() {
    _cancelInternal();
    _sleepTimerMinutes = null;
    _sleepTimerEndTime = null;
    _logger.log('😴 Sleep timer: Cancelled');
    notifyListeners();
  }

  void _cancelInternal() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerDisplayTimer?.cancel();
    _sleepTimerDisplayTimer = null;
  }

  void _onTimerExpired() {
    _logger.log('😴 Sleep timer expired - pausing playback');
    _cancelInternal();
    _sleepTimerMinutes = null;
    _sleepTimerEndTime = null;

    // Trigger the callback to pause playback
    onExpired?.call();

    notifyListeners();
  }

  /// Called when track ends - checks if "end of track" sleep timer is active
  void checkEndOfTrack() {
    if (_sleepTimerMinutes == -1) {
      _logger.log('😴 End of track sleep timer triggered');
      _sleepTimerMinutes = null;

      // Trigger the callback to pause playback
      onExpired?.call();

      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelInternal();
    super.dispose();
  }
}
