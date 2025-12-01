# CONTEXT HANDOFF: Ensemble - Local Player Isolation Fix

## Current State

- **Branch:** `feature/fix-local-player-isolation`
- **Last build:** 2025-12-01 (run 19821514108)
- **Status:** Player isolation WORKING, ghost players hidden from UI

## CRITICAL BUG FIXED: Local Player Isolation

### The Problem
When the app was installed on multiple phones (e.g., Chris's phone and wife's phone), playing music on one device triggered playback on BOTH devices simultaneously. This was a critical bug caused by both devices sharing the same `player_id` with the Music Assistant server.

### Root Cause
The `DeviceIdService` generated player IDs by hashing hardware characteristics (`androidInfo.fingerprint`, `hardware`, `device`, `model`, `brand`). These values are **identical for devices of the same model** (e.g., two Pixel 8 phones), causing both phones to hash to the same player ID.

### The Fix (Based on KMP Client Pattern)

#### 1. UUID-Based Device ID Generation
**File:** `lib/services/device_id_service.dart`
- Replaced hardware-based ID generation with random UUID generation
- ID is generated ONCE per installation and persisted in SharedPreferences
- Format changed: `massiv_<hash>` → `ensemble_<uuid>`
- Key used: `local_player_id` (new), migrates from legacy `device_player_id` and `builtin_player_id`
- Migration: Detects legacy IDs and generates new UUID without attempting server cleanup

#### 2. Owner Name System
**File:** `lib/services/settings_service.dart`
- Added `_keyOwnerName` constant for storing user's name
- Added `getOwnerName()` and `setOwnerName(String)` methods
- Updated `getLocalPlayerName()` to derive name from owner name
- Added `_makePlayerName(String)` helper for proper possessive apostrophe handling:
  - "Chris" → "Chris' Phone" (ends with 's')
  - "Mom" → "Mom's Phone" (doesn't end with 's')

#### 3. Login Screen "Your Name" Field
**File:** `lib/screens/login_screen.dart`
- Added `_ownerNameController` text field controller
- Added "Your Name" field after server URL, before port
- Placeholder: "Your first name" (no examples)
- Validation: Required, non-empty
- Saves to `SettingsService.setOwnerName()` on successful connection
- Loads saved owner name on screen init

#### 4. Ghost Player Handling
**File:** `lib/providers/music_assistant_provider.dart`
- Unavailable players are now **filtered out** of the player list
- Only the user's own player is kept even if temporarily unavailable
- Ghost players (old installations) don't clutter the player selector
- Note: MA server's `players/remove` API doesn't permanently delete players - they get rediscovered

**File:** `lib/screens/settings_screen.dart`
- Removed "Ghost Players" purge button (it didn't work - MA re-adds them)
- Removed entire "Local Player" section (device name customization, enable/disable toggle)
- Local playback is now always enabled when connected

### Migration Strategy
- Existing installations with legacy hardware-based IDs will automatically migrate on next app start
- New UUID is generated and stored in `local_player_id`
- Legacy keys (`device_player_id`, `builtin_player_id`) are detected but not deleted
- Old ghost players remain on MA server but are hidden from app UI
- Owner name defaults to empty; user will be prompted on next login

## Test Results (2025-12-01)

### Player Isolation - VERIFIED WORKING
- Chris' Phone shows as `ensemble_e57c360f-7c09-4e26-a495-9caf192343d9`
- Playing to "Chris' Phone" works correctly
- No other players triggered simultaneously

### Ghost Players - HIDDEN FROM UI
Ghost players on MA server (not visible in MA web UI, but returned by API):
- Phone (massiv_f45e2bd06bf8) - Available: false
- This device (7cf36283-...) - Available: false
- This Device (ma_3bgw7ae5oy) - Available: false
- This Device (ma_wjpkuwuzv7) - Available: false
- Ensemble (massiv_b66ced8381b4) - Available: false

These are now filtered out of the player selector since they're unavailable.

## Previous Work (audio_service Migration)

### Background playback with audio_service:
   - Replaced `just_audio_background` with `audio_service: ^0.18.12` and `rxdart: ^0.27.7`
   - Custom AudioHandler at `lib/services/audio/massiv_audio_handler.dart`
   - Notification buttons: Skip Prev, Play/Pause, Skip Next
   - Fixed white square stop button issue

### Ensemble Rebranding:
   - Grey logo at `assets/images/ensemble_logo.png`
   - Updated app name in all manifests and config files
   - Default player name: "Ensemble"
   - Notification channel: "Ensemble Audio"

## Key Files Changed (This Fix)

- `lib/services/device_id_service.dart` - **REWRITTEN** to use UUID instead of hardware hash
- `lib/services/settings_service.dart` - Added owner name storage and player name derivation
- `lib/screens/login_screen.dart` - Added "Your Name" field, validates owner name
- `lib/screens/settings_screen.dart` - Removed "Local Player" and "Ghost Players" sections
- `lib/providers/music_assistant_provider.dart` - Filter unavailable players from list

## Outstanding Issues / Next Features

### 1. Ghost Player Prevention (MEDIUM PRIORITY)

**Problem:** Ghost players accumulate on the MA server when users:
- Clear app data
- Uninstall/reinstall the app
- Get a new phone (SharedPreferences don't transfer)

Each of these creates a NEW UUID, leaving the old player as an unavailable ghost.

**Current mitigation:** Unavailable players are hidden from the app UI, but they still exist on MA server.

**Potential Solutions:**

#### Option A: Auto-cleanup on connect
When the app connects and registers the local player, automatically remove other unavailable builtin players.

```dart
On connect:
1. Register our player (ensemble_<uuid>)
2. Find all unavailable builtin players that aren't ours
3. Remove them via builtin_player/unregister
```

**Pros:** Simple, automatic, no user interaction needed
**Cons:** `players/remove` doesn't permanently delete (MA re-adds them); `builtin_player/unregister` might work better

#### Option B: Tie ID to owner name on server
Store a mapping of owner name → player ID on the MA server. When "Chris" connects, reuse the existing player ID.

**Pros:** Truly persistent across reinstalls
**Cons:** Requires server-side storage, more complex

#### Option C: Use Android backup system
Ensure SharedPreferences are backed up to Google Drive so the UUID persists across device changes.

**Pros:** Uses existing Android infrastructure
**Cons:** Not guaranteed to work, user must have backup enabled

#### Option D: Prompt user to reuse existing player
On first connect, check if there's an unavailable player matching the owner name pattern. Ask user: "Found existing player 'Chris' Phone' - reuse it?"

**Pros:** User control, handles edge cases
**Cons:** More UI complexity, confusing for non-technical users

**Recommended approach:** Start with Option A (auto-cleanup on connect). If `builtin_player/unregister` works better than `players/remove`, use that.

### 2. Remote Player Notification (HIGH PRIORITY)
**Problem:** Notification ONLY shows when playing locally on the phone. When controlling a remote player (e.g., Dining Room), there's NO notification at all.

**Why:** `audio_service` creates notifications for local audio playback only. When a remote player is active, the phone is just a remote control with no local audio.

**Solution needed:**
- Create a "remote control" notification using a foreground service
- Show notification for ALL playback (local or remote)
- Skip/play/pause buttons control the selected player
- Could add player switcher button to notification
- This is how the official KMP client works

### 2. Player Switcher in Notification (AFTER #1)
Once remote notifications work, add a speaker icon button that opens player selection.

### 3. App Icon
- Currently using old Massiv icon (`massiv_icon.png`)
- User doesn't have new Ensemble icon yet
- Keep current icon for now, notification uses music note

## MusicAssistantProvider Context

The provider at `lib/providers/music_assistant_provider.dart` handles:
- `_pendingTrackMetadata` - metadata captured from player_updated events
- `_currentNotificationMetadata` - what's actually showing in notification
- `_handlePlayerUpdatedEvent()` - captures metadata, detects stale notification
- `_handleLocalPlayerEvent()` - handles play_media, stop, etc from server
- Race condition on local IP: play_media arrives before player_updated with correct metadata

## KMP Client Reference

Looked at https://github.com/music-assistant/kmp-client-app for patterns:
- They use MediaSession directly (Kotlin)
- No stop button in their notification
- Have player switch button
- `MediaNotificationManager.kt` and `MediaSessionHelper.kt` are good references
- They show notification for ANY active player, not just local

## Commands

```bash
# Check build status
gh run list --workflow="Build Android APK" --limit 2

# Watch build
gh run watch <run_id>

# Trigger new build
gh workflow run "Build Android APK" --ref feature/fix-local-player-isolation
```

## Debug Logging Added

Player list debugging in `_loadAndSelectPlayers()`:
```
🎛️ getPlayers returned X players:
   - PlayerName (playerId) available=true/false powered=true/false
🎛️ After filtering: X players available
```
