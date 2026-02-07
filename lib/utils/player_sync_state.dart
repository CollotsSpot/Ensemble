import '../models/player.dart';

/// Utility for determining player sync state.
///
/// Extracted from MusicAssistantProvider to isolate complex sync logic
/// and make it testable independently.
class PlayerSyncState {
  final List<Player> availablePlayers;
  final Map<String, String> castToSendspinIdMap;

  PlayerSyncState({
    required this.availablePlayers,
    required this.castToSendspinIdMap,
  });

  /// Check if a player should show the "manually synced" indicator (yellow border).
  ///
  /// Returns true for BOTH the leader AND children of a manually created sync group.
  /// Excludes pre-configured MA speaker groups (provider = 'player_group').
  bool isPlayerManuallySynced(String playerId) {
    final player = availablePlayers.where((p) => p.playerId == playerId).firstOrNull;
    if (player == null) return false;

    // Group players (like "All Speakers") should NEVER have yellow border
    // They are pre-configured containers, not manually synced players
    // Check this FIRST before any other logic to prevent edge cases
    if (player.provider == 'player_group') return false;

    // Case 1: Player is a child synced to another player
    if (player.syncedTo != null) {
      // Look up sync target - also check translated IDs for Cast+Sendspin players
      // The syncedTo might contain a Cast ID but the player list has the Sendspin version
      Player? syncTarget = availablePlayers.where((p) => p.playerId == player.syncedTo).firstOrNull;

      // If not found, try looking up by translated Sendspin ID
      if (syncTarget == null) {
        final translatedId = castToSendspinIdMap[player.syncedTo];
        if (translatedId != null) {
          syncTarget = availablePlayers.where((p) => p.playerId == translatedId).firstOrNull;
        }
      }

      // Also check reverse: syncedTo might be Sendspin ID, look for Cast player
      if (syncTarget == null) {
        // Build reverse map on demand
        for (final entry in castToSendspinIdMap.entries) {
          if (entry.value == player.syncedTo) {
            syncTarget = availablePlayers.where((p) => p.playerId == entry.key).firstOrNull;
            if (syncTarget != null) break;
          }
        }
      }

      if (syncTarget == null) return false;

      // If synced to a group player, it's part of a pre-configured group
      if (syncTarget.provider == 'player_group') return false;

      // Synced to a regular player - this is a manual sync child
      return true;
    }

    // Case 2: Player is a leader with group members
    if (player.groupMembers != null && player.groupMembers!.length > 1) {
      // Key distinction: In a MANUAL sync, the leader's own ID is in groupMembers
      // In a PRE-CONFIGURED group (UGP), the group player's ID is NOT in groupMembers
      // (the members are the child players, not including the group itself)
      final isInOwnGroup = player.groupMembers!.contains(player.playerId);
      if (!isInOwnGroup) {
        // This is a pre-configured group player (like "All Speakers")
        return false;
      }
      // Leader's ID is in groupMembers = manual sync
      return true;
    }

    return false;
  }

  /// Find a player by ID, optionally translating Cast IDs to Sendspin IDs.
  Player? findPlayer(String playerId) {
    // Try direct lookup first
    var player = availablePlayers.where((p) => p.playerId == playerId).firstOrNull;

    // If not found, try Cast-to-Sendspin translation
    if (player == null && castToSendspinIdMap.containsKey(playerId)) {
      final sendspinId = castToSendspinIdMap[playerId];
      player = availablePlayers.where((p) => p.playerId == sendspinId).firstOrNull;
    }

    return player;
  }

  /// Find the sync target for a player, handling Cast/Sendspin ID translation.
  Player? findSyncTarget(Player player) {
    if (player.syncedTo == null) return null;

    // Try direct lookup
    var syncTarget = availablePlayers.where((p) => p.playerId == player.syncedTo).firstOrNull;

    // If not found, try translated Sendspin ID
    if (syncTarget == null) {
      final translatedId = castToSendspinIdMap[player.syncedTo];
      if (translatedId != null) {
        syncTarget = availablePlayers.where((p) => p.playerId == translatedId).firstOrNull;
      }
    }

    // Also check reverse: syncedTo might be Sendspin ID, look for Cast player
    if (syncTarget == null) {
      for (final entry in castToSendspinIdMap.entries) {
        if (entry.value == player.syncedTo) {
          syncTarget = availablePlayers.where((p) => p.playerId == entry.key).firstOrNull;
          if (syncTarget != null) break;
        }
      }
    }

    return syncTarget;
  }

  /// Check if a player is a group player (pre-configured MA speaker group).
  bool isGroupPlayer(Player player) {
    return player.provider == 'player_group';
  }

  /// Check if a player is a leader in a manual sync group.
  bool isManualSyncLeader(Player player) {
    if (player.groupMembers == null || player.groupMembers!.length <= 1) {
      return false;
    }
    // In a MANUAL sync, the leader's own ID is in groupMembers
    return player.groupMembers!.contains(player.playerId);
  }
}
