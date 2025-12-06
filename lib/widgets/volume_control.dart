import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';

/// Volume control widget for Music Assistant players
class VolumeControl extends StatefulWidget {
  final bool compact;

  const VolumeControl({super.key, this.compact = false});

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  final _logger = DebugLogger();
  double? _pendingVolume; // Track pending volume changes

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      return const SizedBox.shrink();
    }

    final currentVolume = (_pendingVolume ?? player.volume.toDouble()) / 100.0;
    final isMuted = player.isMuted;

    if (widget.compact) {
      // Compact version - just mute button
      return IconButton(
        icon: Icon(
          isMuted ? Icons.volume_off : Icons.volume_up,
          color: Colors.white70,
        ),
        onPressed: () async {
          try {
            await maProvider.setMute(player.playerId, !isMuted);
          } catch (e) {
            // Error already logged by provider
          }
        },
      );
    }

    // Full volume control with slider
    return Row(
      children: [
        // Mute button
        IconButton(
          icon: Icon(
            isMuted
                ? Icons.volume_off
                : currentVolume < 0.3
                    ? Icons.volume_down
                    : Icons.volume_up,
            color: Colors.white70,
          ),
          onPressed: () async {
            try {
              await maProvider.setMute(player.playerId, !isMuted);
            } catch (e) {
              // Error already logged by provider
            }
          },
        ),
        // Volume slider
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 6,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 14,
              ),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.3),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.2),
            ),
            child: Slider(
              value: currentVolume.clamp(0.0, 1.0),
              onChanged: (value) {
                setState(() {
                  _pendingVolume = value * 100;
                });
              },
              onChangeEnd: (value) async {
                final volumeLevel = (value * 100).round();
                _logger.log('Volume: Setting to $volumeLevel%');
                try {
                  // Unmute if changing volume while muted
                  if (isMuted) {
                    _logger.log('Volume: Unmuting player first');
                    await maProvider.setMute(player.playerId, false);
                  }
                  await maProvider.setVolume(player.playerId, volumeLevel);

                  // Wait for the player state to update by polling
                  for (int i = 0; i < 10; i++) {
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (mounted) {
                      final updatedPlayer = maProvider.selectedPlayer;
                      if (updatedPlayer != null && (updatedPlayer.volume - volumeLevel).abs() <= 2) {
                        _logger.log('Volume: Updated to $volumeLevel%');
                        break;
                      }
                    }
                  }
                } catch (e) {
                  _logger.log('Volume: Error - $e');
                } finally {
                  if (mounted) {
                    setState(() {
                      _pendingVolume = null;
                    });
                  }
                }
              },
            ),
          ),
        ),
        // Volume percentage
        SizedBox(
          width: 40,
          child: Text(
            '${(currentVolume * 100).round()}%',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
