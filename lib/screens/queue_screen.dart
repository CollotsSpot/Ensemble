import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  PlayerQueue? _queue;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to safely access context after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadQueue();
    });
  }

  Future<void> _loadQueue() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final maProvider = context.read<MusicAssistantProvider>();
      final player = maProvider.selectedPlayer;

      if (player != null && maProvider.api != null) {
        final queue = await maProvider.api!.getQueue(player.playerId);
        if (mounted) {
          setState(() {
            _queue = queue;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'No player selected';
          });
        }
      }
    } catch (e) {
      print('❌ QueueScreen error loading queue: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load queue: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          player != null ? '${player.name} Queue' : 'Queue',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadQueue,
          ),
        ],
      ),
      body: _buildBody(maProvider),
    );
  }

  Widget _buildBody(MusicAssistantProvider maProvider) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.red[300], fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadQueue,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (maProvider.selectedPlayer == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.speaker_group, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              'No player selected',
              style: TextStyle(color: Colors.grey[600], fontSize: 18),
            ),
          ],
        ),
      );
    }

    if (_queue == null || _queue!.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              'Queue is empty',
              style: TextStyle(color: Colors.grey[600], fontSize: 18),
            ),
          ],
        ),
      );
    }

    // Filter to show only current and upcoming items (not history)
    final currentIndex = _queue!.currentIndex ?? 0;
    final upcomingItems = _queue!.items.sublist(currentIndex);

    if (upcomingItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              'No upcoming tracks',
              style: TextStyle(color: Colors.grey[600], fontSize: 18),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Queue info
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.queue_music, color: Colors.grey[400]),
              const SizedBox(width: 8),
              Text(
                '${upcomingItems.length} track${upcomingItems.length != 1 ? 's' : ''} in queue',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),

        // Queue items (current + upcoming only)
        Expanded(
          child: ListView.builder(
            itemCount: upcomingItems.length,
            itemBuilder: (context, index) {
              final item = upcomingItems[index];
              final actualIndex = currentIndex + index;
              final isCurrentItem = index == 0; // First item in filtered list is current

              return _buildQueueItem(item, actualIndex, isCurrentItem, maProvider);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQueueItem(
    QueueItem item,
    int index,
    bool isCurrentItem,
    MusicAssistantProvider maProvider,
  ) {
    final imageUrl = maProvider.api?.getImageUrl(item.track, size: 80);

    return Dismissible(
      key: Key(item.queueItemId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16.0),
        color: Colors.red[900],
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        // TODO: Implement queue item removal via API
        setState(() {
          _queue!.items.removeAt(index);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${item.track.name}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                setState(() {
                  _queue!.items.insert(index, item);
                });
              },
            ),
          ),
        );
      },
      child: Container(
        color: isCurrentItem ? Colors.blue.withOpacity(0.1) : null,
        child: ListTile(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle (visual only for now - reordering not implemented)
              Icon(
                Icons.drag_handle,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 8),
              // Album art
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 48,
                            height: 48,
                            color: Colors.grey[800],
                            child: const Icon(Icons.music_note, size: 24),
                          );
                        },
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        color: Colors.grey[800],
                        child: const Icon(Icons.music_note, size: 24),
                      ),
              ),
            ],
          ),
          title: Text(
            item.track.name,
            style: TextStyle(
              color: isCurrentItem ? Colors.blue : Colors.white,
              fontWeight: isCurrentItem ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: item.track.artists != null && item.track.artists!.isNotEmpty
              ? Text(
                  item.track.artists!.first.name,
                  style: TextStyle(
                    color: isCurrentItem ? Colors.blue[200] : Colors.grey[400],
                  ),
                )
              : null,
          trailing: isCurrentItem
              ? Icon(Icons.play_arrow, color: Colors.blue[400])
              : null,
        ),
      ),
    );
  }
}
