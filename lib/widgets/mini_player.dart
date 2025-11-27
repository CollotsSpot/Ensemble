import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/now_playing_screen.dart';
import '../screens/queue_screen.dart';
import 'volume_control.dart';
import '../constants/hero_tags.dart';
import 'animated_icon_button.dart';

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
          child: Container(
            height: 80,
            margin: const EdgeInsets.only(left: 8, right: 8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Hero(
              tag: HeroTags.nowPlayingBackground,
              transitionOnUserGestures: true,
              flightShuttleBuilder: (context, animation, direction, fromContext, toContext) {
                return Material(
                  color: Colors.transparent,
                  child: toContext.widget,
                );
              },
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: [
                        // Album art with Hero animation
                        Hero(
                          tag: HeroTags.nowPlayingArt,
                          transitionOnUserGestures: true,
                          child: Container(
                            width: 72,
                            height: 72,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentTrack.artistsString,
                                style: TextStyle(
                                  color: colorScheme.onSurface.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Queue button
                        IconButton(
                          icon: const Icon(Icons.queue_music),
                          color: colorScheme.onSurface.withOpacity(0.7),
                          iconSize: 26,
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const QueueScreen(),
                              ),
                            );
                          },
                        ),
                        // Playback controls for selected player
                        Hero(
                          tag: HeroTags.nowPlayingPreviousButton,
                          transitionOnUserGestures: true,
                          child: Material(
                            color: Colors.transparent,
                            child: AnimatedIconButton(
                              icon: Icons.skip_previous_rounded,
                              color: colorScheme.onSurface,
                              iconSize: 30,
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
                          transitionOnUserGestures: true,
                          child: Material(
                            color: Colors.transparent,
                            child: AnimatedIconButton(
                              icon: selectedPlayer.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: colorScheme.onSurface,
                              iconSize: 38,
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
                          transitionOnUserGestures: true,
                          child: Material(
                            color: Colors.transparent,
                            child: AnimatedIconButton(
                              icon: Icons.skip_next_rounded,
                              color: colorScheme.onSurface,
                              iconSize: 32,
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
              ),
            ),
          ),
        );
      },
    );
  }
}
