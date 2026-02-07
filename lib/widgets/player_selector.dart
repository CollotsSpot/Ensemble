import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/timings.dart';
import '../l10n/app_localizations.dart';
import '../providers/music_assistant_provider.dart';
import 'global_player_overlay.dart'; // For isPlayerExpanded and collapsePlayer

class PlayerSelector extends StatelessWidget {
  const PlayerSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, _) {
        final selectedPlayer = maProvider.selectedPlayer;
        final availablePlayers = maProvider.availablePlayers;

    // Count players that are currently playing MA content (excluding selected player)
    // User already sees if selected player is playing, badge shows "other" activity
    // Exclude external sources (Spotify Connect, TV optical, etc.) - they're not playing MA content
    final selectedPlayerId = selectedPlayer?.playerId;
    final playingCount = availablePlayers
        .where((p) => p.state == 'playing' && p.playerId != selectedPlayerId && !p.isExternalSource)
        .length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Badge(
        isLabelVisible: playingCount > 0,
        backgroundColor: colorScheme.tertiary,
        textColor: colorScheme.onTertiary,
        label: Text(
          playingCount.toString(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11,
            color: colorScheme.onTertiary,
          ),
        ),
        child: Material(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => _showPlayerSelector(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selectedPlayer != null) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        selectedPlayer.name,
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    MdiIcons.castAudio,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
      },
    );
  }

  void _showPlayerSelector(BuildContext context) {
    // Use the new player reveal animation
    GlobalPlayerOverlay.showPlayerReveal();
  }
}

class _PlayerSelectorSheet extends StatefulWidget {
  @override
  State<_PlayerSelectorSheet> createState() => _PlayerSelectorSheetState();
}

class _PlayerSelectorSheetState extends State<_PlayerSelectorSheet> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Preload all player track info for display
    context.read<MusicAssistantProvider>().preloadAllPlayerTracks();

    // Auto-refresh at configured polling interval
    _refreshTimer = Timer.periodic(Timings.playerPollingInterval, (_) {
      if (mounted) {
        final provider = context.read<MusicAssistantProvider>();
        provider.refreshPlayers();
        provider.preloadAllPlayerTracks();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final currentPlayers = maProvider.availablePlayers;
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final currentTrack = maProvider.currentTrack;

        final screenHeight = MediaQuery.of(context).size.height;
        final sheetHeight = screenHeight * 0.7; // Fixed 70% height

        return GestureDetector(
          onTap: () => Navigator.pop(context), // Tap outside to dismiss
          behavior: HitTestBehavior.opaque,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {}, // Prevent taps on sheet from dismissing
              child: Container(
                height: sheetHeight,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.speaker_group_rounded, color: colorScheme.onSurface),
                          const SizedBox(width: 12),
                          Text(
                            'Select Player',
                            style: textTheme.titleLarge?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          // Show last refresh indicator
                          Icon(
                            Icons.sync,
                            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: currentPlayers.isEmpty
                          ? Center(
                              child: Text(
                                S.of(context)!.noPlayersAvailable,
                                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.54)),
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.fromLTRB(12, 8, 12, BottomSpacing.navBarOnly),
                              itemCount: currentPlayers.length,
                            itemBuilder: (context, index) {
                              final player = currentPlayers[index];
                              final isSelected = player.playerId == maProvider.selectedPlayer?.playerId;
                              final isOn = player.available && player.powered;
                              final isPlaying = player.state == 'playing';
                              final isPaused = player.state == 'paused';
                              // MA uses 'idle' for players that were paused (especially cast-based)
                              // but still have track info - treat as "has content" for display
                              final isIdle = player.state == 'idle';

                              // Check for external source (optical, Spotify, etc.)
                              final isExternalSource = player.isExternalSource;

                              // Get track info - use current track for selected player, cache for others
                              // Skip track info for external sources
                              final playerTrack = isExternalSource
                                  ? null
                                  : (isSelected
                                      ? currentTrack
                                      : maProvider.getCachedTrackForPlayer(player.playerId));

                              // Player has content if playing, paused, or idle with cached track (but not external source)
                              final hasContent = !isExternalSource && (isPlaying || isPaused || (isIdle && playerTrack != null));

                              // Get album art for any player with content (skip for external source)
                              String? albumArtUrl;
                              if (!isExternalSource && playerTrack != null && isOn && hasContent) {
                                albumArtUrl = maProvider.getImageUrl(
                                  playerTrack.album ?? playerTrack,
                                  size: 128,
                                );
                              }

                              // Check if this player is manually synced (not a pre-configured group)
                              final isGrouped = maProvider.isPlayerManuallySynced(player.playerId);
                              // Pastel yellow for grouped players
                              const groupBorderColor = Color(0xFFFFF59D);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () {
                                    maProvider.selectPlayer(player);
                                    Navigator.pop(context);
                                  },
                                  onLongPress: () {
                                    // Haptic feedback for sync action
                                    HapticFeedback.mediumImpact();

                                    // Show snackbar for visual feedback
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(S.of(context)!.syncingPlayer(player.name)),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );

                                    // Long-press to sync/unsync player
                                    maProvider.togglePlayerSync(player.playerId);
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? colorScheme.primary.withOpacity(0.15)
                                          : colorScheme.surfaceVariant.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(16),
                                      border: isGrouped
                                          ? Border.all(color: groupBorderColor, width: 1.5)
                                          : null,
                                    ),
                                    child: Row(
                                      children: [
                                        // Album art or player icon
                                        Padding(
                                          padding: const EdgeInsets.only(left: 12),
                                          child: Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: colorScheme.surfaceVariant,
                                              borderRadius: BorderRadius.circular(8),
                                              image: albumArtUrl != null
                                                  ? DecorationImage(
                                                      image: CachedNetworkImageProvider(albumArtUrl),
                                                      fit: BoxFit.cover,
                                                    )
                                                  : null,
                                            ),
                                            child: albumArtUrl == null
                                                ? Icon(
                                                    _getPlayerIcon(player.name),
                                                    color: player.available
                                                        ? (isSelected ? colorScheme.primary : colorScheme.onSurface)
                                                        : colorScheme.onSurface.withOpacity(0.38),
                                                    size: 24,
                                                  )
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Player info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                player.name,
                                                style: TextStyle(
                                                  color: player.available
                                                      ? colorScheme.onSurface
                                                      : colorScheme.onSurface.withOpacity(0.38),
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                  fontSize: 16,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  // Status indicator dot
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: !player.available
                                                          ? colorScheme.onSurface.withOpacity(0.24)
                                                          : !isOn
                                                              ? colorScheme.onSurface.withOpacity(0.3)
                                                              : isExternalSource
                                                                  ? Colors.cyan // external source (optical, Spotify, etc.)
                                                                  : isPlaying
                                                                      ? Colors.green
                                                                      : hasContent
                                                                          ? Colors.orange // paused or idle with content
                                                                          : colorScheme.onSurfaceVariant.withOpacity(0.5),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      !player.available
                                                          ? S.of(context)!.playerStateUnavailable
                                                          : !isOn
                                                              ? S.of(context)!.playerStateOff
                                                              : isExternalSource
                                                                  ? S.of(context)!.playerStateExternalSource
                                                                  : hasContent && playerTrack != null
                                                                      ? playerTrack.name
                                                                      : S.of(context)!.playerStateIdle,
                                                      style: TextStyle(
                                                        color: player.available
                                                            ? colorScheme.onSurfaceVariant
                                                            : colorScheme.onSurface.withOpacity(0.24),
                                                        fontSize: 13,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (isGrouped) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: groupBorderColor.withOpacity(0.3),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.link_rounded,
                                                            size: 10,
                                                            color: Colors.amber.shade800,
                                                          ),
                                                          const SizedBox(width: 3),
                                                          Text(
                                                            'Synced',
                                                            style: TextStyle(
                                                              color: Colors.amber.shade800,
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                  if (isSelected) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: colorScheme.primary.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        S.of(context)!.playerSelected,
                                                        style: TextStyle(
                                                          color: colorScheme.primary,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Play/Pause button (hidden for external sources - controls don't work)
                                        if (player.available && isOn && !isExternalSource)
                                          IconButton(
                                            icon: Icon(
                                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                              color: colorScheme.onSurface,
                                              size: 28,
                                            ),
                                            onPressed: () {
                                              if (isPlaying) {
                                                maProvider.pausePlayer(player.playerId);
                                              } else {
                                                maProvider.resumePlayer(player.playerId);
                                              }
                                            },
                                          ),
                                        // Power button
                                        IconButton(
                                          icon: Icon(
                                            Icons.power_settings_new_rounded,
                                            size: 24,
                                            color: player.available
                                                ? (isOn ? colorScheme.primary : colorScheme.onSurfaceVariant.withOpacity(0.5))
                                                : colorScheme.onSurface.withOpacity(0.2),
                                          ),
                                          onPressed: player.available
                                              ? () => maProvider.togglePower(player.playerId)
                                              : null,
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getPlayerIcon(String playerName) {
    final nameLower = playerName.toLowerCase();

    if (nameLower.contains('music assistant mobile') || nameLower.contains('builtin')) {
      return Icons.phone_android_rounded;
    } else if (nameLower.contains('group') || nameLower.contains('sync')) {
      return Icons.speaker_group_rounded;
    } else if (nameLower.contains('bedroom') || nameLower.contains('living') ||
        nameLower.contains('kitchen') || nameLower.contains('dining')) {
      return Icons.speaker_rounded;
    } else if (nameLower.contains('tv') || nameLower.contains('television')) {
      return Icons.tv_rounded;
    } else if (nameLower.contains('cast') || nameLower.contains('chromecast')) {
      return Icons.cast_rounded;
    } else {
      return Icons.speaker_rounded;
    }
  }
}
