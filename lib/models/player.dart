import 'media_item.dart';

class Player {
  final String playerId;
  final String name;
  final String? provider; // e.g., 'builtin_player', 'chromecast', etc.
  final bool available;
  final bool powered;
  final String state; // 'idle', 'playing', 'paused'
  final String? currentItemId;
  final int? volumeLevel; // 0-100
  final bool? volumeMuted;
  final double? elapsedTime; // Seconds elapsed in current track
  final double? elapsedTimeLastUpdated; // Unix timestamp when elapsed_time was last updated
  final List<String>? groupMembers; // List of player IDs in sync group (includes self)
  final String? syncedTo; // Player ID this player is synced to (null if leader or not synced)
  final String? activeSource; // The currently active source for this player
  final bool isExternalSource; // True when an external source (optical, Spotify, etc.) is active
  final String? appId; // The app_id from MA - 'music_assistant' when MA is playing, else external source
  final String? activeQueue; // The active_queue from MA - has value when MA is controlling playback

  Player({
    required this.playerId,
    required this.name,
    this.provider,
    required this.available,
    required this.powered,
    required this.state,
    this.currentItemId,
    this.volumeLevel,
    this.volumeMuted,
    this.elapsedTime,
    this.elapsedTimeLastUpdated,
    this.groupMembers,
    this.syncedTo,
    this.activeSource,
    this.isExternalSource = false,
    this.appId,
    this.activeQueue,
  });

  /// Create a copy of this Player with some fields replaced
  Player copyWith({
    String? playerId,
    String? name,
    String? provider,
    bool? available,
    bool? powered,
    String? state,
    String? currentItemId,
    int? volumeLevel,
    bool? volumeMuted,
    double? elapsedTime,
    double? elapsedTimeLastUpdated,
    List<String>? groupMembers,
    String? syncedTo,
    String? activeSource,
    bool? isExternalSource,
    String? appId,
    String? activeQueue,
  }) {
    return Player(
      playerId: playerId ?? this.playerId,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      available: available ?? this.available,
      powered: powered ?? this.powered,
      state: state ?? this.state,
      currentItemId: currentItemId ?? this.currentItemId,
      volumeLevel: volumeLevel ?? this.volumeLevel,
      volumeMuted: volumeMuted ?? this.volumeMuted,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      elapsedTimeLastUpdated: elapsedTimeLastUpdated ?? this.elapsedTimeLastUpdated,
      groupMembers: groupMembers ?? this.groupMembers,
      syncedTo: syncedTo ?? this.syncedTo,
      activeSource: activeSource ?? this.activeSource,
      isExternalSource: isExternalSource ?? this.isExternalSource,
      appId: appId ?? this.appId,
      activeQueue: activeQueue ?? this.activeQueue,
    );
  }

  // Derived properties
  bool get isPlaying => state == 'playing';
  bool get isMuted => volumeMuted ?? false;
  int get volume => volumeLevel ?? 0;

  // Group properties
  // A player is grouped if it's a leader with members OR a child synced to another
  bool get isGrouped => (groupMembers != null && groupMembers!.length > 1) || syncedTo != null;
  bool get isGroupLeader => groupMembers != null && groupMembers!.length > 1 && syncedTo == null;
  bool get isGroupChild => syncedTo != null;

  // A player is manually synced if it's synced TO another player (child of a sync group)
  // This excludes pre-configured MA speaker groups which have groupMembers but no syncedTo
  // Used for yellow border highlight - only shows for players the user manually synced
  bool get isManuallySynced => syncedTo != null;

  // Track when this Player object was created (for local interpolation fallback)
  static final Map<String, double> _playerCreationTimes = {};
  static const int _maxCreationTimesEntries = 50;

  /// Clean up old creation time entries using LRU eviction
  static void _cleanupCreationTimes() {
    if (_playerCreationTimes.length <= _maxCreationTimesEntries) return;

    // Sort by timestamp value (oldest first) for true LRU eviction
    final sortedEntries = _playerCreationTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    // Remove oldest entries until we're at target size
    final entriesToRemove = sortedEntries.take(
      _playerCreationTimes.length - _maxCreationTimesEntries,
    );
    for (final entry in entriesToRemove) {
      _playerCreationTimes.remove(entry.key);
    }
  }

  // Calculate current elapsed time (interpolated if playing)
  double get currentElapsedTime {
    if (elapsedTime == null) {
      return 0;
    }

    if (!isPlaying) {
      return elapsedTime!;
    }

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // Try server-provided timestamp first, but only if it's recent
    if (elapsedTimeLastUpdated != null) {
      final timeSinceUpdate = now - elapsedTimeLastUpdated!;

      // Only use server timestamp if it's within valid range (0-10 seconds)
      // - Negative means clock skew (client ahead of server)
      // - > 10 seconds means stale data (e.g., after player switch)
      // If outside this range, fall through to local fallback for smooth interpolation
      if (timeSinceUpdate >= 0 && timeSinceUpdate <= 10.0) {
        return elapsedTime! + timeSinceUpdate;
      }
      // Server timestamp is stale or invalid - fall through to local fallback
    }

    // Fallback: use local creation time for interpolation
    // This handles:
    // 1. Server doesn't send elapsed_time_last_updated
    // 2. Server timestamp is stale (e.g., after switching to a remote player)
    // 3. Clock skew between client and server
    //
    // Key insight: when server sends a NEW elapsed_time, we get a NEW key,
    // so interpolation naturally starts fresh. We should NEVER reset an existing
    // key's creation time, as that causes progress to jump backward.
    final creationKey = '$playerId:$elapsedTime';

    if (!_playerCreationTimes.containsKey(creationKey)) {
      // First time seeing this elapsed_time - record when we saw it
      _playerCreationTimes[creationKey] = now;
      // Clean up old entries to prevent memory leak (LRU eviction)
      _cleanupCreationTimes();
    }

    final creationTime = _playerCreationTimes[creationKey]!;
    final timeSinceCreation = now - creationTime;

    // Server sends updates every ~5 seconds with new elapsed_time values,
    // which creates new keys and corrects any drift. Allow unlimited
    // interpolation since new server data will naturally correct it.
    return elapsedTime! + timeSinceCreation;
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    // Extract current_item_id from current_media if available
    String? currentItemId = json['current_item_id'] as String?;
    double? elapsedTime;
    double? elapsedTimeLastUpdated;

    // Get top-level elapsed time values
    // Try multiple field names as different player types may report position differently
    final topLevelElapsedTime = (json['elapsed_time'] as num?)?.toDouble()
        ?? (json['position'] as num?)?.toDouble()
        ?? (json['media_position'] as num?)?.toDouble()
        ?? (json['current_position'] as num?)?.toDouble();
    final topLevelLastUpdated = (json['elapsed_time_last_updated'] as num?)?.toDouble()
        ?? (json['position_updated_at'] as num?)?.toDouble();

    // Extract current_item_id and elapsed time from current_media
    // current_media often has the more accurate position after seeks
    if (json.containsKey('current_media')) {
      final currentMedia = json['current_media'] as Map<String, dynamic>?;
      if (currentMedia != null) {
        currentItemId ??= currentMedia['queue_item_id'] as String?;

        // Try multiple field names for position
        final currentMediaElapsedTime = (currentMedia['elapsed_time'] as num?)?.toDouble()
            ?? (currentMedia['position'] as num?)?.toDouble()
            ?? (currentMedia['media_position'] as num?)?.toDouble();
        final currentMediaLastUpdated = (currentMedia['elapsed_time_last_updated'] as num?)?.toDouble()
            ?? (currentMedia['position_updated_at'] as num?)?.toDouble();

        // Prefer current_media elapsed_time when available - it reflects actual playback position
        // after seek operations, while top-level elapsed_time may lag behind
        if (currentMediaElapsedTime != null) {
          elapsedTime = currentMediaElapsedTime;
          elapsedTimeLastUpdated = currentMediaLastUpdated ?? topLevelLastUpdated;
        }
      }
    }

    // Fall back to top-level values if current_media didn't have elapsed time
    elapsedTime ??= topLevelElapsedTime;
    elapsedTimeLastUpdated ??= topLevelLastUpdated;

    // Parse group members - MA returns this as a list of player IDs
    final groupMembersList = json['group_members'] as List<dynamic>?;
    final groupMembers = groupMembersList?.map((e) => e.toString()).toList();

    // Parse synced_to - the player ID this player is synced to
    final syncedTo = json['synced_to'] as String?;

    // Parse active_source - the currently active source for this player
    final activeSource = json['active_source'] as String?;

    // Parse active_queue - this is the key indicator for MA-controlled playback
    // When MA is playing: active_queue = 'uuid:...' or similar queue ID
    // When external source: active_queue = null
    final activeQueue = json['active_queue'] as String?;

    // Parse app_id - helps distinguish external sources on DLNA players
    final appId = json['app_id'] as String?;

    // Detect external source (optical, Spotify Connect, AirPlay, etc.)
    //
    // Detection logic priority:
    // 1. If app_id == 'music_assistant' -> MA is playing, NOT external
    // 2. If active_queue has a value -> MA has a queue, NOT external
    //    (This handles Spotify as music provider where URI is spotify:// but MA controls playback)
    // 3. If app_id is set and NOT 'music_assistant' -> external source (e.g., 'http', 'spotify')
    // 4. Fallback: Check URI patterns for simple external IDs (optical, line_in, etc.)
    bool isExternalSource = false;

    // If MA explicitly says it's playing, trust that
    if (appId == 'music_assistant') {
      isExternalSource = false;
    }
    // If there's an active queue, MA is controlling playback (even with spotify:// URIs)
    else if (activeQueue != null && activeQueue.isNotEmpty) {
      isExternalSource = false;
    }
    // If app_id is set to something else (http, spotify, etc.), it's external
    else if (appId != null && appId.isNotEmpty) {
      isExternalSource = true;
    }
    // Fallback: check current_media for simple external source indicators
    // Only check these when we have no app_id and no active_queue
    else if (json.containsKey('current_media')) {
      final currentMedia = json['current_media'] as Map<String, dynamic>?;
      if (currentMedia != null) {
        final uri = currentMedia['uri'] as String?;
        final mediaType = currentMedia['media_type'] as String?;

        // Only check for simple external source identifiers (physical inputs)
        // Do NOT flag spotify://, airplay://, etc. as external here -
        // those should only be external if app_id indicates external control
        if (uri != null) {
          final uriLower = uri.toLowerCase();
          // Simple external source identifiers (no :// or /)
          // These are physical inputs that are always external
          final isSimpleExternalId = !uri.contains('://') && !uri.contains('/') &&
              (uriLower == 'optical' || uriLower == 'line_in' || uriLower == 'bluetooth' ||
               uriLower == 'hdmi' || uriLower == 'tv' || uriLower == 'aux' ||
               uriLower == 'coaxial' || uriLower == 'toslink');

          isExternalSource = isSimpleExternalId;
        }

        // Also check media_type - 'unknown' with non-MA URI indicates external source
        if (!isExternalSource && mediaType == 'unknown') {
          final uri = currentMedia['uri'] as String?;
          if (uri != null && !uri.startsWith('library://') && !uri.contains('://track/')) {
            isExternalSource = true;
          }
        }
      }
    }

    return Player(
      playerId: json['player_id'] as String,
      name: json['name'] as String,
      provider: json['provider'] as String?,
      available: json['available'] as bool? ?? false,
      powered: json['powered'] as bool? ?? false,
      state: json['playback_state'] as String? ?? json['state'] as String? ?? 'idle',
      currentItemId: currentItemId,
      volumeLevel: json['volume_level'] as int?,
      volumeMuted: json['volume_muted'] as bool?,
      elapsedTime: elapsedTime,
      elapsedTimeLastUpdated: elapsedTimeLastUpdated,
      groupMembers: groupMembers,
      syncedTo: syncedTo,
      activeSource: activeSource,
      isExternalSource: isExternalSource,
      appId: appId,
      activeQueue: activeQueue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_id': playerId,
      'name': name,
      if (provider != null) 'provider': provider,
      'available': available,
      'powered': powered,
      'state': state,
      if (currentItemId != null) 'current_item_id': currentItemId,
      if (volumeLevel != null) 'volume_level': volumeLevel,
      if (volumeMuted != null) 'volume_muted': volumeMuted,
      if (elapsedTime != null) 'elapsed_time': elapsedTime,
      if (elapsedTimeLastUpdated != null) 'elapsed_time_last_updated': elapsedTimeLastUpdated,
      if (groupMembers != null) 'group_members': groupMembers,
      if (syncedTo != null) 'synced_to': syncedTo,
      if (activeSource != null) 'active_source': activeSource,
      'is_external_source': isExternalSource,
      if (appId != null) 'app_id': appId,
      if (activeQueue != null) 'active_queue': activeQueue,
    };
  }
}

class StreamDetails {
  final String? streamId;
  final int sampleRate;
  final int bitDepth;
  final String contentType;

  StreamDetails({
    this.streamId,
    required this.sampleRate,
    required this.bitDepth,
    required this.contentType,
  });

  factory StreamDetails.fromJson(Map<String, dynamic> json) {
    return StreamDetails(
      streamId: json['stream_id'] as String?,
      sampleRate: json['sample_rate'] as int? ?? 44100,
      bitDepth: json['bit_depth'] as int? ?? 16,
      contentType: json['content_type'] as String? ?? 'audio/flac',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stream_id': streamId,
      'sample_rate': sampleRate,
      'bit_depth': bitDepth,
      'content_type': contentType,
    };
  }
}

class QueueItem {
  final String queueItemId;
  final Track track;
  final StreamDetails? streamdetails;

  QueueItem({
    required this.queueItemId,
    required this.track,
    this.streamdetails,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    // Queue items may have queue_item_id, or we fall back to item_id from the track
    final queueItemId = json['queue_item_id'] as String? ??
                        json['item_id']?.toString() ??
                        '';

    // The track data is nested inside 'media_item' field (if present and not null)
    final mediaItemData = json.containsKey('media_item') && json['media_item'] != null
        ? json['media_item'] as Map<String, dynamic>
        : json;

    return QueueItem(
      queueItemId: queueItemId,
      track: Track.fromJson(mediaItemData),
      streamdetails: json['streamdetails'] != null
          ? StreamDetails.fromJson(json['streamdetails'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'queue_item_id': queueItemId,
      ...track.toJson(),
      if (streamdetails != null) 'streamdetails': streamdetails!.toJson(),
    };
  }
}

class PlayerQueue {
  final String playerId;
  final List<QueueItem> items;
  final int? currentIndex;
  final bool? shuffleEnabled;
  final String? repeatMode; // 'off', 'one', 'all'
  final double? playbackSpeed; // 0.5 - 2.0, null = default 1.0

  PlayerQueue({
    required this.playerId,
    required this.items,
    this.currentIndex,
    this.shuffleEnabled,
    this.repeatMode,
    this.playbackSpeed,
  });

  bool get shuffle => shuffleEnabled ?? false;
  bool get repeatAll => repeatMode == 'all';
  bool get repeatOne => repeatMode == 'one';
  bool get repeatOff => repeatMode == 'off' || repeatMode == null;
  double get speed => playbackSpeed ?? 1.0;

  factory PlayerQueue.fromJson(Map<String, dynamic> json) {
    return PlayerQueue(
      playerId: json['player_id'] as String,
      items: (json['items'] as List<dynamic>?)
              ?.map((i) => QueueItem.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      currentIndex: json['current_index'] as int?,
      shuffleEnabled: json['shuffle_enabled'] as bool?,
      repeatMode: json['repeat_mode'] as String?,
      playbackSpeed: (json['playback_speed'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_id': playerId,
      'items': items.map((i) => i.toJson()).toList(),
      if (currentIndex != null) 'current_index': currentIndex,
      if (shuffleEnabled != null) 'shuffle_enabled': shuffleEnabled,
      if (repeatMode != null) 'repeat_mode': repeatMode,
      if (playbackSpeed != null) 'playback_speed': playbackSpeed,
    };
  }

  QueueItem? get currentItem {
    if (currentIndex == null || items.isEmpty) return null;
    if (currentIndex! < 0 || currentIndex! >= items.length) return null;
    return items[currentIndex!];
  }
}
