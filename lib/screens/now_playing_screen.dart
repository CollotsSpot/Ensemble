import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';
import '../widgets/volume_control.dart';
import 'queue_screen.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  PlayerQueue? _queue;
  bool _isLoadingQueue = true;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    setState(() {
      _isLoadingQueue = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player != null && maProvider.api != null) {
      final queue = await maProvider.api!.getQueue(player.playerId);
      if (mounted) {
        setState(() {
          _queue = queue;
          _isLoadingQueue = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingQueue = false;
        });
      }
    }
  }

  Future<void> _toggleShuffle() async {
    if (_queue == null) return;
    final maProvider = context.read<MusicAssistantProvider>();
    await maProvider.toggleShuffle(_queue!.playerId);
    await _loadQueue();
  }

  Future<void> _cycleRepeat() async {
    if (_queue == null) return;
    final maProvider = context.read<MusicAssistantProvider>();
    await maProvider.cycleRepeatMode(_queue!.playerId, _queue!.repeatMode);
    await _loadQueue();
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;
    final currentTrack = maProvider.currentTrack;

    if (currentTrack == null || selectedPlayer == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1a1a1a),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note, size: 64, color: Colors.grey[700]),
              const SizedBox(height: 16),
              Text(
                'No track playing',
                style: TextStyle(color: Colors.grey[600], fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    final imageUrl = maProvider.getImageUrl(currentTrack, size: 512);

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          selectedPlayer.name,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const QueueScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              const Spacer(),
              // Album Art
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: const Color(0xFF2a2a2a),
                                child: const Icon(
                                  Icons.music_note_rounded,
                                  color: Colors.white24,
                                  size: 120,
                                ),
                              );
                            },
                          )
                        : Container(
                            color: const Color(0xFF2a2a2a),
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white24,
                              size: 120,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Track Info
              Text(
                currentTrack.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                currentTrack.artistsString,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (currentTrack.album != null) ...[
                const SizedBox(height: 4),
                Text(
                  currentTrack.album!.name,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 32),

              // Progress Bar (showing indeterminate progress while playing)
              if (currentTrack.duration != null) ...[
                Slider(
                  value: 0, // TODO: Track elapsed time from Music Assistant API
                  max: currentTrack.duration!.inSeconds.toDouble(),
                  onChanged: null, // TODO: Implement seek
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '--:--', // TODO: Show elapsed time
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      Text(
                        _formatDuration(currentTrack.duration!.inSeconds),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ] else
                // Show indeterminate progress if no duration available
                const LinearProgressIndicator(
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              const SizedBox(height: 16),

              // Playback Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Shuffle
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: _queue?.shuffle == true ? Colors.blue : Colors.white54,
                    ),
                    iconSize: 24,
                    onPressed: _isLoadingQueue ? null : _toggleShuffle,
                  ),
                  const SizedBox(width: 12),
                  // Previous
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded),
                    color: Colors.white,
                    iconSize: 42,
                    onPressed: maProvider.previousTrackSelectedPlayer,
                  ),
                  const SizedBox(width: 12),
                  // Play/Pause
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        selectedPlayer.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      color: const Color(0xFF1a1a1a),
                      iconSize: 42,
                      onPressed: maProvider.playPauseSelectedPlayer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Next
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    color: Colors.white,
                    iconSize: 42,
                    onPressed: maProvider.nextTrackSelectedPlayer,
                  ),
                  const SizedBox(width: 12),
                  // Repeat
                  IconButton(
                    icon: Icon(
                      _queue?.repeatMode == 'one'
                          ? Icons.repeat_one
                          : Icons.repeat,
                      color: _queue?.repeatMode != null && _queue!.repeatMode != 'off'
                          ? Colors.blue
                          : Colors.white54,
                    ),
                    iconSize: 24,
                    onPressed: _isLoadingQueue ? null : _cycleRepeat,
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Volume Control
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: VolumeControl(compact: false),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
