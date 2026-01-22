// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SEn extends S {
  SEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Ensemble';

  @override
  String get connecting => 'Connecting...';

  @override
  String get connected => 'Connected';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get serverAddress => 'Server Address';

  @override
  String get serverAddressHint => 'e.g., music.example.com or 192.168.1.100';

  @override
  String get yourName => 'Your Name';

  @override
  String get yourFirstName => 'Your first name';

  @override
  String get portOptional => 'Port (Optional)';

  @override
  String get portHint => 'e.g., 8095 or leave blank';

  @override
  String get portDescription =>
      'Leave blank for reverse proxy or standard ports. Enter 8095 for direct connection.';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get detectAndConnect => 'Detect & Connect';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get authServerUrlOptional => 'Auth Server URL (Optional)';

  @override
  String get authServerUrlHint =>
      'e.g., auth.example.com (if different from server)';

  @override
  String get authServerUrlDescription =>
      'Leave empty if authentication is on the same server';

  @override
  String detectedAuthType(String authType) {
    return 'Detected: $authType';
  }

  @override
  String get serverRequiresAuth => 'This server requires authentication';

  @override
  String get tailscaleVpnConnection => 'Tailscale VPN Connection';

  @override
  String get unencryptedConnection => 'Unencrypted Connection';

  @override
  String get usingHttpOverTailscale =>
      'Using HTTP over Tailscale (encrypted tunnel)';

  @override
  String get httpsFailedUsingHttp => 'HTTPS failed, using HTTP fallback';

  @override
  String get httpNotEncrypted => 'HTTP connection - data is not encrypted';

  @override
  String get pleaseEnterServerAddress =>
      'Please enter your Music Assistant server address';

  @override
  String get pleaseEnterName => 'Please enter your name';

  @override
  String get pleaseEnterValidPort =>
      'Please enter a valid port number (1-65535)';

  @override
  String get pleaseEnterCredentials => 'Please enter username and password';

  @override
  String get authFailed =>
      'Authentication failed. Please check your credentials.';

  @override
  String get maLoginFailed =>
      'Music Assistant login failed. Please check your credentials.';

  @override
  String get connectionFailed =>
      'Could not connect to server. Please check the address and try again.';

  @override
  String get detectingAuth => 'Detecting authentication...';

  @override
  String get cannotDetermineAuth =>
      'Cannot determine authentication requirements. Please check server URL.';

  @override
  String get noAuthentication => 'No Authentication';

  @override
  String get httpBasicAuth => 'HTTP Basic Auth';

  @override
  String get authelia => 'Authelia';

  @override
  String get musicAssistantLogin => 'Music Assistant Login';

  @override
  String get pressBackToMinimize => 'Press back again to minimize';

  @override
  String get recentlyPlayed => 'Recently Played';

  @override
  String get discoverArtists => 'Discover Artists';

  @override
  String get discoverAlbums => 'Discover Albums';

  @override
  String get continueListening => 'Continue Listening';

  @override
  String get discoverAudiobooks => 'Discover Audiobooks';

  @override
  String get discoverSeries => 'Discover Series';

  @override
  String get favoriteAlbums => 'Favorite Albums';

  @override
  String get favoriteArtists => 'Favorite Artists';

  @override
  String get favoriteTracks => 'Favorite Tracks';

  @override
  String get favoritePlaylists => 'Favorite Playlists';

  @override
  String get favoriteRadioStations => 'Favorite Radio Stations';

  @override
  String get favoritePodcasts => 'Favorite Podcasts';

  @override
  String get searchMusic => 'Search music...';

  @override
  String get searchForContent => 'Search for artists, albums, or tracks';

  @override
  String get recentSearches => 'Recent Searches';

  @override
  String get clearSearchHistory => 'Clear Search History';

  @override
  String get searchHistoryCleared => 'Search history cleared';

  @override
  String get libraryOnly => 'Library only';

  @override
  String get retry => 'Retry';

  @override
  String get all => 'All';

  @override
  String get artists => 'Artists';

  @override
  String get albums => 'Albums';

  @override
  String get tracks => 'Tracks';

  @override
  String get playlists => 'Playlists';

  @override
  String get audiobooks => 'Audiobooks';

  @override
  String get music => 'Music';

  @override
  String get radio => 'Radio';

  @override
  String get stations => 'Stations';

  @override
  String get selectLibrary => 'Select Library';

  @override
  String get noRadioStations => 'No radio stations';

  @override
  String get addRadioStationsHint => 'Add radio stations in Music Assistant';

  @override
  String get searchFailed => 'Search failed. Please check your connection.';

  @override
  String get queue => 'Queue';

  @override
  String playerQueue(String playerName) {
    return '$playerName Queue';
  }

  @override
  String get noPlayerSelected => 'No player selected';

  @override
  String get undo => 'Undo';

  @override
  String removedItem(String itemName) {
    return 'Removed $itemName';
  }

  @override
  String get settings => 'Settings';

  @override
  String get debugLogs => 'Debug Logs';

  @override
  String get themeMode => 'Theme Mode';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get system => 'System';

  @override
  String get pullToRefresh => 'Pull to refresh the library to apply changes';

  @override
  String get viewDebugLogs => 'View Debug Logs';

  @override
  String get viewAllPlayers => 'View All Players';

  @override
  String get copyLogs => 'Copy Logs';

  @override
  String get clearLogs => 'Clear Logs';

  @override
  String get copyList => 'Copy List';

  @override
  String get close => 'Close';

  @override
  String allPlayersCount(int count) {
    return 'All Players ($count)';
  }

  @override
  String errorLoadingPlayers(String error) {
    return 'Error loading players: $error';
  }

  @override
  String get logsCopied => 'Logs copied to clipboard';

  @override
  String get logsCleared => 'Logs cleared';

  @override
  String get playerListCopied => 'Player list copied to clipboard!';

  @override
  String get noLogsYet => 'No logs yet';

  @override
  String get infoPlus => 'Info+';

  @override
  String get warnings => 'Warnings';

  @override
  String get errors => 'Errors';

  @override
  String showingEntries(int filtered, int total) {
    return 'Showing $filtered of $total entries';
  }

  @override
  String get thisDevice => 'This device';

  @override
  String get ghostPlayer => 'Ghost player (duplicate)';

  @override
  String get unavailableCorrupt => 'Unavailable/Corrupt';

  @override
  String playerId(String id) {
    return 'ID: $id';
  }

  @override
  String playerInfo(String available, String provider) {
    return 'Available: $available | Provider: $provider';
  }

  @override
  String get shareBugReport => 'Share bug report';

  @override
  String get moreOptions => 'More options';

  @override
  String failedToUpdateFavorite(String error) {
    return 'Failed to update favorite: $error';
  }

  @override
  String get noPlayersAvailable => 'No players available';

  @override
  String get albumAddedToQueue => 'Album added to queue';

  @override
  String get tracksAddedToQueue => 'Tracks added to queue';

  @override
  String get play => 'Play';

  @override
  String get noPlayersFound => 'No players found';

  @override
  String startingRadio(String name) {
    return 'Starting $name radio';
  }

  @override
  String failedToStartRadio(String error) {
    return 'Failed to start radio: $error';
  }

  @override
  String startingRadioOnPlayer(String name, String playerName) {
    return 'Starting $name radio on $playerName';
  }

  @override
  String addedRadioToQueue(String name) {
    return 'Added $name radio to queue';
  }

  @override
  String failedToAddToQueue(String error) {
    return 'Failed to add to queue: $error';
  }

  @override
  String playingRadioStation(String name) {
    return 'Playing $name';
  }

  @override
  String get addedToQueue => 'Added to queue';

  @override
  String get inLibrary => 'In Library';

  @override
  String get noAlbumsFound => 'No albums found';

  @override
  String playing(String name) {
    return 'Playing $name';
  }

  @override
  String get playingTrack => 'Playing track';

  @override
  String get nowPlaying => 'Now playing';

  @override
  String markedAsFinished(String name) {
    return '$name marked as finished';
  }

  @override
  String failedToMarkFinished(String error) {
    return 'Failed to mark as finished: $error';
  }

  @override
  String markedAsUnplayed(String name) {
    return '$name marked as unplayed';
  }

  @override
  String failedToMarkUnplayed(String error) {
    return 'Failed to mark as unplayed: $error';
  }

  @override
  String failedToPlay(String error) {
    return 'Failed to play: $error';
  }

  @override
  String get markAsFinished => 'Mark as Finished';

  @override
  String get markAsUnplayed => 'Mark as Unplayed';

  @override
  String byAuthor(String author) {
    return 'By $author';
  }

  @override
  String audiobookCount(int count) {
    return '$count audiobook(s)';
  }

  @override
  String get loading => 'Loading...';

  @override
  String bookCount(int count) {
    return '$count book(s)';
  }

  @override
  String get books => 'Books';

  @override
  String get noFavoriteAudiobooks => 'No favorite audiobooks';

  @override
  String get tapHeartAudiobook =>
      'Tap the heart on an audiobook to add it to favorites';

  @override
  String get noAudiobooks => 'No audiobooks';

  @override
  String get addAudiobooksHint =>
      'Add audiobooks to your library to see them here';

  @override
  String get noFavoriteArtists => 'No favorite artists';

  @override
  String get tapHeartArtist =>
      'Tap the heart on an artist to add them to favorites';

  @override
  String get noFavoriteAlbums => 'No favorite albums';

  @override
  String get tapHeartAlbum =>
      'Tap the heart on an album to add it to favorites';

  @override
  String get noFavoritePlaylists => 'No favorite playlists';

  @override
  String get tapHeartPlaylist =>
      'Tap the heart on a playlist to add it to favorites';

  @override
  String get noFavoriteTracks => 'No favorite tracks';

  @override
  String get longPressTrackHint =>
      'Long-press a track and tap the heart to add it to favorites';

  @override
  String get loadSeries => 'Load Series';

  @override
  String get notConnected => 'Not connected to Music Assistant';

  @override
  String get notConnectedTitle => 'Not Connected';

  @override
  String get connectHint =>
      'Connect to your Music Assistant server to start listening';

  @override
  String get configureServer => 'Configure Server';

  @override
  String get noArtistsFound => 'No artists found';

  @override
  String get noTracksFound => 'No tracks found';

  @override
  String get noPlaylistsFound => 'No playlists found';

  @override
  String get queueIsEmpty => 'Queue is empty';

  @override
  String get noResultsFound => 'No results found';

  @override
  String get refresh => 'Refresh';

  @override
  String get debugConsole => 'Debug Console';

  @override
  String get copy => 'Copy';

  @override
  String get clear => 'Clear';

  @override
  String get noLogsToCopy => 'No logs to copy';

  @override
  String get noDebugLogsYet => 'No debug logs yet. Try detecting auth.';

  @override
  String get showDebug => 'Show Debug';

  @override
  String get hideDebug => 'Hide Debug';

  @override
  String get chapters => 'Chapters';

  @override
  String get noChapters => 'No chapters';

  @override
  String get noChapterInfo => 'This audiobook has no chapter information';

  @override
  String errorSeeking(String error) {
    return 'Error seeking: $error';
  }

  @override
  String error(String error) {
    return 'Error: $error';
  }

  @override
  String get home => 'Home';

  @override
  String get library => 'Library';

  @override
  String get homeScreen => 'Home Screen';

  @override
  String get metadataApis => 'Metadata APIs';

  @override
  String get theme => 'Theme';

  @override
  String get materialYou => 'Material You';

  @override
  String get adaptiveTheme => 'Adaptive Theme';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get german => 'German';

  @override
  String get spanish => 'Spanish';

  @override
  String get french => 'French';

  @override
  String get noTracksInPlaylist => 'No tracks in playlist';

  @override
  String get sortAlphabetically => 'Sort alphabetically';

  @override
  String get sortByYear => 'Sort by year';

  @override
  String get sortBySeriesOrder => 'Sort by series order';

  @override
  String get listView => 'List view';

  @override
  String get gridView => 'Grid view';

  @override
  String get noBooksInSeries => 'No books found in this series';

  @override
  String get artist => 'Artist';

  @override
  String get showRecentlyPlayedAlbums => 'Show recently played albums';

  @override
  String get showRandomArtists => 'Show random artists to discover';

  @override
  String get showRandomAlbums => 'Show random albums to discover';

  @override
  String get showAudiobooksInProgress => 'Show audiobooks in progress';

  @override
  String get showRandomAudiobooks => 'Show random audiobooks to discover';

  @override
  String get showRandomSeries => 'Show random audiobook series to discover';

  @override
  String get showFavoriteAlbums => 'Show a row of your favorite albums';

  @override
  String get showFavoriteArtists => 'Show a row of your favorite artists';

  @override
  String get showFavoriteTracks => 'Show a row of your favorite tracks';

  @override
  String get showFavoritePlaylists => 'Show a row of your favorite playlists';

  @override
  String get showFavoriteRadioStations =>
      'Show a row of your favorite radio stations';

  @override
  String get showFavoritePodcasts => 'Show a row of your favorite podcasts';

  @override
  String get extractColorsFromArtwork =>
      'Extract colors from album and artist artwork';

  @override
  String get chooseHomeScreenRows =>
      'Choose which rows to display on the home screen';

  @override
  String get addedToFavorites => 'Added to favorites';

  @override
  String get removedFromFavorites => 'Removed from favorites';

  @override
  String get addedToLibrary => 'Added to library';

  @override
  String get removedFromLibrary => 'Removed from library';

  @override
  String get addToLibrary => 'Add to library';

  @override
  String get unknown => 'Unknown';

  @override
  String get noUpcomingTracks => 'No upcoming tracks';

  @override
  String get showAll => 'Show all';

  @override
  String get showFavoritesOnly => 'Show favorites only';

  @override
  String get changeView => 'Change view';

  @override
  String get authors => 'Authors';

  @override
  String get series => 'Series';

  @override
  String get shows => 'Shows';

  @override
  String get podcasts => 'Podcasts';

  @override
  String get podcastSupportComingSoon => 'Podcast support coming soon';

  @override
  String get noPodcasts => 'No podcasts';

  @override
  String get addPodcastsHint => 'Subscribe to podcasts in Music Assistant';

  @override
  String get episodes => 'Episodes';

  @override
  String get episode => 'Episode';

  @override
  String get playlist => 'Playlist';

  @override
  String get connectionError => 'Connection Error';

  @override
  String get twoColumnGrid => '2-column grid';

  @override
  String get threeColumnGrid => '3-column grid';

  @override
  String get fromProviders => 'From Providers';

  @override
  String get resume => 'Resume';

  @override
  String get about => 'About';

  @override
  String get inProgress => 'In progress';

  @override
  String narratedBy(String narrators) {
    return 'Narrated by $narrators';
  }

  @override
  String get unknownNarrator => 'Unknown Narrator';

  @override
  String get unknownAuthor => 'Unknown Author';

  @override
  String get loadingChapters => 'Loading chapters...';

  @override
  String get noChapterInfoAvailable => 'No chapter information available';

  @override
  String percentComplete(int percent) {
    return '$percent% complete';
  }

  @override
  String get theAudioDbApiKey => 'TheAudioDB API Key';

  @override
  String get theAudioDbApiKeyHint => 'Use \"2\" for free tier or premium key';

  @override
  String get audiobookLibraries => 'Audiobook Libraries';

  @override
  String get chooseAudiobookLibraries =>
      'Choose which Audiobookshelf libraries to include';

  @override
  String get unknownLibrary => 'Unknown Library';

  @override
  String get musicProviders => 'Music Providers';

  @override
  String get musicProvidersDescription =>
      'Choose which accounts to show in your library';

  @override
  String get libraryRefreshing => 'Refreshing library...';

  @override
  String get cannotDisableLastProvider => 'Cannot disable the last provider';

  @override
  String get noSeriesFound => 'No Series Found';

  @override
  String get ensembleBugReport => 'Ensemble Bug Report';

  @override
  String byOwner(String owner) {
    return 'By $owner';
  }

  @override
  String get noSeriesAvailable =>
      'No series available from your audiobook library.\nPull to refresh.';

  @override
  String get pullToLoadSeries =>
      'Pull down to load series\nfrom Music Assistant';

  @override
  String get search => 'Search';

  @override
  String get metadataApisDescription =>
      'Artist images are automatically fetched from Deezer. Add API keys below for artist biographies and album descriptions.';

  @override
  String get lastFmApiKey => 'Last.fm API Key';

  @override
  String get lastFmApiKeyHint => 'Get free key at last.fm/api';

  @override
  String get swipeToSwitchDevice => 'Swipe to change player';

  @override
  String chapterNumber(int number) {
    return 'Chapter $number';
  }

  @override
  String get pcmAudio => 'PCM Audio';

  @override
  String get playOn => 'Play on...';

  @override
  String get addAlbumToQueueOn => 'Add album to queue on...';

  @override
  String get addToQueueOn => 'Add to queue on...';

  @override
  String startRadioOn(String name) {
    return 'Start $name radio on...';
  }

  @override
  String get book => 'book';

  @override
  String get audiobookSingular => 'audiobook';

  @override
  String get albumSingular => 'Album';

  @override
  String get trackSingular => 'Track';

  @override
  String get podcastSingular => 'Podcast';

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return '$count $_temp0';
  }

  @override
  String get materialYouDescription => 'Use system colors (Android 12+)';

  @override
  String get accentColor => 'Accent Color';

  @override
  String get players => 'Players';

  @override
  String get preferLocalPlayer => 'Prefer Local Player';

  @override
  String get preferLocalPlayerDescription =>
      'Always select this device first when available';

  @override
  String get smartSortPlayers => 'Smart Sort';

  @override
  String get smartSortPlayersDescription =>
      'Sort by status (playing, on, off) instead of alphabetically';

  @override
  String get disableAutoSwitch => 'Disable Auto-Switch';

  @override
  String get disableAutoSwitchDescription =>
      'Never automatically switch to a different player';

  @override
  String get playerStateUnavailable => 'Unavailable';

  @override
  String get playerStateOff => 'Off';

  @override
  String get playerStateIdle => 'Idle';

  @override
  String get playerStateExternalSource => 'External Source';

  @override
  String get playerSelected => 'Selected';

  @override
  String get actionQueuedForSync => 'Will sync when online';

  @override
  String pendingOfflineActions(int count) {
    return '$count pending sync';
  }

  @override
  String get hintsAndTips => 'Hints & Tips';

  @override
  String get showHints => 'Show Hints';

  @override
  String get showHintsDescription =>
      'Display helpful tips for discovering features';

  @override
  String get display => 'Display';

  @override
  String get showProviderIcons => 'Show Provider Icons';

  @override
  String get showProviderIconsDescription =>
      'Display provider logos on album art';

  @override
  String get pullToSelectPlayers => 'Pull to select players';

  @override
  String get holdToSync => 'Long-press to sync';

  @override
  String get swipeToAdjustVolume => 'Swipe to adjust volume';

  @override
  String get selectPlayerHint => 'Choose a player, or dismiss by swiping down';

  @override
  String get welcomeToEnsemble => 'Welcome to Ensemble';

  @override
  String get welcomeMessage =>
      'By default your phone is the selected player.\nPull the mini player down to select another player.';

  @override
  String get skip => 'Skip';

  @override
  String get dismissPlayerHint =>
      'Swipe down, tap outside, or press back to return';

  @override
  String playingAlbum(String albumName) {
    return 'Playing $albumName';
  }

  @override
  String playingPlaylist(String playlistName) {
    return 'Playing $playlistName';
  }

  @override
  String get noTracks => 'No tracks';

  @override
  String get addTracksHint =>
      'Add some music to your library to see tracks here';

  @override
  String get noFavoriteRadioStations => 'No favorite radio stations';

  @override
  String get longPressRadioHint =>
      'Long-press a station and tap the heart to add it to favorites';

  @override
  String get noFavoritePodcasts => 'No favorite podcasts';

  @override
  String get longPressPodcastHint =>
      'Long-press a podcast and tap the heart to add it to favorites';

  @override
  String failedToPlayRadioStation(String error) {
    return 'Failed to play radio station: $error';
  }

  @override
  String get itemAlreadyInLibrary => 'Item is already in library';

  @override
  String get failedToAddToLibrary => 'Failed to add to library';

  @override
  String get cannotFindLibraryId => 'Cannot find library ID for removal';

  @override
  String get failedToRemoveFromLibrary => 'Failed to remove from library';

  @override
  String failedToPlayAlbum(String error) {
    return 'Failed to play album: $error';
  }

  @override
  String playingOnPlayer(String name, String playerName) {
    return 'Playing $name on $playerName';
  }

  @override
  String failedToPlayPlaylist(String error) {
    return 'Failed to play playlist: $error';
  }

  @override
  String failedToPlayAudiobook(String error) {
    return 'Failed to play audiobook: $error';
  }

  @override
  String get noOtherPlayersAvailable => 'No other players available';

  @override
  String get transferQueue => 'Transfer queue';

  @override
  String get clearQueue => 'Clear queue';

  @override
  String syncingPlayer(String playerName) {
    return 'Syncing $playerName...';
  }

  @override
  String get switchPlayer => 'Switch Player';

  @override
  String get logsCopiedToClipboard => 'Logs copied to clipboard';

  @override
  String get auto => 'Auto';

  @override
  String get transferQueueTo => 'Transfer Queue To';

  @override
  String queueTransferredTo(String playerName) {
    return 'Queue transferred to $playerName';
  }

  @override
  String failedToTransferQueue(String error) {
    return 'Failed to transfer queue: $error';
  }

  @override
  String failedToLoadQueue(String error) {
    return 'Failed to load queue: $error';
  }

  @override
  String get transferTo => 'Transfer to...';

  @override
  String get transferQueueToPlayer => 'Transfer queue to another player';

  @override
  String get selectPlayerToPlay => 'Select a player';

  @override
  String get selectPlayerToPlayAlbum => 'Select player to play album';

  @override
  String get selectPlayerToPlayPlaylist => 'Select player to play playlist';

  @override
  String get selectPlayerForRadio => 'Select player for radio';

  @override
  String get selectPlayerForEpisode => 'Select player for episode';

  @override
  String get selectPlayerForAudiobook => 'Select player for audiobook';

  @override
  String get selectPlayerToAddToQueue => 'Select player to add to queue';
}
