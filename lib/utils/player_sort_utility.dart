import '../models/player.dart';

/// Utility for player list sorting and filtering operations.
///
/// Extracted from MusicAssistantProvider to isolate player sorting logic.
class PlayerSortUtility {
  /// Sort players list based on smart sort setting.
  ///
  /// Smart sort order: local player first, then playing, then on, then off.
  /// Within same status, sort alphabetically.
  ///
  /// Default sort: alphabetical only.
  static void sortPlayers(
    List<Player> players, {
    required bool smartSort,
    String? builtinPlayerId,
  }) {
    if (smartSort) {
      // Smart sort: local player first, then playing, then on, then off
      players.sort((a, b) {
        // Local player always first
        final aIsLocal = builtinPlayerId != null && a.playerId == builtinPlayerId;
        final bIsLocal = builtinPlayerId != null && b.playerId == builtinPlayerId;
        if (aIsLocal && !bIsLocal) return -1;
        if (bIsLocal && !aIsLocal) return 1;

        // Then by status: playing > on > off
        final aPriority = _statusPriority(a);
        final bPriority = _statusPriority(b);
        if (aPriority != bPriority) return aPriority.compareTo(bPriority);

        // Within same status, sort alphabetically
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } else {
      // Default alphabetical sort
      players.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  /// Get priority for player status (lower = higher priority).
  static int _statusPriority(Player player) {
    if (player.state == 'playing') return 0;
    if (player.powered && player.state != 'off') return 1;
    return 2;
  }

  /// Filter players to exclude unwanted players.
  ///
  /// Removes:
  /// - "Music Assistant Mobile" players
  /// - MA Web UI's built-in player (ma_ prefix)
  /// - "This Device" named players without proper provider
  /// - Other device's ensemble players
  /// - Unavailable players (except builtin player)
  static List<Player> filterPlayers(
    List<Player> players, {
    required String? builtinPlayerId,
  }) {
    final result = <Player>[];

    for (final player in players) {
      final nameLower = player.name.toLowerCase();

      // Filter out "music assistant mobile" players
      if (nameLower.contains('music assistant mobile')) {
        continue;
      }

      // Filter out MA Web UI's built-in player (provider is 'builtin_player' and starts with 'ma_')
      if (player.provider == 'builtin_player' && player.playerId.startsWith('ma_')) {
        continue;
      }

      // Filter out "This Device" named players without proper provider
      if (nameLower == 'this device') {
        continue;
      }

      // Filter out other device's ensemble players
      if (player.playerId.startsWith('ensemble_')) {
        if (builtinPlayerId == null || player.playerId != builtinPlayerId) {
          continue;
        }
      }

      // Filter out unavailable players (except builtin player)
      if (!player.available) {
        if (builtinPlayerId != null && player.playerId == builtinPlayerId) {
          result.add(player);
        }
        continue;
      }

      result.add(player);
    }

    return result;
  }

  /// Find the best player to auto-select based on priority.
  ///
  /// Priority order:
  /// 1. Last selected player (if available)
  /// 2. Last active player from any session
  /// 3. Built-in player
  /// 4. First available player
  static Player? selectBestPlayer({
    required List<Player> availablePlayers,
    required Player? lastSelectedPlayer,
    required Player? lastActivePlayer,
    required String? builtinPlayerId,
  }) {
    // Priority 1: Last selected player (if available and in current list)
    if (lastSelectedPlayer != null) {
      final found = availablePlayers.firstWhere(
        (p) => p.playerId == lastSelectedPlayer!.playerId,
        orElse: () => _emptyPlayer,
      );
      if (found.playerId.isNotEmpty) {
        return found;
      }
    }

    // Priority 2: Last active player from any session (if available)
    if (lastActivePlayer != null) {
      final found = availablePlayers.firstWhere(
        (p) => p.playerId == lastActivePlayer!.playerId,
        orElse: () => _emptyPlayer,
      );
      if (found.playerId.isNotEmpty) {
        return found;
      }
    }

    // Priority 3: Built-in player (if available)
    if (builtinPlayerId != null) {
      final builtin = availablePlayers.firstWhere(
        (p) => p.playerId == builtinPlayerId,
        orElse: () => _emptyPlayer,
      );
      if (builtin.playerId.isNotEmpty) {
        return builtin;
      }
    }

    // Priority 4: First available player
    if (availablePlayers.isNotEmpty) {
      return availablePlayers.first;
    }

    return null;
  }

  static final Player _emptyPlayer = Player(
    playerId: '',
    name: '',
    available: false,
    powered: false,
    state: 'idle',
  );
}
