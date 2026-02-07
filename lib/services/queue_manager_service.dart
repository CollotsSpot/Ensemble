import 'dart:convert';

import '../models/media_item.dart';
import '../models/player.dart';
import '../services/database_service.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';
import '../services/music_assistant_api.dart';

/// Service for managing player queue operations.
///
/// Extracted from MusicAssistantProvider to isolate queue logic including:
/// - Queue fetching from API with player ID translation
/// - Queue caching to database for instant display
/// - Queue restoration from cache on app resume
/// - Track validation for queue items
class QueueManagerService {
  final MusicAssistantAPI? _api;
  final DatabaseService _database;
  final DebugLogger _logger;
  final List<Player> Function() getAvailablePlayers;
  final Map<String, String> Function() getCastToSendspinMap;
  final Future<void> Function(String playerId, List<Track> tracks, {int startIndex}) playTracks;

  QueueManagerService({
    required MusicAssistantAPI? api,
    required DatabaseService database,
    required DebugLogger logger,
    required this.getAvailablePlayers,
    required this.getCastToSendspinMap,
    required this.playTracks,
  })  : _api = api,
        _database = database,
        _logger = logger;

  /// Fetch queue for a player from the API.
  ///
  /// Handles:
  /// - Group child players (fetches leader's queue)
  /// - Cast-to-Sendspin ID translation
  /// - Automatic caching to database
  Future<PlayerQueue?> getQueue(String playerId) async {
    final effectivePlayerId = _getEffectivePlayerId(playerId);

    final queue = await _api?.getQueue(effectivePlayerId);

    // Persist queue to database for instant display on app resume
    if (queue != null) {
      persistQueueToDatabase(playerId, queue);
    }

    return queue;
  }

  /// Get cached queue for instant display (before API refresh).
  Future<PlayerQueue?> getCachedQueue(String playerId) async {
    try {
      if (!_database.isInitialized) return null;

      final cachedItems = await _database.getCachedQueue(playerId);
      if (cachedItems.isEmpty) return null;

      final items = <QueueItem>[];
      for (final cached in cachedItems) {
        try {
          final itemData = jsonDecode(cached.itemJson) as Map<String, dynamic>;
          items.add(QueueItem.fromJson(itemData));
        } catch (e) {
          _logger.log('⚠️ Error parsing cached queue item: $e');
        }
      }

      if (items.isEmpty) return null;

      return PlayerQueue(
        playerId: playerId,
        items: items,
        currentIndex: 0, // Will be updated from fresh data
      );
    } catch (e) {
      _logger.log('⚠️ Error loading cached queue: $e');
      return null;
    }
  }

  /// Persist queue to database for app restart persistence.
  void persistQueueToDatabase(String playerId, PlayerQueue queue) {
    () async {
      try {
        if (!_database.isInitialized) return;

        final itemJsonList = queue.items.map((item) => jsonEncode(item.toJson())).toList();
        await _database.saveQueue(playerId, itemJsonList);
        _logger.log('💾 Persisted ${queue.items.length} queue items to database');
      } catch (e) {
        _logger.log('⚠️ Error persisting queue to database: $e');
      }
    }();
  }

  /// Attempt to restore the queue from cached data and start playback.
  Future<bool> restoreQueueFromCache(String playerId) async {
    try {
      final cachedQueue = await getCachedQueue(playerId);
      if (cachedQueue == null || cachedQueue.items.isEmpty) {
        _logger.log('⚠️ No cached queue to restore');
        return false;
      }

      // Extract and validate tracks from queue items
      final tracks = _validateQueueTracks(cachedQueue.items);

      if (tracks.isEmpty) {
        _logger.log('⚠️ Cached queue has no valid tracks');
        return false;
      }

      _logger.log('🔄 Restoring ${tracks.length} tracks from cached queue');

      // Re-queue all tracks and start playback
      await playTracks(playerId, tracks, startIndex: 0);

      return true;
    } catch (e) {
      _logger.log('❌ Error restoring queue from cache: $e');
      return false;
    }
  }

  /// Validate and filter tracks from queue items.
  ///
  /// Returns only tracks that can be played (have available provider mappings
  /// or valid provider/itemId combination).
  List<Track> _validateQueueTracks(List<QueueItem> queueItems) {
    return queueItems
        .map((item) => item.track)
        .where((track) {
          // Check for providerMappings with at least one available entry
          if (track.providerMappings != null && track.providerMappings!.isNotEmpty) {
            return track.providerMappings!.any((m) => m.available);
          }
          // Fallback: provider + itemId can be used to construct URI
          return track.provider.isNotEmpty && track.itemId.isNotEmpty;
        })
        .toList();
  }

  /// Get the effective player ID for queue operations.
  ///
  /// Handles:
  /// - Group child players (returns leader's ID)
  /// - Cast-to-Sendspin ID translation
  String _getEffectivePlayerId(String playerId) {
    String effectivePlayerId = playerId;
    final availablePlayers = getAvailablePlayers();
    final castToSendspinMap = getCastToSendspinMap();

    final player = availablePlayers.firstWhere(
      (p) => p.playerId == playerId,
      orElse: () => Player(
        playerId: playerId,
        name: '',
        available: false,
        powered: false,
        state: 'idle',
      ),
    );

    // If this player is a group child, fetch the leader's queue instead
    // This ensures grouped players show the same queue as their leader
    if (player.isGroupChild && player.syncedTo != null) {
      _logger.log('🔗 Player $playerId is grouped, fetching leader queue: ${player.syncedTo}');
      effectivePlayerId = player.syncedTo!;
    }

    // Translate Sendspin ID to Cast UUID for queue fetch
    // MA stores queues under the Cast UUID, not the Sendspin ID
    effectivePlayerId = _translateSendspinToCastId(effectivePlayerId, availablePlayers, castToSendspinMap);

    return effectivePlayerId;
  }

  /// Translate Sendspin ID to Cast UUID for queue operations.
  ///
  /// MA stores queues under the Cast UUID, not the Sendspin ID.
  /// Format: cast-7df484e3 -> need Cast UUID starting with 7df484e3
  String _translateSendspinToCastId(
    String playerId,
    List<Player> availablePlayers,
    Map<String, String> castToSendspinMap,
  ) {
    if (!playerId.startsWith('cast-') || playerId.length < 13) {
      return playerId;
    }

    final prefix = playerId.substring(5); // Remove "cast-"

    // Reverse lookup in the map
    for (final entry in castToSendspinMap.entries) {
      if (entry.value == playerId) {
        _logger.log('🔗 Translated Sendspin ID $playerId to Cast UUID ${entry.key} for queue fetch');
        return entry.key;
      }
    }

    // If not in map, try to find in available players
    for (final p in availablePlayers) {
      if (p.provider == 'chromecast' && p.playerId.startsWith(prefix)) {
        _logger.log('🔗 Found Cast UUID ${p.playerId} for Sendspin ID $playerId via player lookup');
        return p.playerId;
      }
    }

    return playerId;
  }

  /// Clear cached queue for a player.
  Future<void> clearCachedQueue(String playerId) async {
    await _database.clearCachedQueue(playerId);
  }
}
