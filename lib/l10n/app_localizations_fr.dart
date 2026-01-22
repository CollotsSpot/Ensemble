// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class SFr extends S {
  SFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Ensemble';

  @override
  String get connecting => 'Connexion...';

  @override
  String get connected => 'Connecté';

  @override
  String get disconnected => 'Déconnecté';

  @override
  String get serverAddress => 'Adresse du serveur';

  @override
  String get serverAddressHint => 'ex., music.example.com ou 192.168.1.100';

  @override
  String get yourName => 'Votre nom';

  @override
  String get yourFirstName => 'Votre prénom';

  @override
  String get portOptional => 'Port (Facultatif)';

  @override
  String get portHint => 'ex., 8095 ou laisser vide';

  @override
  String get portDescription =>
      'Laisser vide pour les proxys inverses ou les ports standards. Entrer 8095 pour une connexion directe.';

  @override
  String get username => 'Nom d\'utilisateur';

  @override
  String get password => 'Mot de passe';

  @override
  String get detectAndConnect => 'Détecter et connecter';

  @override
  String get connect => 'Connectér';

  @override
  String get disconnect => 'Déconnectér';

  @override
  String get authServerUrlOptional => 'URL du serveur d\'auth (Facultatif)';

  @override
  String get authServerUrlHint =>
      'ex., auth.example.com (si different du serveur)';

  @override
  String get authServerUrlDescription =>
      'Laisser vide si l\'authentification est sur le meme serveur';

  @override
  String detectedAuthType(String authType) {
    return 'Detected: $authType';
  }

  @override
  String get serverRequiresAuth => 'Ce serveur requiert une authentification';

  @override
  String get tailscaleVpnConnection => 'Connexion VPN Tailscale';

  @override
  String get unencryptedConnection => 'Connexion non chiffrée';

  @override
  String get usingHttpOverTailscale =>
      'Utilisation de HTTP via Tailscale (tunnel chiffre)';

  @override
  String get httpsFailedUsingHttp =>
      'HTTPS a échoué, utilisation de HTTP en repli';

  @override
  String get httpNotEncrypted =>
      'Connexion HTTP - les donnees ne sont pas chiffrées';

  @override
  String get pleaseEnterServerAddress =>
      'Veuillez entrer l\'adresse de votre serveur Music Assistant';

  @override
  String get pleaseEnterName => 'Veuillez entrer votre nom';

  @override
  String get pleaseEnterValidPort =>
      'Veuillez entrer un numero de port valide (1-65535)';

  @override
  String get pleaseEnterCredentials =>
      'Veuillez entrer le nom d\'utilisateur et le mot de passe';

  @override
  String get authFailed =>
      'Echec de l\'authentification. Veuillez verifier vos identifiants.';

  @override
  String get maLoginFailed =>
      'Echec de la connexion a Music Assistant. Veuillez verifier vos identifiants.';

  @override
  String get connectionFailed =>
      'Impossible de se connecter au serveur. Veuillez verifier l\'adresse et reessayer.';

  @override
  String get detectingAuth => 'Detection de l\'authentification...';

  @override
  String get cannotDetermineAuth =>
      'Impossible de determiner les exigences d\'authentification. Veuillez verifier l\'URL du serveur.';

  @override
  String get noAuthentication => 'Pas d\'authentification';

  @override
  String get httpBasicAuth => 'HTTP Basic Auth';

  @override
  String get authelia => 'Authelia';

  @override
  String get musicAssistantLogin => 'Connexion Music Assistant';

  @override
  String get pressBackToMinimize =>
      'Appuyez a nouveau sur retour pour minimiser';

  @override
  String get recentlyPlayed => 'Ecoutes recemment';

  @override
  String get discoverArtists => 'Découvrir des artistes';

  @override
  String get discoverAlbums => 'Découvrir des albums';

  @override
  String get continueListening => 'Continuer l\'écoute';

  @override
  String get discoverAudiobooks => 'Découvrir des livres audio';

  @override
  String get discoverSeries => 'Découvrir des séries';

  @override
  String get favoriteAlbums => 'Albums favoris';

  @override
  String get favoriteArtists => 'Artistes favoris';

  @override
  String get favoriteTracks => 'Pistes favorites';

  @override
  String get favoritePlaylists => 'Playlists favorites';

  @override
  String get favoriteRadioStations => 'Stations de radio favorites';

  @override
  String get favoritePodcasts => 'Podcasts favoris';

  @override
  String get searchMusic => 'Rechercher de la musique...';

  @override
  String get searchForContent => 'Rechercher des artistes, albums ou pistes';

  @override
  String get recentSearches => 'Recherches recentes';

  @override
  String get clearSearchHistory => 'Effacer l\'historique de recherche';

  @override
  String get searchHistoryCleared => 'Historique de recherche efface';

  @override
  String get libraryOnly => 'Bibliothèque uniquement';

  @override
  String get retry => 'Reessayer';

  @override
  String get all => 'Tout';

  @override
  String get artists => 'Artistes';

  @override
  String get albums => 'Albums';

  @override
  String get tracks => 'Pistes';

  @override
  String get playlists => 'Playlists';

  @override
  String get audiobooks => 'Livres audio';

  @override
  String get music => 'Musique';

  @override
  String get radio => 'Radio';

  @override
  String get stations => 'Stations';

  @override
  String get selectLibrary => 'Sélectionner la bibliothèque';

  @override
  String get noRadioStations => 'Aucune station de radio';

  @override
  String get addRadioStationsHint =>
      'Ajouter des stations de radio dans Music Assistant';

  @override
  String get searchFailed =>
      'La recherche a échoué. Veuillez verifier votre connexion.';

  @override
  String get queue => 'File d\'attente';

  @override
  String playerQueue(String playerName) {
    return 'File d\'attente de $playerName';
  }

  @override
  String get noPlayerSelected => 'Aucun lecteur selectionne';

  @override
  String get undo => 'Annuler';

  @override
  String removedItem(String itemName) {
    return '$itemName supprimé';
  }

  @override
  String get settings => 'Paramètres';

  @override
  String get debugLogs => 'Journaux de debogage';

  @override
  String get themeMode => 'Mode de theme';

  @override
  String get light => 'Clair';

  @override
  String get dark => 'Sombre';

  @override
  String get system => 'Système';

  @override
  String get pullToRefresh =>
      'Tirez pour rafraichir la bibliothèque et appliquer les modifications';

  @override
  String get viewDebugLogs => 'Voir les journaux de debogage';

  @override
  String get viewAllPlayers => 'Voir tous les lecteurs';

  @override
  String get copyLogs => 'Copier les journaux';

  @override
  String get clearLogs => 'Effacer les journaux';

  @override
  String get copyList => 'Copier la liste';

  @override
  String get close => 'Fermer';

  @override
  String allPlayersCount(int count) {
    return 'Tous les lecteurs ($count)';
  }

  @override
  String errorLoadingPlayers(String error) {
    return 'Erreur lors du chargement des lecteurs : $error';
  }

  @override
  String get logsCopied => 'Journaux copies dans le presse-papiers';

  @override
  String get logsCleared => 'Journaux effaces';

  @override
  String get playerListCopied =>
      'Liste des lecteurs copiee dans le presse-papiers !';

  @override
  String get noLogsYet => 'Pas encore de journaux';

  @override
  String get infoPlus => 'Info+';

  @override
  String get warnings => 'Avertissements';

  @override
  String get errors => 'Erreurs';

  @override
  String showingEntries(int filtered, int total) {
    return 'Affichage de $filtered sur $total entrées';
  }

  @override
  String get thisDevice => 'Cet appareil';

  @override
  String get ghostPlayer => 'Lecteur fantome (doublon)';

  @override
  String get unavailableCorrupt => 'Indisponible/Corrompu';

  @override
  String playerId(String id) {
    return 'ID : $id';
  }

  @override
  String playerInfo(String available, String provider) {
    return 'Disponible : $available | Fournisseur : $provider';
  }

  @override
  String get shareBugReport => 'Partager le rapport de bogue';

  @override
  String get moreOptions => 'Plus d\'options';

  @override
  String failedToUpdateFavorite(String error) {
    return 'Echec de la mise a jour du favori : $error';
  }

  @override
  String get noPlayersAvailable => 'Aucun lecteur disponible';

  @override
  String get albumAddedToQueue => 'Album ajouté a la file d\'attente';

  @override
  String get tracksAddedToQueue => 'Pistes ajoutées a la file d\'attente';

  @override
  String get play => 'Lire';

  @override
  String get noPlayersFound => 'Aucun lecteur trouve';

  @override
  String startingRadio(String name) {
    return 'Demarrage de la radio $name';
  }

  @override
  String failedToStartRadio(String error) {
    return 'Echec du demarrage de la radio : $error';
  }

  @override
  String startingRadioOnPlayer(String name, String playerName) {
    return 'Demarrage de la radio $name sur $playerName';
  }

  @override
  String addedRadioToQueue(String name) {
    return 'Radio $name ajoutée a la file d\'attente';
  }

  @override
  String failedToAddToQueue(String error) {
    return 'Echec de l\'ajout a la file d\'attente : $error';
  }

  @override
  String playingRadioStation(String name) {
    return 'Lecture de $name';
  }

  @override
  String get addedToQueue => 'Ajoute a la file d\'attente';

  @override
  String get inLibrary => 'Dans la bibliothèque';

  @override
  String get noAlbumsFound => 'Aucun album trouve';

  @override
  String playing(String name) {
    return 'Lecture de $name';
  }

  @override
  String get playingTrack => 'Lecture de la piste';

  @override
  String get nowPlaying => 'En cours de lecture';

  @override
  String markedAsFinished(String name) {
    return '$name marque comme termine';
  }

  @override
  String failedToMarkFinished(String error) {
    return 'Echec du marquage comme termine : $error';
  }

  @override
  String markedAsUnplayed(String name) {
    return '$name marque comme non lu';
  }

  @override
  String failedToMarkUnplayed(String error) {
    return 'Echec du marquage comme non lu : $error';
  }

  @override
  String failedToPlay(String error) {
    return 'Echec de la lecture : $error';
  }

  @override
  String get markAsFinished => 'Marquer comme termine';

  @override
  String get markAsUnplayed => 'Marquer comme non lu';

  @override
  String byAuthor(String author) {
    return 'Par $author';
  }

  @override
  String audiobookCount(int count) {
    return '$count livre(s) audio';
  }

  @override
  String get loading => 'Chargement...';

  @override
  String bookCount(int count) {
    return '$count livre(s)';
  }

  @override
  String get books => 'Livres';

  @override
  String get noFavoriteAudiobooks => 'Aucun livre audio favori';

  @override
  String get tapHeartAudiobook =>
      'Appuyez sur le coeur d\'un livre audio pour l\'ajoutér aux favoris';

  @override
  String get noAudiobooks => 'Aucun livre audio';

  @override
  String get addAudiobooksHint =>
      'Ajoutez des livres audio a votre bibliothèque pour les voir ici';

  @override
  String get noFavoriteArtists => 'Aucun artiste favori';

  @override
  String get tapHeartArtist =>
      'Appuyez sur le coeur d\'un artiste pour l\'ajoutér aux favoris';

  @override
  String get noFavoriteAlbums => 'Aucun album favori';

  @override
  String get tapHeartAlbum =>
      'Appuyez sur le coeur d\'un album pour l\'ajoutér aux favoris';

  @override
  String get noFavoritePlaylists => 'Aucune playlist favorite';

  @override
  String get tapHeartPlaylist =>
      'Appuyez sur le coeur d\'une playlist pour l\'ajoutér aux favoris';

  @override
  String get noFavoriteTracks => 'Aucune piste favorite';

  @override
  String get longPressTrackHint =>
      'Appuyez longuement sur une piste et touchez le coeur pour l\'ajoutér aux favoris';

  @override
  String get loadSeries => 'Charger les séries';

  @override
  String get notConnected => 'Not connected to Music Assistant';

  @override
  String get notConnectedTitle => 'Not Connected';

  @override
  String get connectHint =>
      'Connectéz-vous a votre serveur Music Assistant pour commencer a écouter';

  @override
  String get configureServer => 'Configurer le serveur';

  @override
  String get noArtistsFound => 'Aucun artiste trouve';

  @override
  String get noTracksFound => 'Aucune piste trouvee';

  @override
  String get noPlaylistsFound => 'Aucune playlist trouvee';

  @override
  String get queueIsEmpty => 'La file d\'attente est vide';

  @override
  String get noResultsFound => 'Aucun resultat trouve';

  @override
  String get refresh => 'Rafraichir';

  @override
  String get debugConsole => 'Console de debogage';

  @override
  String get copy => 'Copier';

  @override
  String get clear => 'Effacer';

  @override
  String get noLogsToCopy => 'Aucun journal a copier';

  @override
  String get noDebugLogsYet =>
      'Pas encore de journaux de debogage. Essayez de détectér l\'authentification.';

  @override
  String get showDebug => 'Afficher le debogage';

  @override
  String get hideDebug => 'Masquer le debogage';

  @override
  String get chapters => 'Chapitres';

  @override
  String get noChapters => 'Aucun chapitre';

  @override
  String get noChapterInfo =>
      'Ce livre audio n\'a pas d\'informations de chapitre';

  @override
  String errorSeeking(String error) {
    return 'Erreur de positionnement : $error';
  }

  @override
  String error(String error) {
    return 'Erreur : $error';
  }

  @override
  String get home => 'Accueil';

  @override
  String get library => 'Bibliothèque';

  @override
  String get homeScreen => 'Ecran d\'accueil';

  @override
  String get metadataApis => 'API de metadonnees';

  @override
  String get theme => 'Theme';

  @override
  String get materialYou => 'Material You';

  @override
  String get adaptiveTheme => 'Theme adaptatif';

  @override
  String get language => 'Langue';

  @override
  String get english => 'Anglais';

  @override
  String get german => 'Allemand';

  @override
  String get spanish => 'Espagnol';

  @override
  String get french => 'Français';

  @override
  String get noTracksInPlaylist => 'Aucune piste dans la playlist';

  @override
  String get sortAlphabetically => 'Trier alphabétiquement';

  @override
  String get sortByYear => 'Trier par année';

  @override
  String get sortBySeriesOrder => 'Trier par ordre de série';

  @override
  String get listView => 'Vue en liste';

  @override
  String get gridView => 'Vue en grille';

  @override
  String get noBooksInSeries => 'Aucun livre trouve dans cette série';

  @override
  String get artist => 'Artiste';

  @override
  String get showRecentlyPlayedAlbums =>
      'Afficher les albums écoutes recemment';

  @override
  String get showRandomArtists =>
      'Afficher des artistes aléatoires a découvrir';

  @override
  String get showRandomAlbums => 'Afficher des albums aléatoires a découvrir';

  @override
  String get showAudiobooksInProgress => 'Afficher les livres audio en cours';

  @override
  String get showRandomAudiobooks =>
      'Afficher des livres audio aléatoires a découvrir';

  @override
  String get showRandomSeries =>
      'Afficher des séries de livres audio aléatoires a découvrir';

  @override
  String get showFavoriteAlbums => 'Afficher une rangee de vos albums favoris';

  @override
  String get showFavoriteArtists =>
      'Afficher une rangee de vos artistes favoris';

  @override
  String get showFavoriteTracks =>
      'Afficher une rangee de vos pistes favorites';

  @override
  String get showFavoritePlaylists =>
      'Afficher une rangee de vos playlists favorites';

  @override
  String get showFavoriteRadioStations =>
      'Afficher une rangee de vos stations de radio favorites';

  @override
  String get showFavoritePodcasts =>
      'Afficher une rangee de vos podcasts favoris';

  @override
  String get extractColorsFromArtwork =>
      'Extraire les couleurs des pochettes d\'albums et d\'artistes';

  @override
  String get chooseHomeScreenRows =>
      'Choisir les rangees a afficher sur l\'ecran d\'accueil';

  @override
  String get addedToFavorites => 'Ajoute aux favoris';

  @override
  String get removedFromFavorites => 'Retire des favoris';

  @override
  String get addedToLibrary => 'Ajoute a la bibliothèque';

  @override
  String get removedFromLibrary => 'Retire de la bibliothèque';

  @override
  String get addToLibrary => 'Ajouter a la bibliothèque';

  @override
  String get unknown => 'Inconnu';

  @override
  String get noUpcomingTracks => 'Aucune piste a venir';

  @override
  String get showAll => 'Tout afficher';

  @override
  String get showFavoritesOnly => 'Afficher les favoris uniquement';

  @override
  String get changeView => 'Changer la vue';

  @override
  String get authors => 'Auteurs';

  @override
  String get series => 'Series';

  @override
  String get shows => 'Emissions';

  @override
  String get podcasts => 'Podcasts';

  @override
  String get podcastSupportComingSoon =>
      'Prise en charge des podcasts bientot disponible';

  @override
  String get noPodcasts => 'Aucun podcast';

  @override
  String get addPodcastsHint =>
      'Abonnez-vous a des podcasts dans Music Assistant';

  @override
  String get episodes => 'Episodes';

  @override
  String get episode => 'Episode';

  @override
  String get playlist => 'Playlist';

  @override
  String get connectionError => 'Erreur de connexion';

  @override
  String get twoColumnGrid => 'Grille a 2 colonnes';

  @override
  String get threeColumnGrid => 'Grille a 3 colonnes';

  @override
  String get fromProviders => 'Des fournisseurs';

  @override
  String get resume => 'Reprendre';

  @override
  String get about => 'A propos';

  @override
  String get inProgress => 'En cours';

  @override
  String narratedBy(String narrators) {
    return 'Lu par $narrators';
  }

  @override
  String get unknownNarrator => 'Narrateur inconnu';

  @override
  String get unknownAuthor => 'Auteur inconnu';

  @override
  String get loadingChapters => 'Chargement des chapitres...';

  @override
  String get noChapterInfoAvailable =>
      'Aucune information de chapitre disponible';

  @override
  String percentComplete(int percent) {
    return '$percent% termine';
  }

  @override
  String get theAudioDbApiKey => 'Cle API TheAudioDB';

  @override
  String get theAudioDbApiKeyHint =>
      'Utilisez \"2\" pour le niveau gratuit ou une cle premium';

  @override
  String get audiobookLibraries => 'Bibliothèques de livres audio';

  @override
  String get chooseAudiobookLibraries =>
      'Choisir quelles bibliothèques Audiobookshelf inclure';

  @override
  String get unknownLibrary => 'Bibliothèque inconnue';

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
  String get noSeriesFound => 'Aucune série trouvee';

  @override
  String get ensembleBugReport => 'Rapport de bogue Ensemble';

  @override
  String byOwner(String owner) {
    return 'Par $owner';
  }

  @override
  String get noSeriesAvailable =>
      'Aucune série disponible dans votre bibliothèque de livres audio.\nTirez pour rafraichir.';

  @override
  String get pullToLoadSeries =>
      'Tirez vers le bas pour charger les séries\ndepuis Music Assistant';

  @override
  String get search => 'Rechercher';

  @override
  String get metadataApisDescription =>
      'Les images d\'artistes sont automatiquement recuperees depuis Deezer. Ajoutez les cles API ci-dessous pour les biographies d\'artistes et les descriptions d\'albums.';

  @override
  String get lastFmApiKey => 'Cle API Last.fm';

  @override
  String get lastFmApiKeyHint => 'Obtenez une cle gratuite sur last.fm/api';

  @override
  String get swipeToSwitchDevice => 'Balayez pour changer de lecteur';

  @override
  String chapterNumber(int number) {
    return 'Chapitre $number';
  }

  @override
  String get pcmAudio => 'Audio PCM';

  @override
  String get playOn => 'Lire sur...';

  @override
  String get addAlbumToQueueOn =>
      'Ajouter l\'album a la file d\'attente sur...';

  @override
  String get addToQueueOn => 'Ajouter a la file d\'attente sur...';

  @override
  String startRadioOn(String name) {
    return 'Demarrer la radio $name sur...';
  }

  @override
  String get book => 'livre';

  @override
  String get audiobookSingular => 'livre audio';

  @override
  String get albumSingular => 'Album';

  @override
  String get trackSingular => 'Piste';

  @override
  String get podcastSingular => 'Podcast';

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pistes',
      one: '$count piste',
    );
    return '$_temp0';
  }

  @override
  String get materialYouDescription =>
      'Utiliser les couleurs systeme (Android 12+)';

  @override
  String get accentColor => 'Couleur d\'accentuation';

  @override
  String get players => 'Lecteurs';

  @override
  String get preferLocalPlayer => 'Préférer le lecteur local';

  @override
  String get preferLocalPlayerDescription =>
      'Toujours sélectionner cet appareil en premier si disponible';

  @override
  String get smartSortPlayers => 'Tri intelligent';

  @override
  String get smartSortPlayersDescription =>
      'Trier par statut (en lecture, allume, eteint) au lieu d\'alphabétiquement';

  @override
  String get disableAutoSwitch => 'Disable Auto-Switch';

  @override
  String get disableAutoSwitchDescription =>
      'Never automatically switch to a different player';

  @override
  String get playerStateUnavailable => 'Indisponible';

  @override
  String get playerStateOff => 'Eteint';

  @override
  String get playerStateIdle => 'Inactif';

  @override
  String get playerStateExternalSource => 'Source externe';

  @override
  String get playerSelected => 'Selectionne';

  @override
  String get actionQueuedForSync => 'Sera synchronise une fois en ligne';

  @override
  String pendingOfflineActions(int count) {
    return '$count en attente de synchronisation';
  }

  @override
  String get hintsAndTips => 'Astuces et conseils';

  @override
  String get showHints => 'Afficher les astuces';

  @override
  String get showHintsDescription =>
      'Afficher des conseils utiles pour découvrir les fonctionnalites';

  @override
  String get display => 'Display';

  @override
  String get showProviderIcons => 'Show Provider Icons';

  @override
  String get showProviderIconsDescription =>
      'Display provider logos on album art';

  @override
  String get pullToSelectPlayers => 'Tirez pour sélectionner les lecteurs';

  @override
  String get holdToSync => 'Appui long pour synchroniser';

  @override
  String get swipeToAdjustVolume => 'Balayez pour ajuster le volume';

  @override
  String get selectPlayerHint =>
      'Choisissez un lecteur ou fermez en balayant vers le bas';

  @override
  String get welcomeToEnsemble => 'Bienvenue dans Ensemble';

  @override
  String get welcomeMessage =>
      'Par defaut, votre telephone est le lecteur selectionne.\nTirez le mini-lecteur vers le bas pour sélectionner un autre lecteur.';

  @override
  String get skip => 'Passer';

  @override
  String get dismissPlayerHint =>
      'Balayez vers le bas, touchez a l\'exterieur ou appuyez sur retour pour revenir';

  @override
  String playingAlbum(String albumName) {
    return 'Lecture de $albumName';
  }

  @override
  String playingPlaylist(String playlistName) {
    return 'Lecture de $playlistName';
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
