// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class SDe extends S {
  SDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Ensemble';

  @override
  String get connecting => 'Verbinde...';

  @override
  String get connected => 'Verbunden';

  @override
  String get disconnected => 'Getrennt';

  @override
  String get serverAddress => 'Serveradresse';

  @override
  String get serverAddressHint => 'z.B. music.example.com oder 192.168.1.100';

  @override
  String get yourName => 'Dein Name';

  @override
  String get yourFirstName => 'Dein Vorname';

  @override
  String get portOptional => 'Port (Optional)';

  @override
  String get portHint => 'z.B. 8095 oder leer lassen';

  @override
  String get portDescription =>
      'Leer lassen bei Reverse Proxy oder Standardports. 8095 eingeben bei Direktverbindung.';

  @override
  String get username => 'Benutzername';

  @override
  String get password => 'Passwort';

  @override
  String get detectAndConnect => 'Erkennen & Verbinden';

  @override
  String get connect => 'Verbinden';

  @override
  String get disconnect => 'Trennen';

  @override
  String get authServerUrlOptional => 'Auth-Server URL (Optional)';

  @override
  String get authServerUrlHint =>
      'z.B. auth.example.com (wenn abweichend vom Server)';

  @override
  String get authServerUrlDescription =>
      'Leer lassen, wenn Authentifizierung auf demselben Server';

  @override
  String detectedAuthType(String authType) {
    return 'Erkannt: $authType';
  }

  @override
  String get serverRequiresAuth => 'Dieser Server erfordert Authentifizierung';

  @override
  String get tailscaleVpnConnection => 'Tailscale VPN-Verbindung';

  @override
  String get unencryptedConnection => 'Unverschlusselte Verbindung';

  @override
  String get usingHttpOverTailscale =>
      'HTTP uber Tailscale (verschlusselter Tunnel)';

  @override
  String get httpsFailedUsingHttp => 'HTTPS fehlgeschlagen, verwende HTTP';

  @override
  String get httpNotEncrypted =>
      'HTTP-Verbindung - Daten sind nicht verschlusselt';

  @override
  String get pleaseEnterServerAddress =>
      'Bitte gib deine Music Assistant Serveradresse ein';

  @override
  String get pleaseEnterName => 'Bitte gib deinen Namen ein';

  @override
  String get pleaseEnterValidPort =>
      'Bitte gib eine gultige Portnummer ein (1-65535)';

  @override
  String get pleaseEnterCredentials =>
      'Bitte gib Benutzername und Passwort ein';

  @override
  String get authFailed =>
      'Authentifizierung fehlgeschlagen. Bitte uberprufe deine Anmeldedaten.';

  @override
  String get maLoginFailed =>
      'Music Assistant Anmeldung fehlgeschlagen. Bitte uberprufe deine Anmeldedaten.';

  @override
  String get connectionFailed =>
      'Verbindung zum Server fehlgeschlagen. Bitte uberprufe die Adresse und versuche es erneut.';

  @override
  String get detectingAuth => 'Erkenne Authentifizierung...';

  @override
  String get cannotDetermineAuth =>
      'Authentifizierungsanforderungen konnten nicht ermittelt werden. Bitte uberprufe die Server-URL.';

  @override
  String get noAuthentication => 'Keine Authentifizierung';

  @override
  String get httpBasicAuth => 'HTTP Basic Auth';

  @override
  String get authelia => 'Authelia';

  @override
  String get musicAssistantLogin => 'Music Assistant Anmeldung';

  @override
  String get pressBackToMinimize => 'Erneut drucken zum Minimieren';

  @override
  String get recentlyPlayed => 'Zuletzt gespielt';

  @override
  String get discoverArtists => 'Kunstler entdecken';

  @override
  String get discoverAlbums => 'Alben entdecken';

  @override
  String get continueListening => 'Weiterhoren';

  @override
  String get discoverAudiobooks => 'Horbücher entdecken';

  @override
  String get discoverSeries => 'Serien entdecken';

  @override
  String get favoriteAlbums => 'Lieblingsalben';

  @override
  String get favoriteArtists => 'Lieblingskünstler';

  @override
  String get favoriteTracks => 'Lieblingssongs';

  @override
  String get favoritePlaylists => 'Favorite Playlists';

  @override
  String get favoriteRadioStations => 'Favorite Radio Stations';

  @override
  String get favoritePodcasts => 'Favorite Podcasts';

  @override
  String get searchMusic => 'Musik suchen...';

  @override
  String get searchForContent => 'Nach Künstlern, Alben oder Songs suchen';

  @override
  String get recentSearches => 'Recent Searches';

  @override
  String get clearSearchHistory => 'Clear Search History';

  @override
  String get searchHistoryCleared => 'Search history cleared';

  @override
  String get libraryOnly => 'Library only';

  @override
  String get retry => 'Wiederholen';

  @override
  String get all => 'Alle';

  @override
  String get artists => 'Künstler';

  @override
  String get albums => 'Alben';

  @override
  String get tracks => 'Songs';

  @override
  String get playlists => 'Wiedergabelisten';

  @override
  String get audiobooks => 'Hörbücher';

  @override
  String get music => 'Musik';

  @override
  String get radio => 'Radio';

  @override
  String get stations => 'Sender';

  @override
  String get selectLibrary => 'Bibliothek auswählen';

  @override
  String get noRadioStations => 'Keine Radiosender';

  @override
  String get addRadioStationsHint =>
      'Füge Radiosender in Music Assistant hinzu';

  @override
  String get searchFailed =>
      'Suche fehlgeschlagen. Bitte überprüfe deine Verbindung.';

  @override
  String get queue => 'Warteschlange';

  @override
  String playerQueue(String playerName) {
    return '$playerName Warteschlange';
  }

  @override
  String get noPlayerSelected => 'Kein Player ausgewählt';

  @override
  String get undo => 'Rückgängig';

  @override
  String removedItem(String itemName) {
    return '$itemName entfernt';
  }

  @override
  String get settings => 'Einstellungen';

  @override
  String get debugLogs => 'Debug-Protokolle';

  @override
  String get themeMode => 'Design';

  @override
  String get light => 'Hell';

  @override
  String get dark => 'Dunkel';

  @override
  String get system => 'System';

  @override
  String get pullToRefresh => 'Ziehe zum Aktualisieren der Bibliothek';

  @override
  String get viewDebugLogs => 'Debug-Protokolle anzeigen';

  @override
  String get viewAllPlayers => 'Alle Player anzeigen';

  @override
  String get copyLogs => 'Protokolle kopieren';

  @override
  String get clearLogs => 'Protokolle löschen';

  @override
  String get copyList => 'Liste kopieren';

  @override
  String get close => 'Schließen';

  @override
  String allPlayersCount(int count) {
    return 'Alle Player ($count)';
  }

  @override
  String errorLoadingPlayers(String error) {
    return 'Fehler beim Laden der Player: $error';
  }

  @override
  String get logsCopied => 'Protokolle in Zwischenablage kopiert';

  @override
  String get logsCleared => 'Protokolle gelöscht';

  @override
  String get playerListCopied => 'Playerliste in Zwischenablage kopiert!';

  @override
  String get noLogsYet => 'Noch keine Protokolle';

  @override
  String get infoPlus => 'Info+';

  @override
  String get warnings => 'Warnungen';

  @override
  String get errors => 'Fehler';

  @override
  String showingEntries(int filtered, int total) {
    return 'Zeige $filtered von $total Einträgen';
  }

  @override
  String get thisDevice => 'Dieses Gerät';

  @override
  String get ghostPlayer => 'Geist-Player (Duplikat)';

  @override
  String get unavailableCorrupt => 'Nicht verfügbar/Beschädigt';

  @override
  String playerId(String id) {
    return 'ID: $id';
  }

  @override
  String playerInfo(String available, String provider) {
    return 'Verfügbar: $available | Anbieter: $provider';
  }

  @override
  String get shareBugReport => 'Fehlerbericht teilen';

  @override
  String get moreOptions => 'Weitere Optionen';

  @override
  String failedToUpdateFavorite(String error) {
    return 'Favorit konnte nicht aktualisiert werden: $error';
  }

  @override
  String get noPlayersAvailable => 'Keine Player verfügbar';

  @override
  String get albumAddedToQueue => 'Album zur Warteschlange hinzugefügt';

  @override
  String get tracksAddedToQueue => 'Songs zur Warteschlange hinzugefügt';

  @override
  String get play => 'Abspielen';

  @override
  String get noPlayersFound => 'Keine Player gefunden';

  @override
  String startingRadio(String name) {
    return 'Starte $name Radio';
  }

  @override
  String failedToStartRadio(String error) {
    return 'Radio konnte nicht gestartet werden: $error';
  }

  @override
  String startingRadioOnPlayer(String name, String playerName) {
    return 'Starte $name Radio auf $playerName';
  }

  @override
  String addedRadioToQueue(String name) {
    return '$name Radio zur Warteschlange hinzugefügt';
  }

  @override
  String failedToAddToQueue(String error) {
    return 'Konnte nicht zur Warteschlange hinzufügen: $error';
  }

  @override
  String playingRadioStation(String name) {
    return 'Playing $name';
  }

  @override
  String get addedToQueue => 'Added to queue';

  @override
  String get inLibrary => 'In Bibliothek';

  @override
  String get noAlbumsFound => 'Keine Alben gefunden';

  @override
  String playing(String name) {
    return 'Spiele $name';
  }

  @override
  String get playingTrack => 'Spiele Song';

  @override
  String get nowPlaying => 'Wird gespielt';

  @override
  String markedAsFinished(String name) {
    return '$name als beendet markiert';
  }

  @override
  String failedToMarkFinished(String error) {
    return 'Konnte nicht als beendet markieren: $error';
  }

  @override
  String markedAsUnplayed(String name) {
    return '$name als ungespielt markiert';
  }

  @override
  String failedToMarkUnplayed(String error) {
    return 'Konnte nicht als ungespielt markieren: $error';
  }

  @override
  String failedToPlay(String error) {
    return 'Abspielen fehlgeschlagen: $error';
  }

  @override
  String get markAsFinished => 'Als beendet markieren';

  @override
  String get markAsUnplayed => 'Als ungespielt markieren';

  @override
  String byAuthor(String author) {
    return 'Von $author';
  }

  @override
  String audiobookCount(int count) {
    return '$count Hörbuch/Hörbücher';
  }

  @override
  String get loading => 'Laden...';

  @override
  String bookCount(int count) {
    return '$count Buch/Bücher';
  }

  @override
  String get books => 'Bücher';

  @override
  String get noFavoriteAudiobooks => 'Keine Lieblingshörbücher';

  @override
  String get tapHeartAudiobook =>
      'Tippe auf das Herz bei einem Hörbuch, um es zu Favoriten hinzuzufügen';

  @override
  String get noAudiobooks => 'Keine Hörbücher';

  @override
  String get addAudiobooksHint =>
      'Füge Hörbücher zu deiner Bibliothek hinzu, um sie hier zu sehen';

  @override
  String get noFavoriteArtists => 'Keine Lieblingskünstler';

  @override
  String get tapHeartArtist =>
      'Tippe auf das Herz bei einem Künstler, um ihn zu Favoriten hinzuzufügen';

  @override
  String get noFavoriteAlbums => 'Keine Lieblingsalben';

  @override
  String get tapHeartAlbum =>
      'Tippe auf das Herz bei einem Album, um es zu Favoriten hinzuzufügen';

  @override
  String get noFavoritePlaylists => 'Keine Lieblings-Wiedergabelisten';

  @override
  String get tapHeartPlaylist =>
      'Tippe auf das Herz bei einer Wiedergabeliste, um sie zu Favoriten hinzuzufügen';

  @override
  String get noFavoriteTracks => 'Keine Lieblingssongs';

  @override
  String get longPressTrackHint =>
      'Halte einen Song gedrückt und tippe auf das Herz, um ihn zu Favoriten hinzuzufügen';

  @override
  String get loadSeries => 'Serien laden';

  @override
  String get notConnected => 'Nicht mit Music Assistant verbunden';

  @override
  String get notConnectedTitle => 'Nicht verbunden';

  @override
  String get connectHint =>
      'Verbinde dich mit deinem Music Assistant Server, um Musik zu hören';

  @override
  String get configureServer => 'Server konfigurieren';

  @override
  String get noArtistsFound => 'Keine Künstler gefunden';

  @override
  String get noTracksFound => 'Keine Songs gefunden';

  @override
  String get noPlaylistsFound => 'Keine Wiedergabelisten gefunden';

  @override
  String get queueIsEmpty => 'Warteschlange ist leer';

  @override
  String get noResultsFound => 'Keine Ergebnisse gefunden';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get debugConsole => 'Debug-Konsole';

  @override
  String get copy => 'Kopieren';

  @override
  String get clear => 'Löschen';

  @override
  String get noLogsToCopy => 'Keine Protokolle zum Kopieren';

  @override
  String get noDebugLogsYet =>
      'Noch keine Debug-Protokolle. Versuche Authentifizierung zu erkennen.';

  @override
  String get showDebug => 'Debug anzeigen';

  @override
  String get hideDebug => 'Debug ausblenden';

  @override
  String get chapters => 'Kapitel';

  @override
  String get noChapters => 'Keine Kapitel';

  @override
  String get noChapterInfo => 'Dieses Hörbuch hat keine Kapitelinformationen';

  @override
  String errorSeeking(String error) {
    return 'Fehler beim Spulen: $error';
  }

  @override
  String error(String error) {
    return 'Fehler: $error';
  }

  @override
  String get home => 'Start';

  @override
  String get library => 'Bibliothek';

  @override
  String get homeScreen => 'Startbildschirm';

  @override
  String get metadataApis => 'Metadaten-APIs';

  @override
  String get theme => 'Design';

  @override
  String get materialYou => 'Material You';

  @override
  String get adaptiveTheme => 'Adaptives Design';

  @override
  String get language => 'Sprache';

  @override
  String get english => 'Englisch';

  @override
  String get german => 'Deutsch';

  @override
  String get spanish => 'Spanisch';

  @override
  String get french => 'Französisch';

  @override
  String get noTracksInPlaylist => 'Keine Songs in Wiedergabeliste';

  @override
  String get sortAlphabetically => 'Alphabetisch sortieren';

  @override
  String get sortByYear => 'Nach Jahr sortieren';

  @override
  String get sortBySeriesOrder => 'Nach Serienreihenfolge sortieren';

  @override
  String get listView => 'Listenansicht';

  @override
  String get gridView => 'Rasteransicht';

  @override
  String get noBooksInSeries => 'Keine Bücher in dieser Serie gefunden';

  @override
  String get artist => 'Künstler';

  @override
  String get showRecentlyPlayedAlbums => 'Kürzlich gespielte Alben anzeigen';

  @override
  String get showRandomArtists => 'Zufällige Künstler zum Entdecken anzeigen';

  @override
  String get showRandomAlbums => 'Zufällige Alben zum Entdecken anzeigen';

  @override
  String get showAudiobooksInProgress => 'Hörbücher in Bearbeitung anzeigen';

  @override
  String get showRandomAudiobooks =>
      'Zufällige Hörbücher zum Entdecken anzeigen';

  @override
  String get showRandomSeries =>
      'Zufällige Hörbuchserien zum Entdecken anzeigen';

  @override
  String get showFavoriteAlbums => 'Lieblingsalben anzeigen';

  @override
  String get showFavoriteArtists => 'Lieblingskünstler anzeigen';

  @override
  String get showFavoriteTracks => 'Lieblingssongs anzeigen';

  @override
  String get showFavoritePlaylists => 'Show a row of your favorite playlists';

  @override
  String get showFavoriteRadioStations =>
      'Show a row of your favorite radio stations';

  @override
  String get showFavoritePodcasts => 'Show a row of your favorite podcasts';

  @override
  String get extractColorsFromArtwork =>
      'Farben aus Album- und Künstlercover extrahieren';

  @override
  String get chooseHomeScreenRows =>
      'Wähle welche Zeilen auf dem Startbildschirm angezeigt werden';

  @override
  String get addedToFavorites => 'Zu Favoriten hinzugefügt';

  @override
  String get removedFromFavorites => 'Aus Favoriten entfernt';

  @override
  String get addedToLibrary => 'Added to library';

  @override
  String get removedFromLibrary => 'Removed from library';

  @override
  String get addToLibrary => 'Add to library';

  @override
  String get unknown => 'Unbekannt';

  @override
  String get noUpcomingTracks => 'Keine weiteren Songs';

  @override
  String get showAll => 'Alle anzeigen';

  @override
  String get showFavoritesOnly => 'Nur Favoriten anzeigen';

  @override
  String get changeView => 'Ansicht ändern';

  @override
  String get authors => 'Autoren';

  @override
  String get series => 'Serien';

  @override
  String get shows => 'Sendungen';

  @override
  String get podcasts => 'Podcasts';

  @override
  String get podcastSupportComingSoon => 'Podcast-Unterstützung kommt bald';

  @override
  String get noPodcasts => 'No podcasts';

  @override
  String get addPodcastsHint => 'Subscribe to podcasts in Music Assistant';

  @override
  String get episodes => 'Episodes';

  @override
  String get episode => 'Episode';

  @override
  String get playlist => 'Wiedergabeliste';

  @override
  String get connectionError => 'Verbindungsfehler';

  @override
  String get twoColumnGrid => '2-Spalten-Raster';

  @override
  String get threeColumnGrid => '3-Spalten-Raster';

  @override
  String get fromProviders => 'Von Anbietern';

  @override
  String get resume => 'Fortsetzen';

  @override
  String get about => 'Über';

  @override
  String get inProgress => 'In Bearbeitung';

  @override
  String narratedBy(String narrators) {
    return 'Gesprochen von $narrators';
  }

  @override
  String get unknownNarrator => 'Unbekannter Sprecher';

  @override
  String get unknownAuthor => 'Unbekannter Autor';

  @override
  String get loadingChapters => 'Lade Kapitel...';

  @override
  String get noChapterInfoAvailable => 'Keine Kapitelinformationen verfügbar';

  @override
  String percentComplete(int percent) {
    return '$percent% abgeschlossen';
  }

  @override
  String get theAudioDbApiKey => 'TheAudioDB API-Schlüssel';

  @override
  String get theAudioDbApiKeyHint =>
      '\"2\" für kostenlosen Zugang oder Premium-Schlüssel';

  @override
  String get audiobookLibraries => 'Hörbuch-Bibliotheken';

  @override
  String get chooseAudiobookLibraries =>
      'Wähle welche Audiobookshelf-Bibliotheken einbezogen werden';

  @override
  String get unknownLibrary => 'Unbekannte Bibliothek';

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
  String get noSeriesFound => 'Keine Serien gefunden';

  @override
  String get ensembleBugReport => 'Ensemble Fehlerbericht';

  @override
  String byOwner(String owner) {
    return 'Von $owner';
  }

  @override
  String get noSeriesAvailable =>
      'Keine Serien in deiner Hörbuch-Bibliothek verfügbar.\nZiehe zum Aktualisieren.';

  @override
  String get pullToLoadSeries =>
      'Ziehe nach unten um Serien\nvon Music Assistant zu laden';

  @override
  String get search => 'Suche';

  @override
  String get metadataApisDescription =>
      'Künstlerbilder werden automatisch von Deezer abgerufen. Füge unten API-Schlüssel für Künstlerbiografien und Albenbeschreibungen hinzu.';

  @override
  String get lastFmApiKey => 'Last.fm API-Schlüssel';

  @override
  String get lastFmApiKeyHint => 'Kostenlosen Schlüssel auf last.fm/api holen';

  @override
  String get swipeToSwitchDevice => 'Wischen um Gerät zu wechseln';

  @override
  String chapterNumber(int number) {
    return 'Kapitel $number';
  }

  @override
  String get pcmAudio => 'PCM-Audio';

  @override
  String get playOn => 'Abspielen auf...';

  @override
  String get addAlbumToQueueOn => 'Album zur Warteschlange hinzufügen auf...';

  @override
  String get addToQueueOn => 'Zur Warteschlange hinzufügen auf...';

  @override
  String startRadioOn(String name) {
    return '$name Radio starten auf...';
  }

  @override
  String get book => 'Buch';

  @override
  String get audiobookSingular => 'Hörbuch';

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
      other: 'Songs',
      one: 'Song',
    );
    return '$count $_temp0';
  }

  @override
  String get materialYouDescription => 'Systemfarben verwenden (Android 12+)';

  @override
  String get accentColor => 'Akzentfarbe';

  @override
  String get players => 'Geräte';

  @override
  String get preferLocalPlayer => 'Lokales Gerät bevorzugen';

  @override
  String get preferLocalPlayerDescription =>
      'Dieses Gerät immer zuerst auswählen, wenn verfügbar';

  @override
  String get smartSortPlayers => 'Intelligente Sortierung';

  @override
  String get smartSortPlayersDescription =>
      'Nach Status sortieren (spielt, an, aus) statt alphabetisch';

  @override
  String get disableAutoSwitch => 'Disable Auto-Switch';

  @override
  String get disableAutoSwitchDescription =>
      'Never automatically switch to a different player';

  @override
  String get playerStateUnavailable => 'Nicht verfügbar';

  @override
  String get playerStateOff => 'Aus';

  @override
  String get playerStateIdle => 'Inaktiv';

  @override
  String get playerStateExternalSource => 'Externe Quelle';

  @override
  String get playerSelected => 'Ausgewählt';

  @override
  String get actionQueuedForSync => 'Wird synchronisiert wenn online';

  @override
  String pendingOfflineActions(int count) {
    return '$count ausstehende Synchronisierung';
  }

  @override
  String get hintsAndTips => 'Tipps & Hinweise';

  @override
  String get showHints => 'Hinweise anzeigen';

  @override
  String get showHintsDescription =>
      'Hilfreiche Tipps zum Entdecken von Funktionen anzeigen';

  @override
  String get display => 'Display';

  @override
  String get showProviderIcons => 'Show Provider Icons';

  @override
  String get showProviderIconsDescription =>
      'Display provider logos on album art';

  @override
  String get pullToSelectPlayers => 'Ziehen um Geräte auszuwählen';

  @override
  String get holdToSync => 'Gedrückt halten zum Sync';

  @override
  String get swipeToAdjustVolume => 'Wischen für Lautstärke';

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
