import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import '../widgets/global_player_overlay.dart';
import 'artist_details_screen.dart';

class AlbumDetailsScreen extends StatefulWidget {
  final Album album;
  final String? heroTagSuffix;

  const AlbumDetailsScreen({
    super.key, 
    required this.album,
    this.heroTagSuffix,
  });

  @override
  State<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends State<AlbumDetailsScreen> with SingleTickerProviderStateMixin {
  final _logger = DebugLogger();
  List<Track> _tracks = [];
  bool _isLoading = true;
  bool _isFavorite = false;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  int? _expandedTrackIndex;
  bool _isDescriptionExpanded = false;
  String? _albumDescription;
  
  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.album.favorite ?? false;
    _loadTracks();
    _extractColors();
    _loadAlbumDescription();
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.album, size: 512);

    if (imageUrl == null) return;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        NetworkImage(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });
      }
    } catch (e) {
      _logger.log('Failed to extract colors for album: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api == null) return;

    try {
      final newState = await maProvider.api!.toggleFavorite(
        'album',
        widget.album.itemId,
        widget.album.provider,
      );

      setState(() {
        _isFavorite = newState;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFavorite ? 'Added to favorites' : 'Removed from favorites',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error toggling favorite: $e');
    }
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

    try {
      // Use the selected player
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError('No player selected');
        return;
      }

      _logger.log('Queueing album on ${player.name}: ${player.playerId}');

      // Queue all tracks via Music Assistant
      await maProvider.playTracks(player.playerId, _tracks, startIndex: 0);
      _logger.log('Album queued on ${player.name}');

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      _logger.log('Error playing album: $e');
      _showError('Failed to play album: $e');
    }
  }

  Future<void> _playTrack(int index) async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      // Use the selected player
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError('No player selected');
        return;
      }

      _logger.log('Queueing tracks on ${player.name} starting at index $index');

      // Queue tracks starting at the selected index
      await maProvider.playTracks(player.playerId, _tracks, startIndex: index);
      _logger.log('Tracks queued on ${player.name}');

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      _logger.log('Error playing track: $e');
      _showError('Failed to play track: $e');
    }
  }

  Future<void> _addAlbumToQueue() async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError('No player selected');
        return;
      }

      _logger.log('Adding album to queue on ${player.name}');

      // Add all tracks to queue without clearing
      await maProvider.playTracks(player.playerId, _tracks, startIndex: 0, clearQueue: false);
      _logger.log('Album added to queue on ${player.name}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Album added to queue'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error adding album to queue: $e');
      _showError('Failed to add album to queue: $e');
    }
  }

  void _addTrackToQueue(BuildContext context, int index) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;

    // Slide mini player down out of the way
    GlobalPlayerOverlay.hidePlayer();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              'Add to queue on...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No players available'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: players.length,
                  itemBuilder: (context, playerIndex) {
                    final player = players[playerIndex];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          // Add tracks from this index onwards to queue
                          await maProvider.playTracks(
                            player.playerId,
                            _tracks,
                            startIndex: index,
                            clearQueue: false,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Tracks added to queue'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        } catch (e) {
                          _logger.log('Error adding to queue: $e');
                          _showError('Failed to add to queue: $e');
                        }
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ).whenComplete(() {
      // Slide mini player back up when sheet is dismissed
      GlobalPlayerOverlay.showPlayer();
    });
  }

  void _navigateToArtist() {
    // Navigate to the first artist if available
    if (widget.album.artists != null && widget.album.artists!.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ArtistDetailsScreen(artist: widget.album.artists!.first),
        ),
      );
    }
  }

  Future<void> _loadAlbumDescription() async {
    final artistName = widget.album.artists?.firstOrNull?.name ?? '';
    final albumName = widget.album.name;

    if (artistName.isEmpty || albumName.isEmpty) return;

    final description = await MetadataService.getAlbumDescription(
      artistName,
      albumName,
      widget.album.metadata,
    );

    if (mounted) {
      setState(() {
        _albumDescription = description;
      });
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
    final themeProvider = context.watch<ThemeProvider>();
    final imageUrl = maProvider.getImageUrl(widget.album, size: 512);
    
    // Determine if we should use adaptive theme colors
    final useAdaptiveTheme = themeProvider.adaptiveTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get the color scheme to use
    ColorScheme? adaptiveScheme;
    if (useAdaptiveTheme) {
      adaptiveScheme = isDark ? _darkColorScheme : _lightColorScheme;
    }

    // Use adaptive scheme if available, otherwise use global theme
    final colorScheme = adaptiveScheme ?? Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 350, // Increased height for bigger art
            pinned: true,
            backgroundColor: colorScheme.background,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
              color: colorScheme.onBackground,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  Hero(
                    tag: HeroTags.albumCover + (widget.album.uri ?? widget.album.itemId) + _heroTagSuffix,
                    child: Container(
                      width: 280, // Increased size
                      height: 280,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(16), // Slightly more rounded
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
                          ? Icon(
                              Icons.album_rounded,
                              size: 120,
                              color: colorScheme.onSurfaceVariant,
                            )
                          : null,
                    ),
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
                  Hero(
                    tag: HeroTags.albumTitle + (widget.album.uri ?? widget.album.itemId) + _heroTagSuffix,
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.album.name,
                        style: textTheme.headlineMedium?.copyWith(
                          color: colorScheme.onBackground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Hero(
                    tag: HeroTags.artistName + (widget.album.uri ?? widget.album.itemId) + _heroTagSuffix,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _navigateToArtist(),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(
                            widget.album.artistsString,
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onBackground.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Album Description
                  if (_albumDescription != null && _albumDescription!.isNotEmpty) ...[
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isDescriptionExpanded = !_isDescriptionExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _albumDescription!,
                          style: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onBackground.withOpacity(0.8),
                          ),
                          maxLines: _isDescriptionExpanded ? null : 2,
                          overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      // Main Play Button
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading || _tracks.isEmpty ? null : _playAlbum,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              disabledBackgroundColor: colorScheme.primary.withOpacity(0.38),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // "Play on..." Button (Square)
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: _isLoading || _tracks.isEmpty ? null : () => _showPlayOnMenu(context),
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Icon(Icons.speaker_group_outlined),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // "Add Album to Queue" Button (Square)
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: _isLoading || _tracks.isEmpty ? null : _addAlbumToQueue,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Icon(Icons.playlist_add),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Favorite Button
                      Container(
                        height: 50,
                        width: 50,
                        decoration: BoxDecoration(
                          color: _isFavorite ? colorScheme.errorContainer : colorScheme.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _toggleFavorite,
                          icon: Icon(
                            _isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: _isFavorite ? colorScheme.error : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tracks',
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (_isLoading)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: colorScheme.primary),
              ),
            )
          else if (_tracks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No tracks found',
                  style: TextStyle(
                    color: colorScheme.onBackground.withOpacity(0.54),
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
                  final isExpanded = _expandedTrackIndex == index;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${track.position ?? index + 1}',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          track.name,
                          style: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          track.artistsString,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: track.duration != null
                            ? Text(
                                _formatDuration(track.duration!),
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.5),
                                ),
                              )
                            : null,
                        onTap: () {
                          if (isExpanded) {
                            // Single tap to collapse when expanded
                            setState(() {
                              _expandedTrackIndex = null;
                            });
                          } else {
                            _playTrack(index);
                          }
                        },
                        onLongPress: () {
                          setState(() {
                            _expandedTrackIndex = isExpanded ? null : index;
                          });
                        },
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: isExpanded
                            ? Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: FilledButton.tonal(
                                          onPressed: () => _showPlayRadioMenu(context, index),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: colorScheme.tertiaryContainer,
                                            foregroundColor: colorScheme.onTertiaryContainer,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text('Start radio'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: FilledButton.tonal(
                                          onPressed: () => _addTrackToQueue(context, index),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: colorScheme.secondaryContainer,
                                            foregroundColor: colorScheme.onSecondaryContainer,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text('Add to queue'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  );
                },
                childCount: _tracks.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)), // Extra space for mini player
        ],
      ),
    );
  }

  void _showPlayAlbumFromHereMenu(BuildContext context, int startIndex) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;

    // Slide mini player down out of the way
    GlobalPlayerOverlay.hidePlayer();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              'Play on...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No players available'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () {
                        Navigator.pop(context);
                        // Set this as the active player
                        maProvider.selectPlayer(player);
                        // Play album from this track onwards
                        maProvider.playTracks(
                          player.playerId,
                          _tracks,
                          startIndex: startIndex,
                        );
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ).whenComplete(() {
      // Slide mini player back up when sheet is dismissed
      GlobalPlayerOverlay.showPlayer();
    });
  }

  void _showPlayRadioMenu(BuildContext context, int trackIndex) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;
    final track = _tracks[trackIndex];

    // Slide mini player down out of the way
    GlobalPlayerOverlay.hidePlayer();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              'Play on...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No players available'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () {
                        Navigator.pop(context);
                        // Set this as the active player
                        maProvider.selectPlayer(player);
                        // Play radio based on this track
                        maProvider.playRadio(
                          player.playerId,
                          track,
                        );
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ).whenComplete(() {
      // Slide mini player back up when sheet is dismissed
      GlobalPlayerOverlay.showPlayer();
    });
  }

  void _showPlayOnMenu(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;

    // Slide mini player down out of the way
    GlobalPlayerOverlay.hidePlayer();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              'Play on...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No players available'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () {
                        Navigator.pop(context);
                        // Set this as the active player
                        maProvider.selectPlayer(player);
                        // Play on this specific player
                        maProvider.playTracks(player.playerId, _tracks);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ).whenComplete(() {
      // Slide mini player back up when sheet is dismissed
      GlobalPlayerOverlay.showPlayer();
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
