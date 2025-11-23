import 'media_item.dart';

class Player {
  final String playerId;
  final String name;
  final bool available;
  final bool powered;
  final String state; // 'idle', 'playing', 'paused'
  final String? currentItemId;
  final int? volumeLevel; // 0-100
  final bool? volumeMuted;

  Player({
    required this.playerId,
    required this.name,
    required this.available,
    required this.powered,
    required this.state,
    this.currentItemId,
    this.volumeLevel,
    this.volumeMuted,
  });

  // Derived properties
  bool get isPlaying => state == 'playing';
  bool get isMuted => volumeMuted ?? false;
  int get volume => volumeLevel ?? 0;

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      playerId: json['player_id'] as String,
      name: json['name'] as String,
      available: json['available'] as bool? ?? false,
      powered: json['powered'] as bool? ?? false,
      state: json['state'] as String? ?? 'idle',
      currentItemId: json['current_item_id'] as String?,
      volumeLevel: json['volume_level'] as int?,
      volumeMuted: json['volume_muted'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_id': playerId,
      'name': name,
      'available': available,
      'powered': powered,
      'state': state,
      if (currentItemId != null) 'current_item_id': currentItemId,
      if (volumeLevel != null) 'volume_level': volumeLevel,
      if (volumeMuted != null) 'volume_muted': volumeMuted,
    };
  }
}

class StreamDetails {
  final String streamId;
  final int sampleRate;
  final int bitDepth;
  final String contentType;

  StreamDetails({
    required this.streamId,
    required this.sampleRate,
    required this.bitDepth,
    required this.contentType,
  });

  factory StreamDetails.fromJson(Map<String, dynamic> json) {
    return StreamDetails(
      streamId: json['stream_id'] as String,
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

  PlayerQueue({
    required this.playerId,
    required this.items,
    this.currentIndex,
    this.shuffleEnabled,
    this.repeatMode,
  });

  bool get shuffle => shuffleEnabled ?? false;
  bool get repeatAll => repeatMode == 'all';
  bool get repeatOne => repeatMode == 'one';
  bool get repeatOff => repeatMode == 'off' || repeatMode == null;

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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_id': playerId,
      'items': items.map((i) => i.toJson()).toList(),
      if (currentIndex != null) 'current_index': currentIndex,
      if (shuffleEnabled != null) 'shuffle_enabled': shuffleEnabled,
      if (repeatMode != null) 'repeat_mode': repeatMode,
    };
  }

  QueueItem? get currentItem {
    if (currentIndex == null || items.isEmpty) return null;
    if (currentIndex! < 0 || currentIndex! >= items.length) return null;
    return items[currentIndex!];
  }
}
