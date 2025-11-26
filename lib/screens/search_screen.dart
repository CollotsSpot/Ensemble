import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import 'album_details_screen.dart';
import 'artist_details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Map<String, List<MediaItem>> _searchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
  };
  bool _isSearching = false;
  bool _hasSearched = false;
  String _activeFilter = 'all'; // 'all', 'artists', 'albums', 'tracks'

  @override
  void initState() {
    super.initState();
    // Don't auto-focus - let user tap to focus
    // This prevents keyboard popup bug when SearchScreen is in widget tree but not visible
  }

  void requestFocus() {
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  void removeFocus() {
    if (mounted) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = {'artists': [], 'albums': [], 'tracks': []};
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    final provider = context.read<MusicAssistantProvider>();
    final results = await provider.search(query);

    setState(() {
      _searchResults = results;
      _isSearching = false;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          style: TextStyle(color: colorScheme.onSurface),
          cursorColor: colorScheme.primary,
          decoration: InputDecoration(
            hintText: 'Search music...',
            hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear_rounded, color: colorScheme.onSurface.withOpacity(0.5)),
                    onPressed: () {
                      _searchController.clear();
                      _performSearch('');
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() {});
            _performSearch(value);
          },
          onSubmitted: _performSearch,
        ),
      ),
      body: !maProvider.isConnected
          ? _buildDisconnectedView()
          : _buildSearchContent(),
    );
  }

  Widget _buildDisconnectedView() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: colorScheme.onBackground.withOpacity(0.54),
            ),
            const SizedBox(height: 16),
            Text(
              'Not connected to Music Assistant',
              style: TextStyle(
                color: colorScheme.onBackground.withOpacity(0.7),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchContent() {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isSearching) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 80,
              color: colorScheme.onBackground.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Search for artists, albums, or tracks',
              style: TextStyle(
                color: colorScheme.onBackground.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final artists = _searchResults['artists'] as List<MediaItem>? ?? [];
    final albums = _searchResults['albums'] as List<MediaItem>? ?? [];
    final tracks = _searchResults['tracks'] as List<MediaItem>? ?? [];

    final hasResults = artists.isNotEmpty || albums.isNotEmpty || tracks.isNotEmpty;

    if (!hasResults) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: colorScheme.onBackground.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                color: colorScheme.onBackground.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Filters
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildFilterChip('All', 'all'),
              const SizedBox(width: 8),
              if (artists.isNotEmpty) ...[
                _buildFilterChip('Artists', 'artists'),
                const SizedBox(width: 8),
              ],
              if (albums.isNotEmpty) ...[
                _buildFilterChip('Albums', 'albums'),
                const SizedBox(width: 8),
              ],
              if (tracks.isNotEmpty) ...[
                _buildFilterChip('Tracks', 'tracks'),
              ],
            ],
          ),
        ),
        
        // Results
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              if ((_activeFilter == 'all' || _activeFilter == 'artists') && artists.isNotEmpty) ...[
                if (_activeFilter == 'all') _buildSectionHeader('Artists', artists.length),
                ...artists.map((item) => _buildArtistTile(item as Artist)),
                const SizedBox(height: 24),
              ],
              if ((_activeFilter == 'all' || _activeFilter == 'albums') && albums.isNotEmpty) ...[
                if (_activeFilter == 'all') _buildSectionHeader('Albums', albums.length),
                ...albums.map((item) => _buildAlbumTile(item as Album)),
                const SizedBox(height: 24),
              ],
              if ((_activeFilter == 'all' || _activeFilter == 'tracks') && tracks.isNotEmpty) ...[
                if (_activeFilter == 'all') _buildSectionHeader('Tracks', tracks.length),
                ...tracks.map((item) => _buildTrackTile(item as Track)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _activeFilter == value;
    final colorScheme = Theme.of(context).colorScheme;
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _activeFilter = value;
        });
      },
      selectedColor: colorScheme.primaryContainer,
      checkmarkColor: colorScheme.onPrimaryContainer,
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onBackground,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildArtistTile(Artist artist) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(artist, size: 128);
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: colorScheme.surfaceVariant,
        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
        child: imageUrl == null
            ? Icon(Icons.person_rounded, color: colorScheme.onSurfaceVariant)
            : null,
      ),
      title: Text(
        artist.name,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Artist',
        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArtistDetailsScreen(artist: artist),
          ),
        );
      },
    );
  }

  Widget _buildAlbumTile(Album album) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(album, size: 128);
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          image: imageUrl != null
              ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: imageUrl == null
            ? Icon(Icons.album_rounded, color: colorScheme.onSurfaceVariant)
            : null,
      ),
      title: Text(
        album.name,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        album.artistsString,
        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumDetailsScreen(album: album),
          ),
        );
      },
    );
  }

  Widget _buildTrackTile(Track track) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = track.album != null
        ? maProvider.getImageUrl(track.album!, size: 128)
        : null;
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          image: imageUrl != null
              ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: imageUrl == null
            ? Icon(Icons.music_note_rounded, color: colorScheme.onSurfaceVariant)
            : null,
      ),
      title: Text(
        track.name,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artistsString,
        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: track.duration != null
          ? Text(
              _formatDuration(track.duration!),
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
            )
          : null,
      onTap: () => _playTrack(track),
    );
  }

  Future<void> _playTrack(Track track) async {
    final maProvider = context.read<MusicAssistantProvider>();

    if (maProvider.selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No player selected')),
      );
      return;
    }

    // Use Music Assistant to play the track on the selected player
    await maProvider.playTrack(
      maProvider.selectedPlayer!.playerId,
      track,
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
