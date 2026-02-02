import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'device_id_service.dart';
import 'secure_storage_service.dart';

class SettingsService {
  // Cached SharedPreferences instance for performance
  static SharedPreferences? _prefsCache;

  /// Initialize the SharedPreferences cache. Call this early in app startup.
  static Future<void> initialize() async {
    _prefsCache ??= await SharedPreferences.getInstance();
  }

  /// Get SharedPreferences instance, using cache if available.
  static Future<SharedPreferences> _getPrefs() async {
    return _prefsCache ??= await SharedPreferences.getInstance();
  }

  // ============ GENERIC HELPERS ============
  // These reduce boilerplate for repetitive getter/setter patterns

  /// Get a string value, with optional default
  static Future<String?> _getString(String key, {String? defaultValue}) async {
    final prefs = await _getPrefs();
    return prefs.getString(key) ?? defaultValue;
  }

  /// Set a string value, removing if null/empty when removeIfEmpty is true
  static Future<void> _setString(String key, String? value, {bool removeIfEmpty = false}) async {
    final prefs = await _getPrefs();
    if (removeIfEmpty && (value == null || value.isEmpty)) {
      await prefs.remove(key);
    } else if (value != null) {
      await prefs.setString(key, value);
    }
  }

  /// Get a bool value with default
  static Future<bool> _getBool(String key, {bool defaultValue = false}) async {
    final prefs = await _getPrefs();
    return prefs.getBool(key) ?? defaultValue;
  }

  /// Set a bool value
  static Future<void> _setBool(String key, bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(key, value);
  }

  /// Get an int value, with optional default
  static Future<int?> _getInt(String key, {int? defaultValue}) async {
    final prefs = await _getPrefs();
    return prefs.getInt(key) ?? defaultValue;
  }

  /// Set an int value, removing if null
  static Future<void> _setInt(String key, int? value) async {
    final prefs = await _getPrefs();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, value);
    }
  }

  /// Remove a key
  static Future<void> _remove(String key) async {
    final prefs = await _getPrefs();
    await prefs.remove(key);
  }

  static const String _keyServerUrl = 'server_url';
  static const String _keyAuthServerUrl = 'auth_server_url';
  static const String _keyWebSocketPort = 'websocket_port';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyMaAuthToken = 'ma_auth_token'; // Music Assistant native auth token
  static const String _keyAuthCredentials = 'auth_credentials'; // NEW: Serialized auth strategy credentials
  static const String _keyUsername = 'username';
  static const String _keyPassword = 'password';
  static const String _keyBuiltinPlayerId = 'local_player_id'; // Unified with DeviceIdService
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyUseMaterialTheme = 'use_material_theme';
  static const String _keyAdaptiveTheme = 'adaptive_theme';
  static const String _keyCustomColor = 'custom_color';
  static const String _keyLocale = 'locale';
  static const String _keyLastFmApiKey = 'lastfm_api_key';
  static const String _keyTheAudioDbApiKey = 'theaudiodb_api_key';
  static const String _keyEnableLocalPlayback = 'enable_local_playback';
  static const String _keyLocalPlayerName = 'local_player_name';
  static const String _keyOwnerName = 'owner_name';
  static const String _keyLastSelectedPlayerId = 'last_selected_player_id';
  static const String _keySmartSortPlayers = 'smart_sort_players';
  static const String _keyShowRecentAlbums = 'show_recent_albums';
  static const String _keyShowDiscoverArtists = 'show_discover_artists';
  static const String _keyShowDiscoverAlbums = 'show_discover_albums';
  static const String _keyShowExternalMixes = 'show_external_mixes';
  static const String _keyShowContinueListeningAudiobooks = 'show_continue_listening_audiobooks';
  static const String _keyShowDiscoverAudiobooks = 'show_discover_audiobooks';
  static const String _keyShowDiscoverSeries = 'show_discover_series';
  static const String _keyShowFavoriteAlbums = 'show_favorite_albums';
  static const String _keyShowFavoriteArtists = 'show_favorite_artists';
  static const String _keyShowFavoriteTracks = 'show_favorite_tracks';
  static const String _keyShowFavoritePlaylists = 'show_favorite_playlists';
  static const String _keyShowFavoriteRadioStations = 'show_favorite_radio_stations';
  static const String _keyShowFavoritePodcasts = 'show_favorite_podcasts';
  static const String _keyShowOnlyArtistsWithAlbums = 'show_only_artists_with_albums'; // Library artists filter
  static const String _keyHomeRowOrder = 'home_row_order'; // JSON list of row IDs

  // Default row order
  static const List<String> defaultHomeRowOrder = [
    'recent-albums',
    'discover-artists',
    'discover-albums',
    'external-mixes',
    'continue-listening',
    'discover-audiobooks',
    'discover-series',
    'favorite-albums',
    'favorite-artists',
    'favorite-tracks',
    'favorite-playlists',
    'favorite-radio-stations',
    'favorite-podcasts',
  ];

  // View Mode Settings
  static const String _keyArtistAlbumsSortOrder = 'artist_albums_sort_order'; // 'alpha' or 'year'
  static const String _keyArtistAlbumsViewMode = 'artist_albums_view_mode'; // 'grid2', 'grid3', 'list'
  static const String _keyLibraryArtistsViewMode = 'library_artists_view_mode'; // 'grid2', 'grid3', 'list'
  static const String _keyLibraryAlbumsViewMode = 'library_albums_view_mode'; // 'grid2', 'grid3', 'list'
  static const String _keyLibraryPlaylistsViewMode = 'library_playlists_view_mode'; // 'grid2', 'grid3', 'list'

  // Audiobook View Mode Settings
  static const String _keyAuthorAudiobooksSortOrder = 'author_audiobooks_sort_order'; // 'alpha' or 'year'
  static const String _keyAuthorAudiobooksViewMode = 'author_audiobooks_view_mode'; // 'grid2', 'grid3', 'list'
  static const String _keyLibraryAuthorsViewMode = 'library_authors_view_mode'; // 'grid2', 'grid3', 'list'
  static const String _keyLibraryAudiobooksViewMode = 'library_audiobooks_view_mode'; // 'grid2', 'grid3', 'list'
  static const String _keyLibraryAudiobooksSortOrder = 'library_audiobooks_sort_order'; // 'alpha' or 'year'
  static const String _keyLibrarySeriesViewMode = 'library_series_view_mode'; // 'grid2', 'grid3', 'list'
  static const String _keySeriesAudiobooksSortOrder = 'series_audiobooks_sort_order'; // 'alpha' or 'year'
  static const String _keySeriesAudiobooksViewMode = 'series_audiobooks_view_mode'; // 'grid2', 'grid3', 'list'
  static const String _keyLibraryRadioViewMode = 'library_radio_view_mode'; // 'grid2', 'grid3', 'list'
  static const String _keyLibraryPodcastsViewMode = 'library_podcasts_view_mode'; // 'grid2', 'grid3', 'list'

  // Library Sort Order Settings
  static const String _keyLibraryArtistsSortOrder = 'library_artists_sort_order'; // 'alpha', 'alpha_desc'
  static const String _keyLibraryAlbumsSortOrder = 'library_albums_sort_order'; // 'alpha', 'alpha_desc', 'year', 'year_desc', 'artist'
  static const String _keyLibraryTracksSortOrder = 'library_tracks_sort_order'; // 'alpha', 'artist', 'album', 'duration'
  static const String _keyLibraryPlaylistsSortOrder = 'library_playlists_sort_order'; // 'alpha', 'alpha_desc', 'tracks'
  static const String _keyLibraryAuthorsSortOrder = 'library_authors_sort_order'; // 'alpha', 'alpha_desc', 'books'
  static const String _keyLibrarySeriesSortOrder = 'library_series_sort_order'; // 'alpha', 'alpha_desc', 'books'
  static const String _keyLibraryRadioSortOrder = 'library_radio_sort_order'; // 'alpha', 'alpha_desc'
  static const String _keyLibraryPodcastsSortOrder = 'library_podcasts_sort_order'; // 'alpha', 'alpha_desc'
  static const String _keyPodcastEpisodesSortOrder = 'podcast_episodes_sort_order'; // 'newest', 'oldest', 'alpha', 'duration'

  // Audiobookshelf Direct Integration Settings
  static const String _keyAbsServerUrl = 'abs_server_url';
  static const String _keyAbsApiToken = 'abs_api_token';
  static const String _keyAbsEnabled = 'abs_enabled';

  // Audiobookshelf Library Settings (via MA browse)
  static const String _keyEnabledAbsLibraries = 'enabled_abs_libraries'; // JSON list of library paths
  static const String _keyDiscoveredAbsLibraries = 'discovered_abs_libraries'; // JSON list of {path, name}

  // Music Provider Filter Settings
  static const String _keyEnabledMusicProviders = 'enabled_music_providers'; // JSON list of provider instance IDs
  static const String _keyDiscoveredMusicProviders = 'discovered_music_providers'; // JSON list of {instanceId, domain, name}

  // Hint System Settings
  static const String _keyShowHints = 'show_hints'; // Master toggle for hints
  static const String _keyShowProviderIcons = 'show_provider_icons'; // Show provider icons on album art
  static const String _keyHasUsedPlayerReveal = 'has_used_player_reveal'; // Track if user has pulled to reveal players
  static const String _keyHasCompletedOnboarding = 'has_completed_onboarding'; // Track if user has seen welcome screen

  // Volume Precision Mode Settings
  static const String _keyVolumePrecisionMode = 'volume_precision_mode'; // Enable hold-to-precision volume control

  // Podcast Cover Cache (iTunes URLs for high-res artwork)
  static const String _keyPodcastCoverCache = 'podcast_cover_cache';

  static Future<String?> getServerUrl() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyServerUrl);
  }

  static Future<void> setServerUrl(String url) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyServerUrl, url);
  }

  static Future<void> clearServerUrl() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keyServerUrl);
  }

  // Get authentication server URL (returns null if not set, meaning use server URL)
  static Future<String?> getAuthServerUrl() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyAuthServerUrl);
  }

  // Set authentication server URL (null means use same as server URL)
  static Future<void> setAuthServerUrl(String? url) async {
    final prefs = await _getPrefs();
    if (url == null || url.isEmpty) {
      await prefs.remove(_keyAuthServerUrl);
    } else {
      await prefs.setString(_keyAuthServerUrl, url);
    }
  }

  // Get custom WebSocket port (null means use default logic)
  static Future<int?> getWebSocketPort() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_keyWebSocketPort);
  }

  // Set custom WebSocket port (null to use default logic)
  static Future<void> setWebSocketPort(int? port) async {
    final prefs = await _getPrefs();
    if (port == null) {
      await prefs.remove(_keyWebSocketPort);
    } else {
      await prefs.setInt(_keyWebSocketPort, port);
    }
  }

  // Get authentication token for stream requests (securely stored)
  static Future<String?> getAuthToken() async {
    return await SecureStorageService.getAuthToken();
  }

  // Set authentication token for stream requests (securely stored)
  static Future<void> setAuthToken(String? token) async {
    await SecureStorageService.setAuthToken(token);
  }

  // Get Music Assistant native auth token (long-lived token, securely stored)
  static Future<String?> getMaAuthToken() async {
    return await SecureStorageService.getMaAuthToken();
  }

  // Set Music Assistant native auth token (long-lived token, securely stored)
  static Future<void> setMaAuthToken(String? token) async {
    await SecureStorageService.setMaAuthToken(token);
  }

  // Clear Music Assistant native auth token
  static Future<void> clearMaAuthToken() async {
    await SecureStorageService.clearMaAuthToken();
  }

  // Get authentication credentials (serialized auth strategy credentials, securely stored)
  static Future<Map<String, dynamic>?> getAuthCredentials() async {
    return await SecureStorageService.getAuthCredentials();
  }

  // Set authentication credentials (serialized auth strategy credentials, securely stored)
  static Future<void> setAuthCredentials(Map<String, dynamic> credentials) async {
    await SecureStorageService.setAuthCredentials(credentials);
  }

  // Clear authentication credentials
  static Future<void> clearAuthCredentials() async {
    await SecureStorageService.clearAuthCredentials();
  }

  // Get username for authentication
  static Future<String?> getUsername() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyUsername);
  }

  // Set username for authentication
  static Future<void> setUsername(String? username) async {
    final prefs = await _getPrefs();
    if (username == null || username.isEmpty) {
      await prefs.remove(_keyUsername);
    } else {
      await prefs.setString(_keyUsername, username);
    }
  }

  // Get password for authentication (securely stored)
  static Future<String?> getPassword() async {
    return await SecureStorageService.getPassword();
  }

  // Set password for authentication (securely stored)
  static Future<void> setPassword(String? password) async {
    await SecureStorageService.setPassword(password);
  }

  // Get built-in player ID (persistent UUID for this device)
  static Future<String?> getBuiltinPlayerId() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyBuiltinPlayerId);
  }

  // Set built-in player ID
  static Future<void> setBuiltinPlayerId(String id) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyBuiltinPlayerId, id);
  }

  // Theme settings
  static Future<String?> getThemeMode() => _getString(_keyThemeMode, defaultValue: 'system');
  static Future<void> saveThemeMode(String mode) => _setString(_keyThemeMode, mode);

  static Future<bool> getUseMaterialTheme() => _getBool(_keyUseMaterialTheme, defaultValue: false);
  static Future<void> saveUseMaterialTheme(bool enabled) => _setBool(_keyUseMaterialTheme, enabled);

  static Future<bool> getAdaptiveTheme() => _getBool(_keyAdaptiveTheme, defaultValue: true);
  static Future<void> saveAdaptiveTheme(bool enabled) => _setBool(_keyAdaptiveTheme, enabled);

  static Future<String?> getCustomColor() => _getString(_keyCustomColor);
  static Future<void> saveCustomColor(String color) => _setString(_keyCustomColor, color);

  // Locale (null = system default)
  static Future<String?> getLocale() => _getString(_keyLocale);
  static Future<void> saveLocale(String? locale) => _setString(_keyLocale, locale, removeIfEmpty: true);

  // Metadata API Keys
  static Future<String?> getLastFmApiKey() => _getString(_keyLastFmApiKey);
  static Future<void> setLastFmApiKey(String? key) => _setString(_keyLastFmApiKey, key, removeIfEmpty: true);

  static Future<String?> getTheAudioDbApiKey() => _getString(_keyTheAudioDbApiKey);
  static Future<void> setTheAudioDbApiKey(String? key) => _setString(_keyTheAudioDbApiKey, key, removeIfEmpty: true);

  // Local Playback Settings
  static Future<bool> getEnableLocalPlayback() => _getBool(_keyEnableLocalPlayback, defaultValue: true);
  static Future<void> setEnableLocalPlayback(bool enabled) => _setBool(_keyEnableLocalPlayback, enabled);

  static Future<String> getLocalPlayerName() async {
    // Derive player name from owner name
    final ownerName = await getOwnerName();
    if (ownerName != null && ownerName.isNotEmpty) {
      return _makePlayerName(ownerName);
    }

    // Fallback to stored local player name or default
    final prefs = await _getPrefs();
    return prefs.getString(_keyLocalPlayerName) ?? 'Ensemble';
  }

  static Future<void> setLocalPlayerName(String name) => _setString(_keyLocalPlayerName, name);

  // Owner Name - used to derive player name
  static Future<String?> getOwnerName() => _getString(_keyOwnerName);
  static Future<void> setOwnerName(String name) => _setString(_keyOwnerName, name.trim());

  // Last selected player ID - persists user's player selection across sessions
  static Future<String?> getLastSelectedPlayerId() => _getString(_keyLastSelectedPlayerId);
  static Future<void> setLastSelectedPlayerId(String? playerId) =>
      _setString(_keyLastSelectedPlayerId, playerId, removeIfEmpty: true);

  // Smart Sort Players - sort by status (playing > on > off) instead of alphabetically
  static Future<bool> getSmartSortPlayers() => _getBool(_keySmartSortPlayers, defaultValue: false);
  static Future<void> setSmartSortPlayers(bool smartSort) => _setBool(_keySmartSortPlayers, smartSort);

  // Helper to create player name with possessive apostrophe
  // Automatically detects Phone vs Tablet based on screen size
  static String _makePlayerName(String ownerName) {
    final deviceType = DeviceIdService.isTablet ? 'Tablet' : 'Phone';
    // Handle possessive: "Chris" -> "Chris' Tablet", "Mom" -> "Mom's Phone"
    if (ownerName.toLowerCase().endsWith('s')) {
      return "$ownerName' $deviceType";
    } else {
      return "$ownerName's $deviceType";
    }
  }

  static Future<void> clearSettings() async {
    final prefs = await _getPrefs();
    await prefs.clear();
    await SecureStorageService.clearAll(); // Also clear secure storage
  }

  /// Migrate credentials from old SharedPreferences storage to secure storage.
  /// Should be called once during app startup for existing users.
  static Future<void> migrateToSecureStorage() async {
    await SecureStorageService.migrateFromSharedPreferences();
  }

  // Home Screen Row Settings (Main rows - default on)
  static Future<bool> getShowRecentAlbums() => _getBool(_keyShowRecentAlbums, defaultValue: true);
  static Future<void> setShowRecentAlbums(bool show) => _setBool(_keyShowRecentAlbums, show);

  static Future<bool> getShowDiscoverArtists() => _getBool(_keyShowDiscoverArtists, defaultValue: true);
  static Future<void> setShowDiscoverArtists(bool show) => _setBool(_keyShowDiscoverArtists, show);

  static Future<bool> getShowDiscoverAlbums() => _getBool(_keyShowDiscoverAlbums, defaultValue: true);
  static Future<void> setShowDiscoverAlbums(bool show) => _setBool(_keyShowDiscoverAlbums, show);

  static Future<bool> getShowExternalMixes() => _getBool(_keyShowExternalMixes, defaultValue: false);
  static Future<void> setShowExternalMixes(bool show) => _setBool(_keyShowExternalMixes, show);

  // Home Screen Audiobook Rows (default off - optional)
  static Future<bool> getShowContinueListeningAudiobooks() => _getBool(_keyShowContinueListeningAudiobooks, defaultValue: false);
  static Future<void> setShowContinueListeningAudiobooks(bool show) => _setBool(_keyShowContinueListeningAudiobooks, show);

  static Future<bool> getShowDiscoverAudiobooks() => _getBool(_keyShowDiscoverAudiobooks, defaultValue: false);
  static Future<void> setShowDiscoverAudiobooks(bool show) => _setBool(_keyShowDiscoverAudiobooks, show);

  static Future<bool> getShowDiscoverSeries() => _getBool(_keyShowDiscoverSeries, defaultValue: false);
  static Future<void> setShowDiscoverSeries(bool show) => _setBool(_keyShowDiscoverSeries, show);

  // Home Screen Favorites Settings (default off)
  static Future<bool> getShowFavoriteAlbums() => _getBool(_keyShowFavoriteAlbums, defaultValue: false);
  static Future<void> setShowFavoriteAlbums(bool show) => _setBool(_keyShowFavoriteAlbums, show);

  static Future<bool> getShowFavoriteArtists() => _getBool(_keyShowFavoriteArtists, defaultValue: false);
  static Future<void> setShowFavoriteArtists(bool show) => _setBool(_keyShowFavoriteArtists, show);

  static Future<bool> getShowFavoriteTracks() => _getBool(_keyShowFavoriteTracks, defaultValue: false);
  static Future<void> setShowFavoriteTracks(bool show) => _setBool(_keyShowFavoriteTracks, show);

  static Future<bool> getShowFavoritePlaylists() => _getBool(_keyShowFavoritePlaylists, defaultValue: false);
  static Future<void> setShowFavoritePlaylists(bool show) => _setBool(_keyShowFavoritePlaylists, show);

  static Future<bool> getShowFavoriteRadioStations() => _getBool(_keyShowFavoriteRadioStations, defaultValue: false);
  static Future<void> setShowFavoriteRadioStations(bool show) => _setBool(_keyShowFavoriteRadioStations, show);

  static Future<bool> getShowFavoritePodcasts() => _getBool(_keyShowFavoritePodcasts, defaultValue: false);
  static Future<void> setShowFavoritePodcasts(bool show) => _setBool(_keyShowFavoritePodcasts, show);

  // Library Artists Filter - show only artists that have albums in library
  static Future<bool> getShowOnlyArtistsWithAlbums() => _getBool(_keyShowOnlyArtistsWithAlbums, defaultValue: false);
  static Future<void> setShowOnlyArtistsWithAlbums(bool show) => _setBool(_keyShowOnlyArtistsWithAlbums, show);

  // Home Row Order
  static Future<List<String>> getHomeRowOrder() async {
    final prefs = await _getPrefs();
    final json = prefs.getString(_keyHomeRowOrder);
    if (json != null) {
      try {
        final List<dynamic> decoded = jsonDecode(json);
        final savedOrder = decoded.cast<String>();

        // Add any new rows from defaultHomeRowOrder that aren't in saved order
        // This ensures new row types appear for existing users
        final missingRows = defaultHomeRowOrder
            .where((row) => !savedOrder.contains(row))
            .toList();
        if (missingRows.isNotEmpty) {
          return [...savedOrder, ...missingRows];
        }
        return savedOrder;
      } catch (_) {
        return List.from(defaultHomeRowOrder);
      }
    }
    return List.from(defaultHomeRowOrder);
  }

  static Future<void> setHomeRowOrder(List<String> order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyHomeRowOrder, jsonEncode(order));
  }

  // View Mode Settings - Artist Albums
  static Future<String> getArtistAlbumsSortOrder() async => (await _getString(_keyArtistAlbumsSortOrder)) ?? 'alpha';
  static Future<void> setArtistAlbumsSortOrder(String order) => _setString(_keyArtistAlbumsSortOrder, order);

  static Future<String> getArtistAlbumsViewMode() async => (await _getString(_keyArtistAlbumsViewMode)) ?? 'grid2';
  static Future<void> setArtistAlbumsViewMode(String mode) => _setString(_keyArtistAlbumsViewMode, mode);

  // View Mode Settings - Library Artists
  static Future<String> getLibraryArtistsViewMode() async => (await _getString(_keyLibraryArtistsViewMode)) ?? 'list';

  static Future<void> setLibraryArtistsViewMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryArtistsViewMode, mode);
  }

  // View Mode Settings - Library Albums
  static Future<String> getLibraryAlbumsViewMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryAlbumsViewMode) ?? 'grid2';
  }

  static Future<void> setLibraryAlbumsViewMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryAlbumsViewMode, mode);
  }

  // View Mode Settings - Library Playlists
  static Future<String> getLibraryPlaylistsViewMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryPlaylistsViewMode) ?? 'list';
  }

  static Future<void> setLibraryPlaylistsViewMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryPlaylistsViewMode, mode);
  }

  // View Mode Settings - Author Audiobooks (author detail screen)
  static Future<String> getAuthorAudiobooksSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyAuthorAudiobooksSortOrder) ?? 'alpha';
  }

  static Future<void> setAuthorAudiobooksSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyAuthorAudiobooksSortOrder, order);
  }

  static Future<String> getAuthorAudiobooksViewMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyAuthorAudiobooksViewMode) ?? 'grid2';
  }

  static Future<void> setAuthorAudiobooksViewMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyAuthorAudiobooksViewMode, mode);
  }

  // View Mode Settings - Library Authors
  static Future<String> getLibraryAuthorsViewMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryAuthorsViewMode) ?? 'list';
  }

  static Future<void> setLibraryAuthorsViewMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryAuthorsViewMode, mode);
  }

  // View Mode Settings - Library Audiobooks
  static Future<String> getLibraryAudiobooksViewMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryAudiobooksViewMode) ?? 'grid2';
  }

  static Future<void> setLibraryAudiobooksViewMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryAudiobooksViewMode, mode);
  }

  static Future<String> getLibraryAudiobooksSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryAudiobooksSortOrder) ?? 'alpha';
  }

  static Future<void> setLibraryAudiobooksSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryAudiobooksSortOrder, order);
  }

  static Future<String> getLibrarySeriesViewMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibrarySeriesViewMode) ?? 'grid2';
  }

  static Future<void> setLibrarySeriesViewMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibrarySeriesViewMode, mode);
  }

  static Future<String> getLibraryRadioViewMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryRadioViewMode) ?? 'list';
  }

  static Future<void> setLibraryRadioViewMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryRadioViewMode, mode);
  }

  static Future<String> getLibraryPodcastsViewMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryPodcastsViewMode) ?? 'grid2';
  }

  static Future<void> setLibraryPodcastsViewMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryPodcastsViewMode, mode);
  }

  // View Mode Settings - Series Audiobooks (series detail screen)
  static Future<String> getSeriesAudiobooksSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keySeriesAudiobooksSortOrder) ?? 'series';
  }

  static Future<void> setSeriesAudiobooksSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keySeriesAudiobooksSortOrder, order);
  }

  static Future<String> getSeriesAudiobooksViewMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keySeriesAudiobooksViewMode) ?? 'grid2';
  }

  static Future<void> setSeriesAudiobooksViewMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keySeriesAudiobooksViewMode, mode);
  }

  // Library Sort Order Settings - Artists
  static Future<String> getLibraryArtistsSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryArtistsSortOrder) ?? 'alpha';
  }

  static Future<void> setLibraryArtistsSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryArtistsSortOrder, order);
  }

  // Library Sort Order Settings - Albums
  static Future<String> getLibraryAlbumsSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryAlbumsSortOrder) ?? 'alpha';
  }

  static Future<void> setLibraryAlbumsSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryAlbumsSortOrder, order);
  }

  // Library Sort Order Settings - Tracks
  static Future<String> getLibraryTracksSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryTracksSortOrder) ?? 'artist';
  }

  static Future<void> setLibraryTracksSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryTracksSortOrder, order);
  }

  // Library Sort Order Settings - Playlists
  static Future<String> getLibraryPlaylistsSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryPlaylistsSortOrder) ?? 'alpha';
  }

  static Future<void> setLibraryPlaylistsSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryPlaylistsSortOrder, order);
  }

  // Library Sort Order Settings - Authors
  static Future<String> getLibraryAuthorsSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryAuthorsSortOrder) ?? 'alpha';
  }

  static Future<void> setLibraryAuthorsSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryAuthorsSortOrder, order);
  }

  // Library Sort Order Settings - Series
  static Future<String> getLibrarySeriesSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibrarySeriesSortOrder) ?? 'alpha';
  }

  static Future<void> setLibrarySeriesSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibrarySeriesSortOrder, order);
  }

  // Library Sort Order Settings - Radio
  static Future<String> getLibraryRadioSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryRadioSortOrder) ?? 'alpha';
  }

  static Future<void> setLibraryRadioSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryRadioSortOrder, order);
  }

  // Library Sort Order Settings - Podcasts
  static Future<String> getLibraryPodcastsSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLibraryPodcastsSortOrder) ?? 'alpha';
  }

  static Future<void> setLibraryPodcastsSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLibraryPodcastsSortOrder, order);
  }

  // Podcast Episode Sort Order (within podcast detail screen)
  static Future<String> getPodcastEpisodesSortOrder() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyPodcastEpisodesSortOrder) ?? 'newest';
  }

  static Future<void> setPodcastEpisodesSortOrder(String order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyPodcastEpisodesSortOrder, order);
  }

  // Audiobookshelf Settings
  static Future<String?> getAbsServerUrl() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyAbsServerUrl);
  }

  static Future<void> setAbsServerUrl(String url) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyAbsServerUrl, url);
  }

  static Future<String?> getAbsApiToken() async {
    return await SecureStorageService.getAbsApiToken();
  }

  static Future<void> setAbsApiToken(String token) async {
    await SecureStorageService.setAbsApiToken(token);
  }

  static Future<bool> getAbsEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyAbsEnabled) ?? false;
  }

  static Future<void> setAbsEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyAbsEnabled, enabled);
  }

  static Future<void> clearAbsSettings() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keyAbsServerUrl);
    await prefs.remove(_keyAbsEnabled);
    await SecureStorageService.setAbsApiToken(null); // Clear from secure storage
  }

  // Audiobookshelf Library Settings (via MA browse API)

  /// Get list of enabled library paths (all enabled by default if not set)
  static Future<List<String>?> getEnabledAbsLibraries() async {
    final prefs = await _getPrefs();
    final json = prefs.getString(_keyEnabledAbsLibraries);
    if (json == null) return null; // null means all libraries are enabled
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>();
    } catch (e) {
      return null;
    }
  }

  /// Set list of enabled library paths
  static Future<void> setEnabledAbsLibraries(List<String> paths) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyEnabledAbsLibraries, jsonEncode(paths));
  }

  /// Clear enabled libraries (reverts to all enabled)
  static Future<void> clearEnabledAbsLibraries() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keyEnabledAbsLibraries);
  }

  /// Get discovered libraries [{path: String, name: String}]
  static Future<List<Map<String, String>>?> getDiscoveredAbsLibraries() async {
    final prefs = await _getPrefs();
    final json = prefs.getString(_keyDiscoveredAbsLibraries);
    if (json == null) return null;
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (e) {
      return null;
    }
  }

  /// Save discovered libraries
  static Future<void> setDiscoveredAbsLibraries(List<Map<String, String>> libraries) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyDiscoveredAbsLibraries, jsonEncode(libraries));
  }

  /// Check if a specific library is enabled
  static Future<bool> isAbsLibraryEnabled(String libraryPath) async {
    final enabled = await getEnabledAbsLibraries();
    if (enabled == null) return true; // All enabled by default
    return enabled.contains(libraryPath);
  }

  /// Toggle a specific library
  static Future<void> toggleAbsLibrary(String libraryPath, bool enable) async {
    final discovered = await getDiscoveredAbsLibraries();
    if (discovered == null) return;

    var enabled = await getEnabledAbsLibraries();
    // If null (all enabled), initialize with all library paths
    enabled ??= discovered.map((lib) => lib['path']!).toList();

    if (enable && !enabled.contains(libraryPath)) {
      enabled.add(libraryPath);
    } else if (!enable && enabled.contains(libraryPath)) {
      enabled.remove(libraryPath);
    }

    await setEnabledAbsLibraries(enabled);
  }

  // Music Provider Filter Settings

  /// Get list of enabled music provider instance IDs (null = all enabled)
  /// Returns null if no filter is set (all providers enabled by default)
  static Future<List<String>?> getEnabledMusicProviders() async {
    final prefs = await _getPrefs();
    final json = prefs.getString(_keyEnabledMusicProviders);
    if (json == null) return null; // null means all providers are enabled
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>();
    } catch (e) {
      return null;
    }
  }

  /// Set list of enabled music provider instance IDs
  /// Pass null or call clearEnabledMusicProviders() to enable all providers
  static Future<void> setEnabledMusicProviders(List<String> providerIds) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyEnabledMusicProviders, jsonEncode(providerIds));
  }

  /// Clear enabled providers (reverts to all enabled)
  static Future<void> clearEnabledMusicProviders() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keyEnabledMusicProviders);
  }

  /// Get discovered music providers [{instanceId, domain, name}]
  static Future<List<Map<String, String>>?> getDiscoveredMusicProviders() async {
    final prefs = await _getPrefs();
    final json = prefs.getString(_keyDiscoveredMusicProviders);
    if (json == null) return null;
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (e) {
      return null;
    }
  }

  /// Save discovered music providers
  static Future<void> setDiscoveredMusicProviders(List<Map<String, String>> providers) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyDiscoveredMusicProviders, jsonEncode(providers));
  }

  /// Check if a specific music provider is enabled
  static Future<bool> isMusicProviderEnabled(String instanceId) async {
    final enabled = await getEnabledMusicProviders();
    if (enabled == null) return true; // All enabled by default
    return enabled.contains(instanceId);
  }

  /// Toggle a specific music provider
  /// allProviderIds should contain all available provider instance IDs
  static Future<void> toggleMusicProvider(String instanceId, bool enable, List<String> allProviderIds) async {
    var enabled = await getEnabledMusicProviders();
    // If null (all enabled), initialize with all provider IDs
    enabled ??= List.from(allProviderIds);

    if (enable && !enabled.contains(instanceId)) {
      enabled.add(instanceId);
    } else if (!enable && enabled.contains(instanceId)) {
      // Prevent disabling the last provider
      if (enabled.length <= 1) {
        return; // Don't allow disabling the last provider
      }
      enabled.remove(instanceId);
    }

    await setEnabledMusicProviders(enabled);
  }

  // Hint System Settings

  /// Get whether hints are enabled (default: true)
  static Future<bool> getShowHints() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyShowHints) ?? true;
  }

  /// Set whether hints are enabled
  static Future<void> setShowHints(bool show) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyShowHints, show);
  }

  /// Get whether provider icons are shown on album art (default: true)
  static Future<bool> getShowProviderIcons() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyShowProviderIcons) ?? true;
  }

  /// Synchronous getter for provider icons setting (uses cached prefs)
  /// Returns true if prefs not yet initialized
  static bool getShowProviderIconsSync() {
    return _prefsCache?.getBool(_keyShowProviderIcons) ?? true;
  }

  /// Set whether provider icons are shown on album art
  static Future<void> setShowProviderIcons(bool show) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyShowProviderIcons, show);
  }

  /// Check if user has ever used the player reveal gesture
  static Future<bool> getHasUsedPlayerReveal() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyHasUsedPlayerReveal) ?? false;
  }

  /// Mark that user has used the player reveal gesture
  static Future<void> setHasUsedPlayerReveal(bool hasUsed) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyHasUsedPlayerReveal, hasUsed);
  }

  /// Check if user has completed onboarding (seen welcome screen)
  static Future<bool> getHasCompletedOnboarding() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyHasCompletedOnboarding) ?? false;
  }

  /// Mark that user has completed onboarding
  static Future<void> setHasCompletedOnboarding(bool completed) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyHasCompletedOnboarding, completed);
  }

  // Volume Precision Mode Settings

  /// Get whether volume precision mode is enabled (default: true)
  /// When enabled, holding still while adjusting volume enters precision mode
  /// for fine-grained control (10x more precise)
  static Future<bool> getVolumePrecisionMode() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyVolumePrecisionMode) ?? true;
  }

  /// Set whether volume precision mode is enabled
  static Future<void> setVolumePrecisionMode(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyVolumePrecisionMode, enabled);
  }

  // Podcast Cover Cache (iTunes URLs for high-res artwork)
  // Stored as JSON: {"podcastId": "itunesUrl", ...}

  /// Get cached podcast cover URLs (iTunes high-res)
  static Future<Map<String, String>> getPodcastCoverCache() async {
    final prefs = await _getPrefs();
    final json = prefs.getString(_keyPodcastCoverCache);
    if (json == null) return {};
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as String));
    } catch (_) {
      return {};
    }
  }

  /// Save podcast cover cache
  static Future<void> setPodcastCoverCache(Map<String, String> cache) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyPodcastCoverCache, jsonEncode(cache));
  }

  /// Add a single podcast cover to cache (for incremental updates)
  static Future<void> addPodcastCoverToCache(String podcastId, String url) async {
    final cache = await getPodcastCoverCache();
    cache[podcastId] = url;
    await setPodcastCoverCache(cache);
  }
}
