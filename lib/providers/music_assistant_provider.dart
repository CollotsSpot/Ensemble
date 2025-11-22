import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';

class MusicAssistantProvider with ChangeNotifier {
  MusicAssistantAPI? _api;
  MAConnectionState _connectionState = MAConnectionState.disconnected;
  String? _serverUrl;

  List<Artist> _artists = [];
  List<Album> _albums = [];
  List<Track> _tracks = [];
  bool _isLoading = false;
  String? _error;

  MAConnectionState get connectionState => _connectionState;
  String? get serverUrl => _serverUrl;
  List<Artist> get artists => _artists;
  List<Album> get albums => _albums;
  List<Track> get tracks => _tracks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _connectionState == MAConnectionState.connected;

  MusicAssistantProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    _serverUrl = await SettingsService.getServerUrl();
    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      await connectToServer(_serverUrl!);
    }
  }

  Future<void> connectToServer(String serverUrl) async {
    try {
      _error = null;
      _serverUrl = serverUrl;
      await SettingsService.setServerUrl(serverUrl);

      // Disconnect existing connection
      await _api?.disconnect();

      _api = MusicAssistantAPI(serverUrl);

      // Listen to connection state changes
      _api!.connectionState.listen((state) {
        _connectionState = state;
        notifyListeners();

        if (state == MAConnectionState.connected) {
          // Auto-load library when connected
          loadLibrary();
        }
      });

      await _api!.connect();
      notifyListeners();
    } catch (e) {
      _error = 'Connection failed: $e';
      _connectionState = MAConnectionState.error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _api?.disconnect();
    _connectionState = MAConnectionState.disconnected;
    _artists = [];
    _albums = [];
    _tracks = [];
    notifyListeners();
  }

  Future<void> loadLibrary() async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Load artists, albums, and tracks in parallel
      final results = await Future.wait([
        _api!.getArtists(limit: 100),
        _api!.getAlbums(limit: 100),
        _api!.getTracks(limit: 100),
      ]);

      _artists = results[0] as List<Artist>;
      _albums = results[1] as List<Album>;
      _tracks = results[2] as List<Track>;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load library: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadArtists({int? limit, int? offset, String? search}) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _artists = await _api!.getArtists(
        limit: limit,
        offset: offset,
        search: search,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load artists: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAlbums({
    int? limit,
    int? offset,
    String? search,
    String? artistId,
  }) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _albums = await _api!.getAlbums(
        limit: limit,
        offset: offset,
        search: search,
        artistId: artistId,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load albums: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Track>> getAlbumTracks(String provider, String itemId) async {
    if (!isConnected) return [];

    try {
      return await _api!.getAlbumTracks(provider, itemId);
    } catch (e) {
      print('Failed to load album tracks: $e');
      return [];
    }
  }

  Future<Map<String, List<MediaItem>>> search(String query) async {
    if (!isConnected) {
      return {'artists': [], 'albums': [], 'tracks': []};
    }

    try {
      return await _api!.search(query);
    } catch (e) {
      print('Search failed: $e');
      return {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  String getStreamUrl(String provider, String itemId, {String? uri, List<ProviderMapping>? providerMappings}) {
    return _api?.getStreamUrl(provider, itemId, uri: uri, providerMappings: providerMappings) ?? '';
  }

  String? getImageUrl(MediaItem item, {int size = 256}) {
    return _api?.getImageUrl(item, size: size);
  }

  // ============================================================================
  // PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  Future<List<Player>> getPlayers() async {
    return await _api?.getPlayers() ?? [];
  }

  Future<PlayerQueue?> getQueue(String playerId) async {
    return await _api?.getQueue(playerId);
  }

  Future<void> playTrack(String playerId, Track track) async {
    await _api?.playTrack(playerId, track);
  }

  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex}) async {
    await _api?.playTracks(playerId, tracks, startIndex: startIndex);
  }

  Future<String?> getCurrentStreamUrl(String playerId) async {
    return await _api?.getCurrentStreamUrl(playerId);
  }

  Future<void> pausePlayer(String playerId) async {
    await _api?.pausePlayer(playerId);
  }

  Future<void> resumePlayer(String playerId) async {
    await _api?.resumePlayer(playerId);
  }

  Future<void> nextTrack(String playerId) async {
    await _api?.nextTrack(playerId);
  }

  Future<void> previousTrack(String playerId) async {
    await _api?.previousTrack(playerId);
  }

  Future<void> stopPlayer(String playerId) async {
    await _api?.stopPlayer(playerId);
  }

  // ============================================================================
  // END PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  @override
  void dispose() {
    _api?.dispose();
    super.dispose();
  }
}
