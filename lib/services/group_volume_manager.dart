import '../models/player.dart';
import 'debug_logger.dart';

/// Manages volume state for group players where the MA API returns null volume.
///
/// Both pre-configured speaker groups (provider == 'player_group') and dynamic
/// sync groups (ID typically starts with 'syncgroup_') don't have their own
/// volume_level in the MA API. This manager computes an effective volume from
/// group members and caches recently-set volumes to prevent slider snap-back.
class GroupVolumeManager {
  final _logger = DebugLogger();

  // Cache of last-set volume per group player ID.
  // Prevents slider snap-back between setVolume() and next player_updated event.
  final Map<String, int> _pendingVolumes = {};

  // Timestamps for pending volumes - used to expire stale entries
  final Map<String, DateTime> _pendingTimestamps = {};

  // How long to trust a pending volume before falling back to computed average.
  // For group players the API never returns a volume, so we keep the pending
  // value until the computed member average converges (within tolerance) or
  // until a generous timeout to avoid leaking state forever.
  static const Duration _pendingTimeout = Duration(seconds: 30);

  // If the computed member average is within this many points of the pending
  // value, we consider the server to have confirmed it and clear the pending.
  static const int _confirmationTolerance = 3;

  /// Check if a player is a group player that needs computed volume.
  ///
  /// Detects both:
  /// - Pre-configured MA speaker groups (provider == 'player_group')
  /// - Dynamic sync groups (have group members but API returns null volume)
  bool isGroupPlayer(Player player) {
    // Pre-configured MA speaker groups
    if (player.provider == 'player_group') return true;
    // Dynamic sync groups: have multiple group members but MA returns null volume
    if (player.groupMembers != null &&
        player.groupMembers!.length > 1 &&
        player.volumeLevel == null) {
      return true;
    }
    return false;
  }

  /// Get the effective volume for a player.
  ///
  /// For non-group players: returns player.volumeLevel (unchanged behavior).
  /// For group players: returns cached pending volume if recent, otherwise
  /// computes average from group members.
  ///
  /// [player] - The player to get volume for.
  /// [allPlayers] - All available players (needed to look up group members).
  ///
  /// Returns volume as int 0-100, or null if no volume can be determined.
  int? getEffectiveVolumeLevel(Player player, List<Player> allPlayers) {
    if (!isGroupPlayer(player)) {
      return player.volumeLevel;
    }

    // Check for a pending (just-set) volume
    final pending = _pendingVolumes[player.playerId];
    if (pending != null) {
      final timestamp = _pendingTimestamps[player.playerId];
      if (timestamp != null &&
          DateTime.now().difference(timestamp) < _pendingTimeout) {
        // Compute member average to see if server has converged
        final memberAvg = _computeGroupVolume(player, allPlayers);
        if (memberAvg != null && (memberAvg - pending).abs() <= _confirmationTolerance) {
          // Server confirmed — member average matches what we set
          _pendingVolumes.remove(player.playerId);
          _pendingTimestamps.remove(player.playerId);
          _logger.debug(
              'GroupVolume: Convergence confirmed for ${player.name}: '
              'pending=$pending, memberAvg=$memberAvg',
              context: 'GroupVolumeManager');
          return memberAvg;
        }
        // Not yet confirmed — keep showing the pending value
        _logger.debug(
            'GroupVolume: Pending protection active for ${player.name}: '
            'pending=$pending, memberAvg=$memberAvg, '
            'elapsed=${DateTime.now().difference(timestamp).inSeconds}s',
            context: 'GroupVolumeManager');
        return pending;
      }
      // Expired after generous timeout — remove it
      _logger.debug(
          'GroupVolume: Pending expired for ${player.name} after ${_pendingTimeout.inSeconds}s, '
          'falling back to computed average',
          context: 'GroupVolumeManager');
      _pendingVolumes.remove(player.playerId);
      _pendingTimestamps.remove(player.playerId);
    }

    // Compute average from group members
    return _computeGroupVolume(player, allPlayers);
  }

  /// Compute the average volume across all group members.
  /// Recursively resolves nested group members (MA sometimes makes the first
  /// member of a group also a group player, which returns null for volumeLevel).
  /// Returns null if no members have a valid volume.
  int? _computeGroupVolume(Player groupPlayer, List<Player> allPlayers,
      {int depth = 0}) {
    // Prevent infinite recursion from circular group references
    if (depth > 3) return null;

    final memberIds = groupPlayer.groupMembers;
    if (memberIds == null || memberIds.isEmpty) {
      _logger.debug('GroupVolume: No group members for ${groupPlayer.name}',
          context: 'GroupVolumeManager');
      return null;
    }

    int totalVolume = 0;
    int count = 0;

    for (final memberId in memberIds) {
      // Skip self-references (groupMembers can include the group's own ID)
      if (memberId == groupPlayer.playerId) continue;

      final member =
          allPlayers.where((p) => p.playerId == memberId).firstOrNull;
      if (member == null) continue;

      if (member.volumeLevel != null) {
        totalVolume += member.volumeLevel!;
        count++;
      } else if (isGroupPlayer(member)) {
        // Nested group player — MA returns null volumeLevel for these.
        // Recursively compute from the nested group's own members.
        final subVolume =
            _computeGroupVolume(member, allPlayers, depth: depth + 1);
        if (subVolume != null) {
          totalVolume += subVolume;
          count++;
          _logger.debug(
              'GroupVolume: Resolved nested group ${member.name} → volume $subVolume',
              context: 'GroupVolumeManager');
        }
      }
    }

    if (count == 0) {
      _logger.debug(
          'GroupVolume: No members with volume for ${groupPlayer.name} '
          '(${memberIds.length} members checked, depth=$depth)',
          context: 'GroupVolumeManager');
      return null;
    }

    final avg = (totalVolume / count).round();
    _logger.debug(
        'GroupVolume: ${groupPlayer.name} average=$avg from $count members '
        '(total=$totalVolume, depth=$depth)',
        context: 'GroupVolumeManager');
    return avg;
  }

  /// Record that a volume was just set on a group player.
  /// This prevents the slider from snapping back to 0 before the
  /// MA server processes the volume change on all members.
  void onVolumeSet(String playerId, int volumeLevel) {
    _pendingVolumes[playerId] = volumeLevel;
    _pendingTimestamps[playerId] = DateTime.now();
  }

  /// Clear all cached state (e.g., on disconnect)
  void clear() {
    _pendingVolumes.clear();
    _pendingTimestamps.clear();
  }
}
