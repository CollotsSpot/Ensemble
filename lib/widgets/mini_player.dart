import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/now_playing_screen.dart';
import '../screens/queue_screen.dart';
import 'volume_control.dart';
import '../constants/hero_tags.dart';
import 'animated_icon_button.dart';
import 'player_selector.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final selectedPlayer = maProvider.selectedPlayer;
        final currentTrack = maProvider.currentTrack;

        // Don't show mini player if no track is playing or no player selected
        if (currentTrack == null || selectedPlayer == null) {
          return const SizedBox.shrink();
        }

        final imageUrl = maProvider.getImageUrl(currentTrack, size: 96);

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NowPlayingScreen(),
              ),
            );
          },
          child: Hero(
            tag: HeroTags.nowPlayingBackground,
            child: Material(
              color: colorScheme.surface,
              elevation: 0,
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Status indicator bar
                    Container(
                      height: 2,
                      color: selectedPlayer.isPlaying
                          ? colorScheme.primary.withOpacity(0.7)
                          : colorScheme.onSurface.withOpacity(0.1),
                    ),
                    // Player content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Row(
                          children: [
                            // Album art with Hero animation
                            Hero(
                              tag: HeroTags.nowPlayingArt,
                              child: Container(
                                width: 48,
                                height: 48,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: imageUrl != null
                                      ? Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          cacheWidth: 96,
                                          cacheHeight: 96,
                                          filterQuality: FilterQuality.medium,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: colorScheme.surfaceVariant,
                                              child: Icon(
                                                Icons.music_note_rounded,
                                                color: colorScheme.onSurfaceVariant,
                                                size: 24,
                                              ),
                                            );
                                          },
                                        )
                                      : Container(
                                          color: colorScheme.surfaceVariant,
                                          child: Icon(
                                            Icons.music_note_rounded,
                                            color: colorScheme.onSurfaceVariant,
                                            size: 24,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Track info
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentTrack.name,
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currentTrack.artistsString,
                                    style: TextStyle(
                                      color: colorScheme.onSurface.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Player Selector (replacing Queue button)
                            Transform.scale(
                              scale: 0.9,
                              child: const PlayerSelector(),
                            ),
                            // Volume control (compact mute button)
                            const VolumeControl(compact: true),
                            // Playback controls for selected player
                            Hero(
                              tag: HeroTags.nowPlayingPreviousButton,
                              child: Material(
                                color: Colors.transparent,
                                child: AnimatedIconButton(
                                  icon: Icons.skip_previous_rounded,
                                  color: colorScheme.onSurface,
                                  iconSize: 26,
                                  onPressed: () async {
                                    try {
                                      await maProvider.previousTrackSelectedPlayer();
                                    } catch (e) {
                                      print('❌ Error in previous track: $e');
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error: $e')),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                            Hero(
                              tag: HeroTags.nowPlayingPlayButton,
                              child: Material(
                                color: Colors.transparent,
                                child: AnimatedIconButton(
                                  icon: selectedPlayer.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: colorScheme.onSurface,
                                  iconSize: 32,
                                  onPressed: () async {
                                    try {
                                      await maProvider.playPauseSelectedPlayer();
                                    } catch (e) {
                                      print('❌ Error in play/pause: $e');
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error: $e')),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                            Hero(
                              tag: HeroTags.nowPlayingNextButton,
                              child: Material(
                                color: Colors.transparent,
                                child: AnimatedIconButton(
                                  icon: Icons.skip_next_rounded,
                                  color: colorScheme.onSurface,
                                  iconSize: 28,
                                  onPressed: () async {
                                    try {
                                      await maProvider.nextTrackSelectedPlayer();
                                    } catch (e) {
                                      print('❌ Error in next track: $e');
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error: $e')),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
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
}
