# Multi-Provider Split Plan

## Current Status (2026-02-07)

### Completed

| Provider | Lines | File | Status |
|----------|-------|------|--------|
| ConnectionProvider | 245 | lib/providers/connection_provider.dart | ✅ Created |
| UIStateProvider | 167 | lib/providers/ui_state_provider.dart | ✅ Created & Committed |
| LibraryProvider | 290 | lib/providers/library_provider.dart | ✅ Created & Committed |
| PlayerProvider | 589 | lib/providers/player_provider.dart | ✅ Created & Integrated |
| LocalPlayerProvider | 370 | lib/providers/local_player_provider.dart | ✅ Created & Integrated |

**Main Provider: 5928 lines** (down from 6180 original)

### Integration Status

✅ **Phase 1 Complete**: All 5 providers created
✅ **Phase 2 Started**: Integration into main.dart completed
- All providers added to MultiProvider tree
- Shared services (CacheService, PositionTracker, ImageHelperService) properly initialized
- Build successful (52.2MB APK)

### Remaining Work

| Task | Complexity | Notes |
|------|------------|-------|
| Update MusicAssistantProvider facade | Medium | Accept providers in constructor, delegate methods |
| Migrate consumers incrementally | High | Start with less critical screens |
| Remove facade when complete | Low | After all consumers migrated |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                      MusicAssistantProvider                         │
│                      (Facade - during transition)                   │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  Delegates to sub-providers:                                  │  │
│  │  • ConnectionProvider - connect/disconnect, auth              │  │
│  │  • UIStateProvider - search, filters, loading state            │  │
│  │  • LibraryProvider - artists, albums, tracks, podcasts        │  │
│  │  • PlayerProvider - player selection, controls, queue (TODO)  │  │
│  │  • LocalPlayerProvider - local audio engine (TODO)            │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Next Steps

### Phase 1: Complete Provider Creation (Current)

1. **Create PlayerProvider** (~800 lines)
   - Extract player selection and switching logic
   - Extract play/pause/stop/seek controls
   - Extract queue management
   - Extract sleep timer functionality

2. **Create LocalPlayerProvider** (~500 lines)
   - Extract local audio playback engine
   - Extract Sendspin integration
   - Extract player registration
   - Extract volume and power control

### Phase 2: Integration

3. **Update main.dart**
   - Add all providers to MultiProvider
   - Keep MusicAssistantProvider as facade initially

4. **Migrate one consumer at a time**
   - Start with less critical screens
   - Test thoroughly after each migration
   - Use facade to maintain compatibility during transition

5. **Remove facade**
   - Once all consumers migrated
   - Remove MusicAssistantProvider
   - Direct widget-provider relationships

---

## PlayerProvider Extraction Plan

### State to Extract

```dart
// Player selection
Player? _selectedPlayer;
List<Player> _availablePlayers = [];
Map<String, String> _castToSendspinIdMap = {};

// Current playback
Track? _currentTrack;
Audiobook? _currentAudiobook;
String? _currentPodcastName;

// Sleep timer
Timer? _sleepTimer;
DateTime? _sleepTimerEndTime;
int? _sleepTimerMinutes;
Timer? _sleepTimerDisplayTimer;

// Timers
Timer? _playerStateTimer;
Timer? _notificationPositionTimer;
Timer? _idleServiceTimer;

// Position tracking
PositionTracker _positionTracker;
```

### Methods to Extract

```dart
// Player selection
Future<void> _loadAndSelectPlayers({bool forceRefresh, bool coldStart});
Future<void> selectPlayer(Player player, {bool? sendToSendspin});

// Playback controls
Future<void> playPause();
Future<void> stop();
Future<void> nextTrack();
Future<void> previousTrack();
Future<void> seek(Duration position);
Future<void> setVolume(String playerId, int volumeLevel);

// Queue management
Future<PlayerQueue?> getQueue(String playerId);
Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex});

// Sleep timer
Future<void> setSleepTimer(int minutes);
Future<void> cancelSleepTimer();
```

### Dependencies to Inject

- MusicAssistantAPI
- DatabaseService
- SettingsService
- QueueManagerService
- PositionTracker
- PlayerSyncState
- AudioHandler (from audio_service)

---

## Estimated Timeline

| Task | Time | Notes |
|------|------|-------|
| Create PlayerProvider | 2-3 hours | Complex, many dependencies |
| Create LocalPlayerProvider | 2-3 hours | Sendspin integration is complex |
| Integration & Testing | 3-4 hours | Update main.dart, migrate consumers |
| Bug Fixes | 1-2 hours | Edge cases in player switching |

**Total: ~8-12 hours of focused development**

---

## Risk Mitigation

1. **Keep facade during transition** - Maintain backward compatibility
2. **Migrate incrementally** - One screen/consumer at a time
3. **Test on device** - Test player controls thoroughly
4. **Commit frequently** - Each provider as it's completed
5. **Keep backup** - Can revert to monolithic provider if needed

---

## Success Criteria

- [ ] All 5 providers created and building
- [ ] Main.dart updated with all providers
- [ ] At least 3 screens migrated to new providers
- [ ] Player controls working correctly on device
- [ ] No regressions in core functionality
- [ ] Main provider reduced to < 1000 lines (or removed)

---

## Files Created So Far

```
lib/providers/
├── connection_provider.dart   (245 lines)  ✅
├── ui_state_provider.dart      (167 lines)  ✅
├── library_provider.dart       (290 lines)  ✅
├── player_provider.dart        (TODO)       ⏳
└── local_player_provider.dart  (TODO)       ⏳
```

---

## Notes from Analysis

1. **Player selection logic is complex** - Involves Cast-to-Sendspin mapping, filtering, smart sorting
2. **Sendspin integration is tricky** - Need to handle both MA 2.7.0+ (Sendspin) and older versions
3. **Queue management already extracted** - QueueManagerService handles most queue logic
4. **Position tracking is separate** - PositionTracker service handles interpolation
5. **Event handlers need coordination** - Player events update both provider and position tracker
