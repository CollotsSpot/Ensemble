import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/music_player_provider.dart';
import '../models/audio_track.dart';

class AlbumDetailsScreen extends StatefulWidget {
  final Album album;

  const AlbumDetailsScreen({super.key, required this.album});

  @override
  State<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends State<AlbumDetailsScreen> {
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final provider = context.read<MusicAssistantProvider>();
    final tracks = await provider.getAlbumTracks(
      widget.album.provider,
      widget.album.itemId,
    );

    setState(() {
      _tracks = tracks;
      _isLoading = false;
    });
  }

  Future<void> _playAlbum() async {
    if (_tracks.isEmpty) return;

    final maProvider = context.read<MusicAssistantProvider>();
    final playerProvider = context.read<MusicPlayerProvider>();

    // Convert Music Assistant tracks to AudioTrack objects with stream URLs
    final audioTracks = _tracks.map((track) {
      final streamUrl = maProvider.getStreamUrl(
        track.provider,
        track.itemId,
        uri: track.uri,
        providerMappings: track.providerMappings,
      );
      return AudioTrack(
        id: track.itemId,
        title: track.name,
        artist: track.artistsString,
        album: widget.album.name,
        filePath: streamUrl,
        duration: track.duration,
      );
    }).toList();

    await playerProvider.setPlaylist(audioTracks);
    await playerProvider.play();

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _playTrack(int index) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final playerProvider = context.read<MusicPlayerProvider>();

    try {
      // 1. Get available players
      final players = await maProvider.getPlayers();
      if (players.isEmpty) {
        _showError('No players available');
        return;
      }

      // 2. Find the built-in player or use first available
      final player = players.firstWhere(
        (p) => p.playerId.contains('builtin') && p.available,
        orElse: () => players.firstWhere((p) => p.available, orElse: () => players.first),
      );

      print('🎵 Using player: ${player.name} (${player.playerId})');

      // 3. Queue the tracks via Music Assistant WebSocket
      await maProvider.playTracks(player.playerId, _tracks, startIndex: index);
      print('✓ Tracks queued in Music Assistant');

      // 4. Wait a moment for Music Assistant to process the queue
      await Future.delayed(const Duration(milliseconds: 500));

      // 5. Get the stream URL from the queue
      final streamUrl = await maProvider.getCurrentStreamUrl(player.playerId);
      if (streamUrl == null) {
        _showError('Failed to get stream URL from queue');
        return;
      }

      print('🎵 Stream URL from queue: $streamUrl');

      // 6. Convert tracks to AudioTrack objects with the queue-based stream URL
      final audioTracks = _tracks.map((track) {
        return AudioTrack(
          id: track.itemId,
          title: track.name,
          artist: track.artistsString,
          album: widget.album.name,
          filePath: streamUrl, // All tracks will use queue-based streaming
          duration: track.duration,
        );
      }).toList();

      // 7. Play via local audio player
      await playerProvider.setPlaylist(audioTracks, initialIndex: index);
      await playerProvider.play();

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error playing track: $e');
      _showError('Failed to play track: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.album, size: 512);

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: const Color(0xFF1a1a1a),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
              color: Colors.white,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      image: imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(imageUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: imageUrl == null
                        ? const Icon(
                            Icons.album_rounded,
                            size: 100,
                            color: Colors.white54,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.album.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.album.artistsString,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading || _tracks.isEmpty ? null : _playAlbum,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play Album'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1a1a1a),
                        disabledBackgroundColor: Colors.white38,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Tracks',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else if (_tracks.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'No tracks found',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${track.position ?? index + 1}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      track.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artistsString,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: track.duration != null
                        ? Text(
                            _formatDuration(track.duration!),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          )
                        : null,
                    onTap: () => _playTrack(index),
                  );
                },
                childCount: _tracks.length,
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
