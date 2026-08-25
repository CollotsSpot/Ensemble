# Music Assistant 2.8.0 Beta 14 — Impact on Ensemble

**Date:** 2026-03-03
**Current server:** 2.8.0 beta 12
**Target server:** 2.8.0 beta 14 (released March 2, 2026)

---

## Summary

Beta 14 is a large release (50+ PRs). The headline change — merging multi-protocol players into a single entity — directly overlaps with Ensemble's client-side Cast↔Sendspin consolidation logic. Sendspin also received a major v4.0 overhaul. Most changes should degrade gracefully but player ID persistence will break on upgrade.

---

## Breaking: Player Merging (PR #3150)

MA now merges players that support multiple protocols (e.g. a Chromecast with Cast + Sendspin) into a **single player entity** server-side. Previously these appeared as two separate players.

> *"After this change, all your players will be reset. If you previously had multiple players in Music Assistant per protocol, this will now show up as one single player."*

### What Ensemble does today

Ensemble handles this client-side in `music_assistant_provider.dart:4271-4406`:

- `_castToSendspinIdMap` maps Cast IDs → Sendspin IDs
- When Sendspin is grouped: hides Cast player, shows Sendspin (renamed to base name)
- When ungrouped: hides Sendspin, shows original Cast
- Mappings persisted to database for cold start restoration

### Impact on Ensemble

| Component | Location | Impact | Severity |
|---|---|---|---|
| `_castToSendspinIdMap` + consolidation logic | `provider:4271-4406` | Dead code — server no longer sends separate players | Medium |
| `isManuallySyncedPlayer()` ID translation | `provider:533-595` | Lookups against stale map fail silently (returns `false`) | Low |
| Player selection persistence | Settings + DB | **Stored player IDs invalid after upgrade** — all players reset | **High** |
| `_handlePlayerUpdatedEvent()` ID matching | `provider:2956-3358` | Events arrive with new merged IDs, old translation won't match | Medium |
| Database-persisted Cast↔Sendspin mappings | `DatabaseService` | Stale data, won't match anything | Low |

### Assessment

The consolidation logic should degrade gracefully — it won't find Sendspin suffixes to strip or Cast pairs to merge, so the server's already-merged players pass through `filterPlayers()` as-is. The main risk is **player selection breaking** because saved player IDs no longer exist.

### Action required

1. Verify the existing fallback logic (`provider:4427-4465`) gracefully re-selects when the stored `selectedPlayerId` doesn't exist in the player list
2. Remove or gate the Cast↔Sendspin consolidation code behind a server version check (on beta 14+ it's unnecessary and could cause confusion)
3. Clear stale database mappings on first connection to a beta 14+ server

---

## Sendspin v4.0 (PR #3158)

Major rewrite of the Sendspin server.

### Changes

- New `SendspinPlaybackSession` coordinator architecture
- Per-member DSP pipelines, dynamic group membership, late-join audio backfill
- Max buffer capacity 5 → 30 seconds
- Multiple Sendspin servers with automatic failover
- Per-client codec/sample-rate/bit-depth options
- Album artwork persists during skip/pause
- Reduced latency for live streams

### Impact on Ensemble

| Change | Impact |
|---|---|
| New session architecture | **Likely compatible** — sendspin-js only bumped 2.0.0 → 2.0.1 (minor), suggesting wire protocol didn't fundamentally change |
| Per-client codec options | `stream/start` may contain new fields — safe if Ensemble ignores unknown fields |
| Multiple servers with failover | Ensemble's 3-tier connection strategy may need awareness |
| Buffer increase | No client impact |

### Action required

1. Test Sendspin connection against beta 14 — verify `client/hello`, `stream/start`, state reporting all still work
2. Confirm unknown fields in protocol messages are ignored gracefully

---

## Sendspin-Chromecast Bridge (PR #3255)

Replaces the inline experimental Sendspin mode in `ChromecastPlayer` with a dedicated bridge. Cast devices now use a Cast receiver app with an embedded JS Sendspin client.

### Impact on Ensemble

- **Direct impact: None** — Ensemble is a Sendspin client itself, not going through Cast
- **Indirect:** Changes how grouped Cast players behave, which could affect `GroupVolumeManager`

---

## Group Volume / Grouping Fixes

| PR | Change | Ensemble Impact |
|---|---|---|
| #3192 | Fix grouping for players whose native protocol is also a protocol of other players | Bidirectional grouping translation — may affect group detection logic |
| #3205 | Fix group mute for protocol-synced players (`player.state.group_members` vs `player.group_members`) | `GroupVolumeManager` may see different/correct member lists |
| #3277 | Fix `volume_up`/`volume_down` for group players | Server-side fix, should improve behavior |
| #3118 | Fix sync groups losing members on power off | Affects dynamic group management |

### Action required

1. Test group volume behavior — may "just work better" with server-side fixes
2. Verify `GroupVolumeManager` handles any changes to `group_members` field population

---

## Sendspin Bug Fixes

| PR | Fix | Ensemble Relevance |
|---|---|---|
| #3191 | DSP not applying for Sendspin players | DSP config stored on parent player, looked up by protocol player ID — now fixed |
| #3249 | Update to aiosendspin 4.2.0 | Library update, potential behavior changes |
| #3250 | Metadata sending wrong progress when paused | Progress reporting fix — Ensemble's position tracker may see better data |
| #3258 | Floating point for internal audio data | Audio quality improvement, no client impact |

---

## New APIs — Opportunities

| Feature | PR | Details | Ensemble Opportunity |
|---|---|---|---|
| Playback speed | #3198 | `player_queues/set_playback_speed`, stored in `queue.extra_attributes["playback_speed"]` | Great for audiobooks/podcasts |
| Save queue to playlist | #3149 | `save_as_playlist` command on player queue controller | Easy feature add |
| Mixed-media playlists | #3216 | Playlists can contain tracks + podcasts + audiobooks. DB schema bumped to v30. `get_playlist_tracks()` returns `Sequence[PlaylistPlayableItem]` | Playlist screens may need to handle heterogeneous items |
| Genres v2 | #3164 | New browsing category with icons and SVG support | New library section |

---

## Also Changed in Beta 13 (Skipped)

Relevant changes from beta 13 (between current beta 12 and target beta 14):

- Group volume mute support (#3034)
- Frontend prepared for multiprotocol support (#1409) — groundwork for beta 14 merging
- IPv6 support for zeroconf, stream server, AirPlay (#3086)
- Snapcast player availability alignment (#3104)
- DLNA reconnection fix (#3132)

---

## Recommended Action Plan

### Before upgrading

- [ ] Verify player selection fallback handles missing player IDs gracefully
- [ ] Back up current configuration

### Immediate (after upgrading)

- [ ] Test Sendspin protocol compatibility (connection, streaming, state reporting)
- [ ] Test player list — confirm merged players appear correctly without client-side consolidation
- [ ] Test group volume behavior with new server-side fixes
- [ ] Test player selection persistence across app restarts

### Short-term

- [ ] Remove or version-gate Cast↔Sendspin consolidation code
- [ ] Clear stale database mappings on beta 14+ detection
- [ ] Test mixed-media playlist handling if playlists are used

### Opportunistic

- [ ] Add playback speed control (audiobook/podcast feature)
- [ ] Add save-queue-to-playlist
- [ ] Explore Genres v2 browsing
