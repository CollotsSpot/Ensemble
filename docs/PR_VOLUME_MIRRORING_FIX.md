# PR: Fix lockscreen volume mirroring for remote/group players

## Summary

Fixes the volume jump bug in lockscreen hardware volume control when using remote/group players. The system volume slider now shadows the MA player volume without dangerous jumps or desync.

**References:**
- Original feature: `ea7144d` (Sync group volume management, hardware volume buttons)
- Original feature introduced unintended behaviour and was pathed: `688b635` (Fix hardware volume in background)

## Problem

When the app was backgrounded and the system volume changed (e.g., for YouTube), returning to use hardware buttons for MA volume control caused potentially very large volume jumps — the system volume (e.g., 100%) was mirrored directly to MA, potentially blowing out speakers and killing the cat. The patch in `688b635` stopped the volume observer on pause, but this disabled lockscreen volume control entirely.

## Approach

Instead of mirroring system volume values to MA, hardware buttons are now treated as **directional step inputs**. The system volume slider becomes a "button press detector" that silently resets after each event, while MA volume changes independently in safe increments.

## Changes

### `MainActivity.kt` (Kotlin — native layer)
- **`isMAPlaying` guard**: Observer suppresses mirroring when MA is not actively streaming (`isMusicActive`, `MODE_NORMAL` checks), replacing the stop/start of `688b635`
- **Observer stays alive across pause/resume**: `onPause` only disables `dispatchKeyEvent` (foreground key interception); the observer remains active for lockscreen button detection
- **Direction + delta signal**: Each observer event sends `direction` (+1/-1) and `delta` (per-step size mapped to 0-100) to Flutter
- **Center-reset with MA shadow**: After each event, system volume resets to the position matching `estimatedMAVolume`, clamped to `[1, max-1]` so buttons always have room in both directions. The slider visually tracks MA instead of snapping to midpoint
- **Reduced ignore window**: `ignoringVolumeChange` guard reduced from 1000ms to 100ms, preventing button presses from being swallowed

### `lib/main.dart` (Flutter — app layer)
- **Always-step mode**: `_setAbsoluteVolume` never mirrors the system value directly — steps MA by the native `delta` in the button `direction`, making volume jumps structurally impossible
- **`_lastSteppedVolume` tracking**: Accumulates volume changes synchronously so rapid presses (hold button) use the correct base instead of stale `player.volume`
- **Play-resume re-sync**: When `isPlaying` transitions true, syncs system volume to MA, closing any drift from the suppression window
- **`setMAPlayingState`**: Sends playback state to native layer so the observer can self-guard

### `lib/services/hardware_volume_service.dart`
- Updated `onAbsoluteVolumeChange` stream type to include `direction` and `delta` fields
- Added `setMAPlayingState()` method to notify native layer of playback state

## How it works

1. User presses hardware volume button on lockscreen
2. System volume changes by 1 step → ContentObserver fires
3. Kotlin detects direction and delta, sends to Flutter, resets system to MA-equivalent position (clamped [1, max-1])
4. Flutter steps MA by delta in that direction, tracks accumulated value
5. System slider visually shadows MA position; buttons always work in both directions

**Desync scenario** (MA=20%, system was changed to 100% while paused):
- Play resumes → system syncs back to 20%
- If sync didn't happen: button press steps MA by ~7%, never jumps to 100%
