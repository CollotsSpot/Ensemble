import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import 'database_service.dart';
import 'debug_logger.dart';
import 'music_assistant_api.dart';
import 'settings_service.dart';

/// Sync status for UI indicators
enum SyncStatus {
  idle,
  syncing,
  completed,
  error,
}

/// Service for background library synchronization
/// Loads from database cache first, then syncs from MA API in background
class SyncService with ChangeNotifier {
  static SyncService? _instance;
  static final _logger = DebugLogger();

  SyncService._();

  static SyncService get instance {
    _instance ??= SyncService._();
    return _instance!;
  }

  DatabaseService get _db => DatabaseService.instance;

  // Sync state
  SyncStatus _status = SyncStatus.idle;
  String? _lastError;
  DateTime? _lastSyncTime;
  bool _isSyncing = false;

  // Cached data (loaded from DB, updated after sync)
  List<Album> _cachedAlbums = [];
  List<Artist> _cachedArtists = [];
  List<Audiobook> _cachedAudiobooks = [];
  List<Playlist> _cachedPlaylists = [];

  // Getters
  SyncStatus get status => _status;
  String? get lastError => _lastError;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isSyncing => _isSyncing;
  List<Album> get cachedAlbums => _cachedAlbums;
  List<Artist> get cachedArtists => _cachedArtists;
  List<Audiobook> get cachedAudiobooks => _cachedAudiobooks;
  List<Playlist> get cachedPlaylists => _cachedPlaylists;
  bool get hasCache => _cachedAlbums.isNotEmpty || _cachedArtists.isNotEmpty ||
                       _cachedAudiobooks.isNotEmpty || _cachedPlaylists.isNotEmpty;

  /// Load library data from database cache (instant)
  /// Call this on app startup for immediate data
  Future<void> loadFromCache() async {
    if (!_db.isInitialized) {
      _logger.log('⚠️ Database not initialized, skipping cache load');
      return;
    }

    try {
      _logger.log('📦 Loading library from database cache...');

      // Load albums from cache
      final albumData = await _db.getCachedItems('album');
      _cachedAlbums = albumData.map((data) {
        try {
          return Album.fromJson(data);
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached album: $e');
          return null;
        }
      }).whereType<Album>().toList();

      // Load artists from cache
      final artistData = await _db.getCachedItems('artist');
      _cachedArtists = artistData.map((data) {
        try {
          return Artist.fromJson(data);
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached artist: $e');
          return null;
        }
      }).whereType<Artist>().toList();

      // Load audiobooks from cache
      final audiobookData = await _db.getCachedItems('audiobook');
      _cachedAudiobooks = audiobookData.map((data) {
        try {
          return Audiobook.fromJson(data);
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached audiobook: $e');
          return null;
        }
      }).whereType<Audiobook>().toList();

      // Load playlists from cache
      final playlistData = await _db.getCachedItems('playlist');
      _cachedPlaylists = playlistData.map((data) {
        try {
          return Playlist.fromJson(data);
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached playlist: $e');
          return null;
        }
      }).whereType<Playlist>().toList();

      _logger.log('📦 Loaded ${_cachedAlbums.length} albums, ${_cachedArtists.length} artists, '
                  '${_cachedAudiobooks.length} audiobooks, ${_cachedPlaylists.length} playlists from cache');
      notifyListeners();
    } catch (e) {
      _logger.log('❌ Failed to load from cache: $e');
    }
  }

  /// Sync library data from MA API in background
  /// Updates database cache and notifies listeners when complete
  /// If provider is specified, only fetch items from that provider (server-side filtering)
  Future<void> syncFromApi(MusicAssistantAPI api, {bool force = false, String? provider}) async {
    if (_isSyncing) {
      _logger.log('🔄 Sync already in progress, skipping');
      return;
    }

    if (!_db.isInitialized) {
      _logger.log('⚠️ Database not initialized, skipping sync');
      return;
    }

    // Check if sync is needed (default: every 5 minutes)
    if (!force) {
      final albumsNeedSync = await _db.needsSync('albums', maxAge: const Duration(minutes: 5));
      final artistsNeedSync = await _db.needsSync('artists', maxAge: const Duration(minutes: 5));
      final audiobooksNeedSync = await _db.needsSync('audiobooks', maxAge: const Duration(minutes: 5));
      final playlistsNeedSync = await _db.needsSync('playlists', maxAge: const Duration(minutes: 5));

      if (!albumsNeedSync && !artistsNeedSync && !audiobooksNeedSync && !playlistsNeedSync) {
        _logger.log('✅ Cache is fresh, skipping sync');
        return;
      }
    }

    _isSyncing = true;
    _status = SyncStatus.syncing;
    _lastError = null;
    notifyListeners();

    try {
      _logger.log('🔄 Starting background library sync (provider=$provider)...');

      // Read artist filter setting - when ON, only fetch artists that have albums
      final showOnlyArtistsWithAlbums = await SettingsService.getShowOnlyArtistsWithAlbums();
      _logger.log('🎨 Sync using albumArtistsOnly: $showOnlyArtistsWithAlbums, provider: $provider');

      // Fetch fresh data from MA API (in parallel for speed)
      // If provider is specified, filter to only that provider's library items
      final results = await Future.wait([
        api.getAlbums(limit: 1000, provider: provider),
        api.getArtists(limit: 1000, albumArtistsOnly: showOnlyArtistsWithAlbums, provider: provider),
        api.getAudiobooks(limit: 1000),
        api.getPlaylists(limit: 1000),
      ]);

      final albums = results[0] as List<Album>;
      final artists = results[1] as List<Artist>;
      final audiobooks = results[2] as List<Audiobook>;
      final playlists = results[3] as List<Playlist>;

      _logger.log('📥 Fetched ${albums.length} albums, ${artists.length} artists, '
                  '${audiobooks.length} audiobooks, ${playlists.length} playlists from MA');

      // Clear old cache before saving fresh data (removes stale items)
      await _db.clearCacheForType('album');
      await _db.clearCacheForType('artist');
      await _db.clearCacheForType('audiobook');
      await _db.clearCacheForType('playlist');

      // Save to database cache
      await _saveAlbumsToCache(albums);
      await _saveArtistsToCache(artists);
      await _saveAudiobooksToCache(audiobooks);
      await _savePlaylistsToCache(playlists);

      // Update sync metadata
      await _db.updateSyncMetadata('albums', albums.length);
      await _db.updateSyncMetadata('artists', artists.length);
      await _db.updateSyncMetadata('audiobooks', audiobooks.length);
      await _db.updateSyncMetadata('playlists', playlists.length);

      // Update in-memory cache
      _cachedAlbums = albums;
      _cachedArtists = artists;
      _cachedAudiobooks = audiobooks;
      _cachedPlaylists = playlists;
      _lastSyncTime = DateTime.now();
      _status = SyncStatus.completed;

      _logger.log('✅ Library sync complete');
    } catch (e) {
      _logger.log('❌ Library sync failed: $e');
      _status = SyncStatus.error;
      _lastError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Save albums to database cache
  Future<void> _saveAlbumsToCache(List<Album> albums) async {
    for (final album in albums) {
      try {
        await _db.cacheItem(
          itemType: 'album',
          itemId: album.itemId,
          data: album.toJson(),
        );
      } catch (e) {
        _logger.log('⚠️ Failed to cache album ${album.name}: $e');
      }
    }
    _logger.log('💾 Saved ${albums.length} albums to cache');
  }

  /// Save artists to database cache
  Future<void> _saveArtistsToCache(List<Artist> artists) async {
    for (final artist in artists) {
      try {
        await _db.cacheItem(
          itemType: 'artist',
          itemId: artist.itemId,
          data: artist.toJson(),
        );
      } catch (e) {
        _logger.log('⚠️ Failed to cache artist ${artist.name}: $e');
      }
    }
    _logger.log('💾 Saved ${artists.length} artists to cache');
  }

  /// Save audiobooks to database cache
  Future<void> _saveAudiobooksToCache(List<Audiobook> audiobooks) async {
    for (final audiobook in audiobooks) {
      try {
        await _db.cacheItem(
          itemType: 'audiobook',
          itemId: audiobook.itemId,
          data: audiobook.toJson(),
        );
      } catch (e) {
        _logger.log('⚠️ Failed to cache audiobook ${audiobook.name}: $e');
      }
    }
    _logger.log('💾 Saved ${audiobooks.length} audiobooks to cache');
  }

  /// Save playlists to database cache
  Future<void> _savePlaylistsToCache(List<Playlist> playlists) async {
    for (final playlist in playlists) {
      try {
        await _db.cacheItem(
          itemType: 'playlist',
          itemId: playlist.itemId,
          data: playlist.toJson(),
        );
      } catch (e) {
        _logger.log('⚠️ Failed to cache playlist ${playlist.name}: $e');
      }
    }
    _logger.log('💾 Saved ${playlists.length} playlists to cache');
  }

  /// Force a fresh sync (for pull-to-refresh)
  Future<void> forceSync(MusicAssistantAPI api, {String? provider}) async {
    await syncFromApi(api, force: true, provider: provider);
  }

  /// Clear all cached data and reset sync state
  /// This allows a fresh sync to start even if one was in progress
  Future<void> clearCache() async {
    if (!_db.isInitialized) return;

    await _db.clearAllCache();
    _cachedAlbums = [];
    _cachedArtists = [];
    _cachedAudiobooks = [];
    _cachedPlaylists = [];
    _lastSyncTime = null;
    _isSyncing = false;  // Reset so a new sync can start
    _status = SyncStatus.idle;
    notifyListeners();
    _logger.log('🗑️ Library cache cleared (sync state reset)');
  }

  /// Get albums (from cache or empty if not loaded)
  List<Album> getAlbums() => _cachedAlbums;

  /// Get artists (from cache or empty if not loaded)
  List<Artist> getArtists() => _cachedArtists;

  /// Get audiobooks (from cache or empty if not loaded)
  List<Audiobook> getAudiobooks() => _cachedAudiobooks;

  /// Get playlists (from cache or empty if not loaded)
  List<Playlist> getPlaylists() => _cachedPlaylists;

  /// Check if we have data available (from cache or sync)
  bool get hasData => _cachedAlbums.isNotEmpty || _cachedArtists.isNotEmpty ||
                      _cachedAudiobooks.isNotEmpty || _cachedPlaylists.isNotEmpty;
}
