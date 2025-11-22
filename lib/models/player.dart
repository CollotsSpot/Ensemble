import 'media_item.dart';

class Player {
  final String playerId;
  final String name;
  final bool available;
  final bool powered;
  final String state; // 'idle', 'playing', 'paused'
  final String? currentItemId;

  Player({
    required this.playerId,
    required this.name,
    required this.available,
    required this.powered,
    required this.state,
    this.currentItemId,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      playerId: json['player_id'] as String,
      name: json['name'] as String,
      available: json['available'] as bool? ?? false,
      powered: json['powered'] as bool? ?? false,
      state: json['state'] as String? ?? 'idle',
      currentItemId: json['current_item_id'] as String?,
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
    return QueueItem(
      queueItemId: json['queue_item_id'] as String,
      track: Track.fromJson(json),
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

  PlayerQueue({
    required this.playerId,
    required this.items,
    this.currentIndex,
  });

  factory PlayerQueue.fromJson(Map<String, dynamic> json) {
    return PlayerQueue(
      playerId: json['player_id'] as String,
      items: (json['items'] as List<dynamic>?)
              ?.map((i) => QueueItem.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      currentIndex: json['current_index'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_id': playerId,
      'items': items.map((i) => i.toJson()).toList(),
      if (currentIndex != null) 'current_index': currentIndex,
    };
  }

  QueueItem? get currentItem {
    if (currentIndex == null || items.isEmpty) return null;
    if (currentIndex! < 0 || currentIndex! >= items.length) return null;
    return items[currentIndex!];
  }
}
