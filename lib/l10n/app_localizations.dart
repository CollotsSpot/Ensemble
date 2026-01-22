import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S? of(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr')
  ];

  /// The application title
  ///
  /// In en, this message translates to:
  /// **'Ensemble'**
  String get appTitle;

  /// Connection status when connecting
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// Connection status when connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// Connection status when disconnected
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// Login screen server address field label
  ///
  /// In en, this message translates to:
  /// **'Server Address'**
  String get serverAddress;

  /// Hint text for server address field
  ///
  /// In en, this message translates to:
  /// **'e.g., music.example.com or 192.168.1.100'**
  String get serverAddressHint;

  /// Login screen name field label
  ///
  /// In en, this message translates to:
  /// **'Your Name'**
  String get yourName;

  /// Hint for name field
  ///
  /// In en, this message translates to:
  /// **'Your first name'**
  String get yourFirstName;

  /// Port field label
  ///
  /// In en, this message translates to:
  /// **'Port (Optional)'**
  String get portOptional;

  /// Hint for port field
  ///
  /// In en, this message translates to:
  /// **'e.g., 8095 or leave blank'**
  String get portHint;

  /// Description for port field
  ///
  /// In en, this message translates to:
  /// **'Leave blank for reverse proxy or standard ports. Enter 8095 for direct connection.'**
  String get portDescription;

  /// Username field label
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// Password field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Button to detect auth and connect
  ///
  /// In en, this message translates to:
  /// **'Detect & Connect'**
  String get detectAndConnect;

  /// Connect button label
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// Disconnect button label
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// Auth server URL field label
  ///
  /// In en, this message translates to:
  /// **'Auth Server URL (Optional)'**
  String get authServerUrlOptional;

  /// Hint for auth server URL
  ///
  /// In en, this message translates to:
  /// **'e.g., auth.example.com (if different from server)'**
  String get authServerUrlHint;

  /// Description for auth server URL field
  ///
  /// In en, this message translates to:
  /// **'Leave empty if authentication is on the same server'**
  String get authServerUrlDescription;

  /// Shows detected authentication type
  ///
  /// In en, this message translates to:
  /// **'Detected: {authType}'**
  String detectedAuthType(String authType);

  /// Message when server requires auth
  ///
  /// In en, this message translates to:
  /// **'This server requires authentication'**
  String get serverRequiresAuth;

  /// Tailscale connection type
  ///
  /// In en, this message translates to:
  /// **'Tailscale VPN Connection'**
  String get tailscaleVpnConnection;

  /// Unencrypted connection warning
  ///
  /// In en, this message translates to:
  /// **'Unencrypted Connection'**
  String get unencryptedConnection;

  /// HTTP over Tailscale description
  ///
  /// In en, this message translates to:
  /// **'Using HTTP over Tailscale (encrypted tunnel)'**
  String get usingHttpOverTailscale;

  /// HTTP fallback message
  ///
  /// In en, this message translates to:
  /// **'HTTPS failed, using HTTP fallback'**
  String get httpsFailedUsingHttp;

  /// HTTP not encrypted warning
  ///
  /// In en, this message translates to:
  /// **'HTTP connection - data is not encrypted'**
  String get httpNotEncrypted;

  /// Validation message for server address
  ///
  /// In en, this message translates to:
  /// **'Please enter your Music Assistant server address'**
  String get pleaseEnterServerAddress;

  /// Validation message for name
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get pleaseEnterName;

  /// Validation message for port
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid port number (1-65535)'**
  String get pleaseEnterValidPort;

  /// Validation message for credentials
  ///
  /// In en, this message translates to:
  /// **'Please enter username and password'**
  String get pleaseEnterCredentials;

  /// Authentication failed error
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Please check your credentials.'**
  String get authFailed;

  /// MA login failed error
  ///
  /// In en, this message translates to:
  /// **'Music Assistant login failed. Please check your credentials.'**
  String get maLoginFailed;

  /// Connection failed error
  ///
  /// In en, this message translates to:
  /// **'Could not connect to server. Please check the address and try again.'**
  String get connectionFailed;

  /// Status when detecting auth
  ///
  /// In en, this message translates to:
  /// **'Detecting authentication...'**
  String get detectingAuth;

  /// Error when auth detection fails
  ///
  /// In en, this message translates to:
  /// **'Cannot determine authentication requirements. Please check server URL.'**
  String get cannotDetermineAuth;

  /// Auth type: none
  ///
  /// In en, this message translates to:
  /// **'No Authentication'**
  String get noAuthentication;

  /// Auth type: HTTP Basic
  ///
  /// In en, this message translates to:
  /// **'HTTP Basic Auth'**
  String get httpBasicAuth;

  /// Auth type: Authelia
  ///
  /// In en, this message translates to:
  /// **'Authelia'**
  String get authelia;

  /// Auth type: MA Login
  ///
  /// In en, this message translates to:
  /// **'Music Assistant Login'**
  String get musicAssistantLogin;

  /// Back button toast message
  ///
  /// In en, this message translates to:
  /// **'Press back again to minimize'**
  String get pressBackToMinimize;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Recently Played'**
  String get recentlyPlayed;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Discover Artists'**
  String get discoverArtists;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Discover Albums'**
  String get discoverAlbums;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Continue Listening'**
  String get continueListening;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Discover Audiobooks'**
  String get discoverAudiobooks;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Discover Series'**
  String get discoverSeries;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Favorite Albums'**
  String get favoriteAlbums;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Favorite Artists'**
  String get favoriteArtists;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Favorite Tracks'**
  String get favoriteTracks;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Favorite Playlists'**
  String get favoritePlaylists;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Favorite Radio Stations'**
  String get favoriteRadioStations;

  /// Home screen section title
  ///
  /// In en, this message translates to:
  /// **'Favorite Podcasts'**
  String get favoritePodcasts;

  /// Search placeholder text
  ///
  /// In en, this message translates to:
  /// **'Search music...'**
  String get searchMusic;

  /// Search hint text
  ///
  /// In en, this message translates to:
  /// **'Search for artists, albums, or tracks'**
  String get searchForContent;

  /// Label for recent search history section
  ///
  /// In en, this message translates to:
  /// **'Recent Searches'**
  String get recentSearches;

  /// Button to clear search history
  ///
  /// In en, this message translates to:
  /// **'Clear Search History'**
  String get clearSearchHistory;

  /// Confirmation message after clearing search history
  ///
  /// In en, this message translates to:
  /// **'Search history cleared'**
  String get searchHistoryCleared;

  /// Toggle to search only in library
  ///
  /// In en, this message translates to:
  /// **'Library only'**
  String get libraryOnly;

  /// Retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Filter option: All
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// Artists category
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get artists;

  /// Albums category
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albums;

  /// Tracks category
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get tracks;

  /// Playlists category
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// Audiobooks category
  ///
  /// In en, this message translates to:
  /// **'Audiobooks'**
  String get audiobooks;

  /// Music category
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get music;

  /// Radio button label
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get radio;

  /// Radio stations subcategory
  ///
  /// In en, this message translates to:
  /// **'Stations'**
  String get stations;

  /// Title for library type selection bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Select Library'**
  String get selectLibrary;

  /// Empty state when no radio stations are available
  ///
  /// In en, this message translates to:
  /// **'No radio stations'**
  String get noRadioStations;

  /// Hint for adding radio stations
  ///
  /// In en, this message translates to:
  /// **'Add radio stations in Music Assistant'**
  String get addRadioStationsHint;

  /// Search error message
  ///
  /// In en, this message translates to:
  /// **'Search failed. Please check your connection.'**
  String get searchFailed;

  /// Queue screen title
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// Queue title with player name
  ///
  /// In en, this message translates to:
  /// **'{playerName} Queue'**
  String playerQueue(String playerName);

  /// Message when no player is selected
  ///
  /// In en, this message translates to:
  /// **'No player selected'**
  String get noPlayerSelected;

  /// Undo action
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Snackbar message when item removed
  ///
  /// In en, this message translates to:
  /// **'Removed {itemName}'**
  String removedItem(String itemName);

  /// Settings screen title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Debug logs section
  ///
  /// In en, this message translates to:
  /// **'Debug Logs'**
  String get debugLogs;

  /// Theme mode setting
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeMode;

  /// Light theme
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// Dark theme
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// System theme
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// Refresh hint message
  ///
  /// In en, this message translates to:
  /// **'Pull to refresh the library to apply changes'**
  String get pullToRefresh;

  /// Button to view debug logs
  ///
  /// In en, this message translates to:
  /// **'View Debug Logs'**
  String get viewDebugLogs;

  /// Button to view all players
  ///
  /// In en, this message translates to:
  /// **'View All Players'**
  String get viewAllPlayers;

  /// Button to copy logs
  ///
  /// In en, this message translates to:
  /// **'Copy Logs'**
  String get copyLogs;

  /// Button to clear logs
  ///
  /// In en, this message translates to:
  /// **'Clear Logs'**
  String get clearLogs;

  /// Button to copy list
  ///
  /// In en, this message translates to:
  /// **'Copy List'**
  String get copyList;

  /// Close button
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Dialog title with player count
  ///
  /// In en, this message translates to:
  /// **'All Players ({count})'**
  String allPlayersCount(int count);

  /// Error loading players
  ///
  /// In en, this message translates to:
  /// **'Error loading players: {error}'**
  String errorLoadingPlayers(String error);

  /// Confirmation when logs copied
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard'**
  String get logsCopied;

  /// Confirmation when logs cleared
  ///
  /// In en, this message translates to:
  /// **'Logs cleared'**
  String get logsCleared;

  /// Confirmation when player list copied
  ///
  /// In en, this message translates to:
  /// **'Player list copied to clipboard!'**
  String get playerListCopied;

  /// Empty logs message
  ///
  /// In en, this message translates to:
  /// **'No logs yet'**
  String get noLogsYet;

  /// Log filter: Info+
  ///
  /// In en, this message translates to:
  /// **'Info+'**
  String get infoPlus;

  /// Log filter: Warnings
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get warnings;

  /// Log filter: Errors
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get errors;

  /// Entries count display
  ///
  /// In en, this message translates to:
  /// **'Showing {filtered} of {total} entries'**
  String showingEntries(int filtered, int total);

  /// Label for current device
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get thisDevice;

  /// Warning for ghost player
  ///
  /// In en, this message translates to:
  /// **'Ghost player (duplicate)'**
  String get ghostPlayer;

  /// Warning for corrupt player
  ///
  /// In en, this message translates to:
  /// **'Unavailable/Corrupt'**
  String get unavailableCorrupt;

  /// Player ID display
  ///
  /// In en, this message translates to:
  /// **'ID: {id}'**
  String playerId(String id);

  /// Player info display
  ///
  /// In en, this message translates to:
  /// **'Available: {available} | Provider: {provider}'**
  String playerInfo(String available, String provider);

  /// Share bug report option
  ///
  /// In en, this message translates to:
  /// **'Share bug report'**
  String get shareBugReport;

  /// More options menu
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// Error updating favorite
  ///
  /// In en, this message translates to:
  /// **'Failed to update favorite: {error}'**
  String failedToUpdateFavorite(String error);

  /// Message when no players available
  ///
  /// In en, this message translates to:
  /// **'No players available'**
  String get noPlayersAvailable;

  /// Confirmation when album added
  ///
  /// In en, this message translates to:
  /// **'Album added to queue'**
  String get albumAddedToQueue;

  /// Confirmation when tracks added
  ///
  /// In en, this message translates to:
  /// **'Tracks added to queue'**
  String get tracksAddedToQueue;

  /// Play button label
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// Message when no players found
  ///
  /// In en, this message translates to:
  /// **'No players found'**
  String get noPlayersFound;

  /// Status when starting radio
  ///
  /// In en, this message translates to:
  /// **'Starting {name} radio'**
  String startingRadio(String name);

  /// Error starting radio
  ///
  /// In en, this message translates to:
  /// **'Failed to start radio: {error}'**
  String failedToStartRadio(String error);

  /// Status when starting radio on player
  ///
  /// In en, this message translates to:
  /// **'Starting {name} radio on {playerName}'**
  String startingRadioOnPlayer(String name, String playerName);

  /// Confirmation when radio added to queue
  ///
  /// In en, this message translates to:
  /// **'Added {name} radio to queue'**
  String addedRadioToQueue(String name);

  /// Error adding to queue
  ///
  /// In en, this message translates to:
  /// **'Failed to add to queue: {error}'**
  String failedToAddToQueue(String error);

  /// Status when playing radio station
  ///
  /// In en, this message translates to:
  /// **'Playing {name}'**
  String playingRadioStation(String name);

  /// Confirmation when item added to queue
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get addedToQueue;

  /// In library section title
  ///
  /// In en, this message translates to:
  /// **'In Library'**
  String get inLibrary;

  /// Empty albums message
  ///
  /// In en, this message translates to:
  /// **'No albums found'**
  String get noAlbumsFound;

  /// Status when playing
  ///
  /// In en, this message translates to:
  /// **'Playing {name}'**
  String playing(String name);

  /// Status when playing track
  ///
  /// In en, this message translates to:
  /// **'Playing track'**
  String get playingTrack;

  /// Label shown when device selector is open to indicate current player
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get nowPlaying;

  /// Audiobook marked finished
  ///
  /// In en, this message translates to:
  /// **'{name} marked as finished'**
  String markedAsFinished(String name);

  /// Error marking finished
  ///
  /// In en, this message translates to:
  /// **'Failed to mark as finished: {error}'**
  String failedToMarkFinished(String error);

  /// Audiobook marked unplayed
  ///
  /// In en, this message translates to:
  /// **'{name} marked as unplayed'**
  String markedAsUnplayed(String name);

  /// Error marking unplayed
  ///
  /// In en, this message translates to:
  /// **'Failed to mark as unplayed: {error}'**
  String failedToMarkUnplayed(String error);

  /// Error playing
  ///
  /// In en, this message translates to:
  /// **'Failed to play: {error}'**
  String failedToPlay(String error);

  /// Button to mark as finished
  ///
  /// In en, this message translates to:
  /// **'Mark as Finished'**
  String get markAsFinished;

  /// Button to mark as unplayed
  ///
  /// In en, this message translates to:
  /// **'Mark as Unplayed'**
  String get markAsUnplayed;

  /// Author attribution
  ///
  /// In en, this message translates to:
  /// **'By {author}'**
  String byAuthor(String author);

  /// Audiobook count
  ///
  /// In en, this message translates to:
  /// **'{count} audiobook(s)'**
  String audiobookCount(int count);

  /// Loading state
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Book count
  ///
  /// In en, this message translates to:
  /// **'{count} book(s)'**
  String bookCount(int count);

  /// Books section title
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get books;

  /// Empty favorite audiobooks
  ///
  /// In en, this message translates to:
  /// **'No favorite audiobooks'**
  String get noFavoriteAudiobooks;

  /// Hint to add audiobook favorite
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on an audiobook to add it to favorites'**
  String get tapHeartAudiobook;

  /// Empty audiobooks
  ///
  /// In en, this message translates to:
  /// **'No audiobooks'**
  String get noAudiobooks;

  /// Hint to add audiobooks
  ///
  /// In en, this message translates to:
  /// **'Add audiobooks to your library to see them here'**
  String get addAudiobooksHint;

  /// Empty favorite artists
  ///
  /// In en, this message translates to:
  /// **'No favorite artists'**
  String get noFavoriteArtists;

  /// Hint to add artist favorite
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on an artist to add them to favorites'**
  String get tapHeartArtist;

  /// Empty favorite albums
  ///
  /// In en, this message translates to:
  /// **'No favorite albums'**
  String get noFavoriteAlbums;

  /// Hint to add album favorite
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on an album to add it to favorites'**
  String get tapHeartAlbum;

  /// Empty favorite playlists
  ///
  /// In en, this message translates to:
  /// **'No favorite playlists'**
  String get noFavoritePlaylists;

  /// Hint to add playlist favorite
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on a playlist to add it to favorites'**
  String get tapHeartPlaylist;

  /// Empty favorite tracks
  ///
  /// In en, this message translates to:
  /// **'No favorite tracks'**
  String get noFavoriteTracks;

  /// Hint to add track favorite
  ///
  /// In en, this message translates to:
  /// **'Long-press a track and tap the heart to add it to favorites'**
  String get longPressTrackHint;

  /// Button to load series
  ///
  /// In en, this message translates to:
  /// **'Load Series'**
  String get loadSeries;

  /// Disconnected state title
  ///
  /// In en, this message translates to:
  /// **'Not connected to Music Assistant'**
  String get notConnected;

  /// Disconnected state short title
  ///
  /// In en, this message translates to:
  /// **'Not Connected'**
  String get notConnectedTitle;

  /// Hint to connect
  ///
  /// In en, this message translates to:
  /// **'Connect to your Music Assistant server to start listening'**
  String get connectHint;

  /// Button to configure server
  ///
  /// In en, this message translates to:
  /// **'Configure Server'**
  String get configureServer;

  /// Empty artists
  ///
  /// In en, this message translates to:
  /// **'No artists found'**
  String get noArtistsFound;

  /// Empty tracks
  ///
  /// In en, this message translates to:
  /// **'No tracks found'**
  String get noTracksFound;

  /// Empty playlists
  ///
  /// In en, this message translates to:
  /// **'No playlists found'**
  String get noPlaylistsFound;

  /// Empty queue
  ///
  /// In en, this message translates to:
  /// **'Queue is empty'**
  String get queueIsEmpty;

  /// Empty search results
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// Refresh button
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Debug console title
  ///
  /// In en, this message translates to:
  /// **'Debug Console'**
  String get debugConsole;

  /// Copy button
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Clear button
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Message when no logs to copy
  ///
  /// In en, this message translates to:
  /// **'No logs to copy'**
  String get noLogsToCopy;

  /// Empty debug logs hint
  ///
  /// In en, this message translates to:
  /// **'No debug logs yet. Try detecting auth.'**
  String get noDebugLogsYet;

  /// Button to show debug
  ///
  /// In en, this message translates to:
  /// **'Show Debug'**
  String get showDebug;

  /// Button to hide debug
  ///
  /// In en, this message translates to:
  /// **'Hide Debug'**
  String get hideDebug;

  /// Chapters panel title
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get chapters;

  /// Empty chapters title
  ///
  /// In en, this message translates to:
  /// **'No chapters'**
  String get noChapters;

  /// Empty chapters message
  ///
  /// In en, this message translates to:
  /// **'This audiobook has no chapter information'**
  String get noChapterInfo;

  /// Error when seeking
  ///
  /// In en, this message translates to:
  /// **'Error seeking: {error}'**
  String errorSeeking(String error);

  /// Generic error message
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String error(String error);

  /// Home navigation label
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// Library navigation label
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// Home screen settings section
  ///
  /// In en, this message translates to:
  /// **'Home Screen'**
  String get homeScreen;

  /// Metadata APIs settings section
  ///
  /// In en, this message translates to:
  /// **'Metadata APIs'**
  String get metadataApis;

  /// Theme settings section
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// Material You theme option
  ///
  /// In en, this message translates to:
  /// **'Material You'**
  String get materialYou;

  /// Adaptive theme option
  ///
  /// In en, this message translates to:
  /// **'Adaptive Theme'**
  String get adaptiveTheme;

  /// Language setting
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// English language
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// German language
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get german;

  /// Spanish language
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get spanish;

  /// French language
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get french;

  /// No description provided for @noTracksInPlaylist.
  ///
  /// In en, this message translates to:
  /// **'No tracks in playlist'**
  String get noTracksInPlaylist;

  /// No description provided for @sortAlphabetically.
  ///
  /// In en, this message translates to:
  /// **'Sort alphabetically'**
  String get sortAlphabetically;

  /// No description provided for @sortByYear.
  ///
  /// In en, this message translates to:
  /// **'Sort by year'**
  String get sortByYear;

  /// No description provided for @sortBySeriesOrder.
  ///
  /// In en, this message translates to:
  /// **'Sort by series order'**
  String get sortBySeriesOrder;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get listView;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gridView;

  /// No description provided for @noBooksInSeries.
  ///
  /// In en, this message translates to:
  /// **'No books found in this series'**
  String get noBooksInSeries;

  /// No description provided for @artist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get artist;

  /// No description provided for @showRecentlyPlayedAlbums.
  ///
  /// In en, this message translates to:
  /// **'Show recently played albums'**
  String get showRecentlyPlayedAlbums;

  /// No description provided for @showRandomArtists.
  ///
  /// In en, this message translates to:
  /// **'Show random artists to discover'**
  String get showRandomArtists;

  /// No description provided for @showRandomAlbums.
  ///
  /// In en, this message translates to:
  /// **'Show random albums to discover'**
  String get showRandomAlbums;

  /// No description provided for @showAudiobooksInProgress.
  ///
  /// In en, this message translates to:
  /// **'Show audiobooks in progress'**
  String get showAudiobooksInProgress;

  /// No description provided for @showRandomAudiobooks.
  ///
  /// In en, this message translates to:
  /// **'Show random audiobooks to discover'**
  String get showRandomAudiobooks;

  /// No description provided for @showRandomSeries.
  ///
  /// In en, this message translates to:
  /// **'Show random audiobook series to discover'**
  String get showRandomSeries;

  /// No description provided for @showFavoriteAlbums.
  ///
  /// In en, this message translates to:
  /// **'Show a row of your favorite albums'**
  String get showFavoriteAlbums;

  /// No description provided for @showFavoriteArtists.
  ///
  /// In en, this message translates to:
  /// **'Show a row of your favorite artists'**
  String get showFavoriteArtists;

  /// No description provided for @showFavoriteTracks.
  ///
  /// In en, this message translates to:
  /// **'Show a row of your favorite tracks'**
  String get showFavoriteTracks;

  /// No description provided for @showFavoritePlaylists.
  ///
  /// In en, this message translates to:
  /// **'Show a row of your favorite playlists'**
  String get showFavoritePlaylists;

  /// No description provided for @showFavoriteRadioStations.
  ///
  /// In en, this message translates to:
  /// **'Show a row of your favorite radio stations'**
  String get showFavoriteRadioStations;

  /// No description provided for @showFavoritePodcasts.
  ///
  /// In en, this message translates to:
  /// **'Show a row of your favorite podcasts'**
  String get showFavoritePodcasts;

  /// No description provided for @extractColorsFromArtwork.
  ///
  /// In en, this message translates to:
  /// **'Extract colors from album and artist artwork'**
  String get extractColorsFromArtwork;

  /// No description provided for @chooseHomeScreenRows.
  ///
  /// In en, this message translates to:
  /// **'Choose which rows to display on the home screen'**
  String get chooseHomeScreenRows;

  /// No description provided for @addedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get addedToFavorites;

  /// No description provided for @removedFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get removedFromFavorites;

  /// No description provided for @addedToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Added to library'**
  String get addedToLibrary;

  /// No description provided for @removedFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Removed from library'**
  String get removedFromLibrary;

  /// No description provided for @addToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get addToLibrary;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @noUpcomingTracks.
  ///
  /// In en, this message translates to:
  /// **'No upcoming tracks'**
  String get noUpcomingTracks;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAll;

  /// No description provided for @showFavoritesOnly.
  ///
  /// In en, this message translates to:
  /// **'Show favorites only'**
  String get showFavoritesOnly;

  /// No description provided for @changeView.
  ///
  /// In en, this message translates to:
  /// **'Change view'**
  String get changeView;

  /// No description provided for @authors.
  ///
  /// In en, this message translates to:
  /// **'Authors'**
  String get authors;

  /// No description provided for @series.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get series;

  /// No description provided for @shows.
  ///
  /// In en, this message translates to:
  /// **'Shows'**
  String get shows;

  /// No description provided for @podcasts.
  ///
  /// In en, this message translates to:
  /// **'Podcasts'**
  String get podcasts;

  /// No description provided for @podcastSupportComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Podcast support coming soon'**
  String get podcastSupportComingSoon;

  /// No description provided for @noPodcasts.
  ///
  /// In en, this message translates to:
  /// **'No podcasts'**
  String get noPodcasts;

  /// No description provided for @addPodcastsHint.
  ///
  /// In en, this message translates to:
  /// **'Subscribe to podcasts in Music Assistant'**
  String get addPodcastsHint;

  /// No description provided for @episodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get episodes;

  /// No description provided for @episode.
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get episode;

  /// No description provided for @playlist.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get playlist;

  /// No description provided for @connectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection Error'**
  String get connectionError;

  /// No description provided for @twoColumnGrid.
  ///
  /// In en, this message translates to:
  /// **'2-column grid'**
  String get twoColumnGrid;

  /// No description provided for @threeColumnGrid.
  ///
  /// In en, this message translates to:
  /// **'3-column grid'**
  String get threeColumnGrid;

  /// No description provided for @fromProviders.
  ///
  /// In en, this message translates to:
  /// **'From Providers'**
  String get fromProviders;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get inProgress;

  /// No description provided for @narratedBy.
  ///
  /// In en, this message translates to:
  /// **'Narrated by {narrators}'**
  String narratedBy(String narrators);

  /// No description provided for @unknownNarrator.
  ///
  /// In en, this message translates to:
  /// **'Unknown Narrator'**
  String get unknownNarrator;

  /// No description provided for @unknownAuthor.
  ///
  /// In en, this message translates to:
  /// **'Unknown Author'**
  String get unknownAuthor;

  /// No description provided for @loadingChapters.
  ///
  /// In en, this message translates to:
  /// **'Loading chapters...'**
  String get loadingChapters;

  /// No description provided for @noChapterInfoAvailable.
  ///
  /// In en, this message translates to:
  /// **'No chapter information available'**
  String get noChapterInfoAvailable;

  /// No description provided for @percentComplete.
  ///
  /// In en, this message translates to:
  /// **'{percent}% complete'**
  String percentComplete(int percent);

  /// No description provided for @theAudioDbApiKey.
  ///
  /// In en, this message translates to:
  /// **'TheAudioDB API Key'**
  String get theAudioDbApiKey;

  /// No description provided for @theAudioDbApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Use \"2\" for free tier or premium key'**
  String get theAudioDbApiKeyHint;

  /// No description provided for @audiobookLibraries.
  ///
  /// In en, this message translates to:
  /// **'Audiobook Libraries'**
  String get audiobookLibraries;

  /// No description provided for @chooseAudiobookLibraries.
  ///
  /// In en, this message translates to:
  /// **'Choose which Audiobookshelf libraries to include'**
  String get chooseAudiobookLibraries;

  /// No description provided for @unknownLibrary.
  ///
  /// In en, this message translates to:
  /// **'Unknown Library'**
  String get unknownLibrary;

  /// No description provided for @musicProviders.
  ///
  /// In en, this message translates to:
  /// **'Music Providers'**
  String get musicProviders;

  /// No description provided for @musicProvidersDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose which accounts to show in your library'**
  String get musicProvidersDescription;

  /// No description provided for @libraryRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing library...'**
  String get libraryRefreshing;

  /// No description provided for @cannotDisableLastProvider.
  ///
  /// In en, this message translates to:
  /// **'Cannot disable the last provider'**
  String get cannotDisableLastProvider;

  /// No description provided for @noSeriesFound.
  ///
  /// In en, this message translates to:
  /// **'No Series Found'**
  String get noSeriesFound;

  /// No description provided for @ensembleBugReport.
  ///
  /// In en, this message translates to:
  /// **'Ensemble Bug Report'**
  String get ensembleBugReport;

  /// No description provided for @byOwner.
  ///
  /// In en, this message translates to:
  /// **'By {owner}'**
  String byOwner(String owner);

  /// No description provided for @noSeriesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No series available from your audiobook library.\nPull to refresh.'**
  String get noSeriesAvailable;

  /// No description provided for @pullToLoadSeries.
  ///
  /// In en, this message translates to:
  /// **'Pull down to load series\nfrom Music Assistant'**
  String get pullToLoadSeries;

  /// Search navigation label
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Description for metadata APIs section
  ///
  /// In en, this message translates to:
  /// **'Artist images are automatically fetched from Deezer. Add API keys below for artist biographies and album descriptions.'**
  String get metadataApisDescription;

  /// Last.fm API key field label
  ///
  /// In en, this message translates to:
  /// **'Last.fm API Key'**
  String get lastFmApiKey;

  /// Hint for Last.fm API key field
  ///
  /// In en, this message translates to:
  /// **'Get free key at last.fm/api'**
  String get lastFmApiKeyHint;

  /// Hint for device switching gesture
  ///
  /// In en, this message translates to:
  /// **'Swipe to change player'**
  String get swipeToSwitchDevice;

  /// Chapter number display
  ///
  /// In en, this message translates to:
  /// **'Chapter {number}'**
  String chapterNumber(int number);

  /// PCM audio format label
  ///
  /// In en, this message translates to:
  /// **'PCM Audio'**
  String get pcmAudio;

  /// Bottom sheet title for selecting player
  ///
  /// In en, this message translates to:
  /// **'Play on...'**
  String get playOn;

  /// Bottom sheet title for adding album to queue
  ///
  /// In en, this message translates to:
  /// **'Add album to queue on...'**
  String get addAlbumToQueueOn;

  /// Bottom sheet title for adding to queue
  ///
  /// In en, this message translates to:
  /// **'Add to queue on...'**
  String get addToQueueOn;

  /// Bottom sheet title for starting radio
  ///
  /// In en, this message translates to:
  /// **'Start {name} radio on...'**
  String startRadioOn(String name);

  /// Singular form of book
  ///
  /// In en, this message translates to:
  /// **'book'**
  String get book;

  /// Singular form of audiobook
  ///
  /// In en, this message translates to:
  /// **'audiobook'**
  String get audiobookSingular;

  /// Singular form of album for search type indicator
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get albumSingular;

  /// Singular form of track for search type indicator
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get trackSingular;

  /// Singular form of podcast for search type indicator
  ///
  /// In en, this message translates to:
  /// **'Podcast'**
  String get podcastSingular;

  /// Track count with plural
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{track} other{tracks}}'**
  String trackCount(int count);

  /// Description for Material You theme option
  ///
  /// In en, this message translates to:
  /// **'Use system colors (Android 12+)'**
  String get materialYouDescription;

  /// Accent color selection label
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get accentColor;

  /// Players settings section title
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get players;

  /// Setting to always prefer local player
  ///
  /// In en, this message translates to:
  /// **'Prefer Local Player'**
  String get preferLocalPlayer;

  /// Description for prefer local player setting
  ///
  /// In en, this message translates to:
  /// **'Always select this device first when available'**
  String get preferLocalPlayerDescription;

  /// Setting to sort players by status
  ///
  /// In en, this message translates to:
  /// **'Smart Sort'**
  String get smartSortPlayers;

  /// Description for smart sort players setting
  ///
  /// In en, this message translates to:
  /// **'Sort by status (playing, on, off) instead of alphabetically'**
  String get smartSortPlayersDescription;

  /// Setting to disable automatic player switching
  ///
  /// In en, this message translates to:
  /// **'Disable Auto-Switch'**
  String get disableAutoSwitch;

  /// Description for disable auto-switch setting
  ///
  /// In en, this message translates to:
  /// **'Never automatically switch to a different player'**
  String get disableAutoSwitchDescription;

  /// Player state when unavailable
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get playerStateUnavailable;

  /// Player state when powered off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get playerStateOff;

  /// Player state when idle
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get playerStateIdle;

  /// Player state when playing from external source (optical, Spotify, etc.)
  ///
  /// In en, this message translates to:
  /// **'External Source'**
  String get playerStateExternalSource;

  /// Label for selected player
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get playerSelected;

  /// Message when action is queued for sync while offline
  ///
  /// In en, this message translates to:
  /// **'Will sync when online'**
  String get actionQueuedForSync;

  /// Shows number of pending offline actions
  ///
  /// In en, this message translates to:
  /// **'{count} pending sync'**
  String pendingOfflineActions(int count);

  /// Settings section title for hints
  ///
  /// In en, this message translates to:
  /// **'Hints & Tips'**
  String get hintsAndTips;

  /// Toggle label for showing hints
  ///
  /// In en, this message translates to:
  /// **'Show Hints'**
  String get showHints;

  /// Description for show hints toggle
  ///
  /// In en, this message translates to:
  /// **'Display helpful tips for discovering features'**
  String get showHintsDescription;

  /// Settings section title for display options
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get display;

  /// Toggle label for showing provider icons on album art
  ///
  /// In en, this message translates to:
  /// **'Show Provider Icons'**
  String get showProviderIcons;

  /// Description for show provider icons toggle
  ///
  /// In en, this message translates to:
  /// **'Display provider logos on album art'**
  String get showProviderIconsDescription;

  /// Hint shown when mini player bounces
  ///
  /// In en, this message translates to:
  /// **'Pull to select players'**
  String get pullToSelectPlayers;

  /// Hint for long-press to sync players
  ///
  /// In en, this message translates to:
  /// **'Long-press to sync'**
  String get holdToSync;

  /// Hint for swiping left/right to adjust player volume
  ///
  /// In en, this message translates to:
  /// **'Swipe to adjust volume'**
  String get swipeToAdjustVolume;

  /// First-time hint for selecting a player in device selector
  ///
  /// In en, this message translates to:
  /// **'Choose a player, or dismiss by swiping down'**
  String get selectPlayerHint;

  /// Welcome message title for onboarding
  ///
  /// In en, this message translates to:
  /// **'Welcome to Ensemble'**
  String get welcomeToEnsemble;

  /// Welcome message body explaining how to select players
  ///
  /// In en, this message translates to:
  /// **'By default your phone is the selected player.\nPull the mini player down to select another player.'**
  String get welcomeMessage;

  /// Button to skip onboarding or hints
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// Hint explaining how to dismiss the player selector
  ///
  /// In en, this message translates to:
  /// **'Swipe down, tap outside, or press back to return'**
  String get dismissPlayerHint;

  /// Message shown when starting to play an album
  ///
  /// In en, this message translates to:
  /// **'Playing {albumName}'**
  String playingAlbum(String albumName);

  /// Message shown when starting to play a playlist
  ///
  /// In en, this message translates to:
  /// **'Playing {playlistName}'**
  String playingPlaylist(String playlistName);

  /// Empty state title when no tracks exist in library
  ///
  /// In en, this message translates to:
  /// **'No tracks'**
  String get noTracks;

  /// Hint for adding tracks to library
  ///
  /// In en, this message translates to:
  /// **'Add some music to your library to see tracks here'**
  String get addTracksHint;

  /// Empty state when no favorite radio stations
  ///
  /// In en, this message translates to:
  /// **'No favorite radio stations'**
  String get noFavoriteRadioStations;

  /// Hint for favoriting radio stations
  ///
  /// In en, this message translates to:
  /// **'Long-press a station and tap the heart to add it to favorites'**
  String get longPressRadioHint;

  /// Empty state when no favorite podcasts
  ///
  /// In en, this message translates to:
  /// **'No favorite podcasts'**
  String get noFavoritePodcasts;

  /// Hint for favoriting podcasts
  ///
  /// In en, this message translates to:
  /// **'Long-press a podcast and tap the heart to add it to favorites'**
  String get longPressPodcastHint;

  /// Error when playing radio station fails
  ///
  /// In en, this message translates to:
  /// **'Failed to play radio station: {error}'**
  String failedToPlayRadioStation(String error);

  /// Message when trying to add item already in library
  ///
  /// In en, this message translates to:
  /// **'Item is already in library'**
  String get itemAlreadyInLibrary;

  /// Error when adding to library fails
  ///
  /// In en, this message translates to:
  /// **'Failed to add to library'**
  String get failedToAddToLibrary;

  /// Error when library ID not found for removal
  ///
  /// In en, this message translates to:
  /// **'Cannot find library ID for removal'**
  String get cannotFindLibraryId;

  /// Error when removing from library fails
  ///
  /// In en, this message translates to:
  /// **'Failed to remove from library'**
  String get failedToRemoveFromLibrary;

  /// Error when playing album fails
  ///
  /// In en, this message translates to:
  /// **'Failed to play album: {error}'**
  String failedToPlayAlbum(String error);

  /// Status when playing item on specific player
  ///
  /// In en, this message translates to:
  /// **'Playing {name} on {playerName}'**
  String playingOnPlayer(String name, String playerName);

  /// Error when playing playlist fails
  ///
  /// In en, this message translates to:
  /// **'Failed to play playlist: {error}'**
  String failedToPlayPlaylist(String error);

  /// Error when playing audiobook fails
  ///
  /// In en, this message translates to:
  /// **'Failed to play audiobook: {error}'**
  String failedToPlayAudiobook(String error);

  /// Message when no other players available for transfer
  ///
  /// In en, this message translates to:
  /// **'No other players available'**
  String get noOtherPlayersAvailable;

  /// Tooltip for transfer queue button
  ///
  /// In en, this message translates to:
  /// **'Transfer queue'**
  String get transferQueue;

  /// Tooltip for clear queue button
  ///
  /// In en, this message translates to:
  /// **'Clear queue'**
  String get clearQueue;

  /// Status when syncing player
  ///
  /// In en, this message translates to:
  /// **'Syncing {playerName}...'**
  String syncingPlayer(String playerName);

  /// Label for switch player action
  ///
  /// In en, this message translates to:
  /// **'Switch Player'**
  String get switchPlayer;

  /// Confirmation when logs copied
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard'**
  String get logsCopiedToClipboard;

  /// Auto option for language selection
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get auto;

  /// Title for transfer queue dialog
  ///
  /// In en, this message translates to:
  /// **'Transfer Queue To'**
  String get transferQueueTo;

  /// Success message when queue transferred
  ///
  /// In en, this message translates to:
  /// **'Queue transferred to {playerName}'**
  String queueTransferredTo(String playerName);

  /// Error when queue transfer fails
  ///
  /// In en, this message translates to:
  /// **'Failed to transfer queue: {error}'**
  String failedToTransferQueue(String error);

  /// Error when queue loading fails
  ///
  /// In en, this message translates to:
  /// **'Failed to load queue: {error}'**
  String failedToLoadQueue(String error);

  /// Label for transfer destination selection
  ///
  /// In en, this message translates to:
  /// **'Transfer to...'**
  String get transferTo;

  /// Tooltip for transfer queue button
  ///
  /// In en, this message translates to:
  /// **'Transfer queue to another player'**
  String get transferQueueToPlayer;

  /// Generic hint for selecting a player in player selector
  ///
  /// In en, this message translates to:
  /// **'Select a player'**
  String get selectPlayerToPlay;

  /// Hint for selecting player to play album
  ///
  /// In en, this message translates to:
  /// **'Select player to play album'**
  String get selectPlayerToPlayAlbum;

  /// Hint for selecting player to play playlist
  ///
  /// In en, this message translates to:
  /// **'Select player to play playlist'**
  String get selectPlayerToPlayPlaylist;

  /// Hint for selecting player to start radio
  ///
  /// In en, this message translates to:
  /// **'Select player for radio'**
  String get selectPlayerForRadio;

  /// Hint for selecting player to play episode
  ///
  /// In en, this message translates to:
  /// **'Select player for episode'**
  String get selectPlayerForEpisode;

  /// Hint for selecting player to play audiobook
  ///
  /// In en, this message translates to:
  /// **'Select player for audiobook'**
  String get selectPlayerForAudiobook;

  /// Hint for selecting player to add to queue
  ///
  /// In en, this message translates to:
  /// **'Select player to add to queue'**
  String get selectPlayerToAddToQueue;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return SDe();
    case 'en':
      return SEn();
    case 'es':
      return SEs();
    case 'fr':
      return SFr();
  }

  throw FlutterError(
      'S.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
