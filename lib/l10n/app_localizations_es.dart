// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class SEs extends S {
  SEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Ensemble';

  @override
  String get connecting => 'Conectando...';

  @override
  String get connected => 'Conectado';

  @override
  String get disconnected => 'Desconectado';

  @override
  String get serverAddress => 'Dirección del servidor';

  @override
  String get serverAddressHint => 'ej., music.example.com o 192.168.1.100';

  @override
  String get yourName => 'Tu nombre';

  @override
  String get yourFirstName => 'Tu nombre de pila';

  @override
  String get portOptional => 'Puerto (Opcional)';

  @override
  String get portHint => 'ej., 8095 o dejar en blanco';

  @override
  String get portDescription =>
      'Dejar en blanco para proxy inverso o puertos estándar. Introduce 8095 para conexión directa.';

  @override
  String get username => 'Usuario';

  @override
  String get password => 'Contraseña';

  @override
  String get detectAndConnect => 'Detectar y conectar';

  @override
  String get connect => 'Conectar';

  @override
  String get disconnect => 'Desconectar';

  @override
  String get authServerUrlOptional =>
      'URL del servidor de autenticación (Opcional)';

  @override
  String get authServerUrlHint =>
      'ej., auth.example.com (si es diferente del servidor)';

  @override
  String get authServerUrlDescription =>
      'Dejar vacío si la autenticación está en el mismo servidor';

  @override
  String detectedAuthType(String authType) {
    return 'Detectado: $authType';
  }

  @override
  String get serverRequiresAuth => 'Este servidor requiere autenticación';

  @override
  String get tailscaleVpnConnection => 'Conexión VPN Tailscale';

  @override
  String get unencryptedConnection => 'Conexión sin cifrar';

  @override
  String get usingHttpOverTailscale =>
      'Usando HTTP sobre Tailscale (túnel cifrado)';

  @override
  String get httpsFailedUsingHttp =>
      'HTTPS falló, usando HTTP como alternativa';

  @override
  String get httpNotEncrypted => 'Conexión HTTP - los datos no están cifrados';

  @override
  String get pleaseEnterServerAddress =>
      'Por favor, introduce la dirección de tu servidor Music Assistant';

  @override
  String get pleaseEnterName => 'Por favor, introduce tu nombre';

  @override
  String get pleaseEnterValidPort =>
      'Por favor, introduce un número de puerto válido (1-65535)';

  @override
  String get pleaseEnterCredentials =>
      'Por favor, introduce usuario y contraseña';

  @override
  String get authFailed =>
      'Autenticación fallida. Por favor, verifica tus credenciales.';

  @override
  String get maLoginFailed =>
      'Inicio de sesión en Music Assistant fallido. Por favor, verifica tus credenciales.';

  @override
  String get connectionFailed =>
      'No se pudo conectar al servidor. Por favor, verifica la dirección e inténtalo de nuevo.';

  @override
  String get detectingAuth => 'Detectando autenticación...';

  @override
  String get cannotDetermineAuth =>
      'No se pueden determinar los requisitos de autenticación. Por favor, verifica la URL del servidor.';

  @override
  String get noAuthentication => 'Sin autenticación';

  @override
  String get httpBasicAuth => 'Autenticación HTTP Basic';

  @override
  String get authelia => 'Authelia';

  @override
  String get musicAssistantLogin => 'Inicio de sesión de Music Assistant';

  @override
  String get pressBackToMinimize => 'Presiona atrás de nuevo para minimizar';

  @override
  String get recentlyPlayed => 'Reproducido recientemente';

  @override
  String get discoverArtists => 'Descubrir artistas';

  @override
  String get discoverAlbums => 'Descubrir álbumes';

  @override
  String get continueListening => 'Continuar escuchando';

  @override
  String get discoverAudiobooks => 'Descubrir audiolibros';

  @override
  String get discoverSeries => 'Descubrir series';

  @override
  String get favoriteAlbums => 'Álbumes favoritos';

  @override
  String get favoriteArtists => 'Artistas favoritos';

  @override
  String get favoriteTracks => 'Canciones favoritas';

  @override
  String get favoritePlaylists => 'Favorite Playlists';

  @override
  String get favoriteRadioStations => 'Favorite Radio Stations';

  @override
  String get favoritePodcasts => 'Favorite Podcasts';

  @override
  String get searchMusic => 'Buscar música...';

  @override
  String get searchForContent => 'Buscar artistas, álbumes o canciones';

  @override
  String get recentSearches => 'Recent Searches';

  @override
  String get clearSearchHistory => 'Clear Search History';

  @override
  String get searchHistoryCleared => 'Search history cleared';

  @override
  String get libraryOnly => 'Library only';

  @override
  String get retry => 'Reintentar';

  @override
  String get all => 'Todo';

  @override
  String get artists => 'Artistas';

  @override
  String get albums => 'Álbumes';

  @override
  String get tracks => 'Canciones';

  @override
  String get playlists => 'Listas de reproducción';

  @override
  String get audiobooks => 'Audiolibros';

  @override
  String get music => 'Música';

  @override
  String get radio => 'Radio';

  @override
  String get stations => 'Emisoras';

  @override
  String get selectLibrary => 'Seleccionar Biblioteca';

  @override
  String get noRadioStations => 'No hay emisoras de radio';

  @override
  String get addRadioStationsHint =>
      'Añade emisoras de radio en Music Assistant';

  @override
  String get searchFailed =>
      'Búsqueda fallida. Por favor, verifica tu conexión.';

  @override
  String get queue => 'Cola';

  @override
  String playerQueue(String playerName) {
    return 'Cola de $playerName';
  }

  @override
  String get noPlayerSelected => 'Ningún reproductor seleccionado';

  @override
  String get undo => 'Deshacer';

  @override
  String removedItem(String itemName) {
    return 'Eliminado $itemName';
  }

  @override
  String get settings => 'Ajustes';

  @override
  String get debugLogs => 'Registros de depuración';

  @override
  String get themeMode => 'Modo de tema';

  @override
  String get light => 'Claro';

  @override
  String get dark => 'Oscuro';

  @override
  String get system => 'Sistema';

  @override
  String get pullToRefresh =>
      'Desliza hacia abajo para actualizar la biblioteca y aplicar los cambios';

  @override
  String get viewDebugLogs => 'Ver registros de depuración';

  @override
  String get viewAllPlayers => 'Ver todos los reproductores';

  @override
  String get copyLogs => 'Copiar registros';

  @override
  String get clearLogs => 'Borrar registros';

  @override
  String get copyList => 'Copiar lista';

  @override
  String get close => 'Cerrar';

  @override
  String allPlayersCount(int count) {
    return 'Todos los reproductores ($count)';
  }

  @override
  String errorLoadingPlayers(String error) {
    return 'Error al cargar reproductores: $error';
  }

  @override
  String get logsCopied => 'Registros copiados al portapapeles';

  @override
  String get logsCleared => 'Registros borrados';

  @override
  String get playerListCopied =>
      'Lista de reproductores copiada al portapapeles';

  @override
  String get noLogsYet => 'Aún no hay registros';

  @override
  String get infoPlus => 'Info+';

  @override
  String get warnings => 'Advertencias';

  @override
  String get errors => 'Errores';

  @override
  String showingEntries(int filtered, int total) {
    return 'Mostrando $filtered de $total entradas';
  }

  @override
  String get thisDevice => 'Este dispositivo';

  @override
  String get ghostPlayer => 'Reproductor fantasma (duplicado)';

  @override
  String get unavailableCorrupt => 'No disponible/Corrupto';

  @override
  String playerId(String id) {
    return 'ID: $id';
  }

  @override
  String playerInfo(String available, String provider) {
    return 'Disponible: $available | Proveedor: $provider';
  }

  @override
  String get shareBugReport => 'Compartir informe de errores';

  @override
  String get moreOptions => 'Más opciones';

  @override
  String failedToUpdateFavorite(String error) {
    return 'Error al actualizar favorito: $error';
  }

  @override
  String get noPlayersAvailable => 'No hay reproductores disponibles';

  @override
  String get albumAddedToQueue => 'Álbum añadido a la cola';

  @override
  String get tracksAddedToQueue => 'Canciones añadidas a la cola';

  @override
  String get play => 'Reproducir';

  @override
  String get noPlayersFound => 'No se encontraron reproductores';

  @override
  String startingRadio(String name) {
    return 'Iniciando radio de $name';
  }

  @override
  String failedToStartRadio(String error) {
    return 'Error al iniciar radio: $error';
  }

  @override
  String startingRadioOnPlayer(String name, String playerName) {
    return 'Iniciando radio de $name en $playerName';
  }

  @override
  String addedRadioToQueue(String name) {
    return 'Radio de $name añadida a la cola';
  }

  @override
  String failedToAddToQueue(String error) {
    return 'Error al añadir a la cola: $error';
  }

  @override
  String playingRadioStation(String name) {
    return 'Playing $name';
  }

  @override
  String get addedToQueue => 'Added to queue';

  @override
  String get inLibrary => 'En la biblioteca';

  @override
  String get noAlbumsFound => 'No se encontraron álbumes';

  @override
  String playing(String name) {
    return 'Reproduciendo $name';
  }

  @override
  String get playingTrack => 'Reproduciendo canción';

  @override
  String get nowPlaying => 'Reproduciendo ahora';

  @override
  String markedAsFinished(String name) {
    return '$name marcado como terminado';
  }

  @override
  String failedToMarkFinished(String error) {
    return 'Error al marcar como terminado: $error';
  }

  @override
  String markedAsUnplayed(String name) {
    return '$name marcado como no reproducido';
  }

  @override
  String failedToMarkUnplayed(String error) {
    return 'Error al marcar como no reproducido: $error';
  }

  @override
  String failedToPlay(String error) {
    return 'Error al reproducir: $error';
  }

  @override
  String get markAsFinished => 'Marcar como terminado';

  @override
  String get markAsUnplayed => 'Marcar como no reproducido';

  @override
  String byAuthor(String author) {
    return 'Por $author';
  }

  @override
  String audiobookCount(int count) {
    return '$count audiolibro(s)';
  }

  @override
  String get loading => 'Cargando...';

  @override
  String bookCount(int count) {
    return '$count libro(s)';
  }

  @override
  String get books => 'Libros';

  @override
  String get noFavoriteAudiobooks => 'No hay audiolibros favoritos';

  @override
  String get tapHeartAudiobook =>
      'Toca el corazón en un audiolibro para añadirlo a favoritos';

  @override
  String get noAudiobooks => 'No hay audiolibros';

  @override
  String get addAudiobooksHint =>
      'Añade audiolibros a tu biblioteca para verlos aquí';

  @override
  String get noFavoriteArtists => 'No hay artistas favoritos';

  @override
  String get tapHeartArtist =>
      'Toca el corazón en un artista para añadirlo a favoritos';

  @override
  String get noFavoriteAlbums => 'No hay álbumes favoritos';

  @override
  String get tapHeartAlbum =>
      'Toca el corazón en un álbum para añadirlo a favoritos';

  @override
  String get noFavoritePlaylists => 'No hay listas de reproducción favoritas';

  @override
  String get tapHeartPlaylist =>
      'Toca el corazón en una lista para añadirla a favoritos';

  @override
  String get noFavoriteTracks => 'No hay canciones favoritas';

  @override
  String get longPressTrackHint =>
      'Mantén presionada una canción y toca el corazón para añadirla a favoritos';

  @override
  String get loadSeries => 'Cargar series';

  @override
  String get notConnected => 'No conectado a Music Assistant';

  @override
  String get notConnectedTitle => 'No conectado';

  @override
  String get connectHint =>
      'Conéctate a tu servidor Music Assistant para empezar a escuchar';

  @override
  String get configureServer => 'Configurar servidor';

  @override
  String get noArtistsFound => 'No se encontraron artistas';

  @override
  String get noTracksFound => 'No se encontraron canciones';

  @override
  String get noPlaylistsFound => 'No se encontraron listas de reproducción';

  @override
  String get queueIsEmpty => 'La cola está vacía';

  @override
  String get noResultsFound => 'No se encontraron resultados';

  @override
  String get refresh => 'Actualizar';

  @override
  String get debugConsole => 'Consola de depuración';

  @override
  String get copy => 'Copiar';

  @override
  String get clear => 'Borrar';

  @override
  String get noLogsToCopy => 'No hay registros para copiar';

  @override
  String get noDebugLogsYet =>
      'Aún no hay registros de depuración. Intenta detectar autenticación.';

  @override
  String get showDebug => 'Mostrar depuración';

  @override
  String get hideDebug => 'Ocultar depuración';

  @override
  String get chapters => 'Capítulos';

  @override
  String get noChapters => 'Sin capítulos';

  @override
  String get noChapterInfo =>
      'Este audiolibro no tiene información de capítulos';

  @override
  String errorSeeking(String error) {
    return 'Error al buscar: $error';
  }

  @override
  String error(String error) {
    return 'Error: $error';
  }

  @override
  String get home => 'Inicio';

  @override
  String get library => 'Biblioteca';

  @override
  String get homeScreen => 'Pantalla de inicio';

  @override
  String get metadataApis => 'APIs de metadatos';

  @override
  String get theme => 'Tema';

  @override
  String get materialYou => 'Material You';

  @override
  String get adaptiveTheme => 'Tema adaptativo';

  @override
  String get language => 'Idioma';

  @override
  String get english => 'Inglés';

  @override
  String get german => 'Alemán';

  @override
  String get spanish => 'Español';

  @override
  String get french => 'Francés';

  @override
  String get noTracksInPlaylist => 'No hay canciones en la lista';

  @override
  String get sortAlphabetically => 'Ordenar alfabéticamente';

  @override
  String get sortByYear => 'Ordenar por año';

  @override
  String get sortBySeriesOrder => 'Ordenar por orden de serie';

  @override
  String get listView => 'Vista de lista';

  @override
  String get gridView => 'Vista de cuadrícula';

  @override
  String get noBooksInSeries => 'No se encontraron libros en esta serie';

  @override
  String get artist => 'Artista';

  @override
  String get showRecentlyPlayedAlbums =>
      'Mostrar álbumes reproducidos recientemente';

  @override
  String get showRandomArtists => 'Mostrar artistas aleatorios para descubrir';

  @override
  String get showRandomAlbums => 'Mostrar álbumes aleatorios para descubrir';

  @override
  String get showAudiobooksInProgress => 'Mostrar audiolibros en progreso';

  @override
  String get showRandomAudiobooks =>
      'Mostrar audiolibros aleatorios para descubrir';

  @override
  String get showRandomSeries =>
      'Mostrar series de audiolibros aleatorias para descubrir';

  @override
  String get showFavoriteAlbums => 'Mostrar una fila de tus álbumes favoritos';

  @override
  String get showFavoriteArtists =>
      'Mostrar una fila de tus artistas favoritos';

  @override
  String get showFavoriteTracks =>
      'Mostrar una fila de tus canciones favoritas';

  @override
  String get showFavoritePlaylists => 'Show a row of your favorite playlists';

  @override
  String get showFavoriteRadioStations =>
      'Show a row of your favorite radio stations';

  @override
  String get showFavoritePodcasts => 'Show a row of your favorite podcasts';

  @override
  String get extractColorsFromArtwork =>
      'Extraer colores de las portadas de álbumes y artistas';

  @override
  String get chooseHomeScreenRows =>
      'Elige qué filas mostrar en la pantalla de inicio';

  @override
  String get addedToFavorites => 'Añadido a favoritos';

  @override
  String get removedFromFavorites => 'Eliminado de favoritos';

  @override
  String get addedToLibrary => 'Added to library';

  @override
  String get removedFromLibrary => 'Removed from library';

  @override
  String get addToLibrary => 'Add to library';

  @override
  String get unknown => 'Desconocido';

  @override
  String get noUpcomingTracks => 'No hay canciones próximas';

  @override
  String get showAll => 'Mostrar todo';

  @override
  String get showFavoritesOnly => 'Mostrar solo favoritos';

  @override
  String get changeView => 'Cambiar vista';

  @override
  String get authors => 'Autores';

  @override
  String get series => 'Series';

  @override
  String get shows => 'Programas';

  @override
  String get podcasts => 'Podcasts';

  @override
  String get podcastSupportComingSoon => 'Soporte de podcasts próximamente';

  @override
  String get noPodcasts => 'No podcasts';

  @override
  String get addPodcastsHint => 'Subscribe to podcasts in Music Assistant';

  @override
  String get episodes => 'Episodes';

  @override
  String get episode => 'Episode';

  @override
  String get playlist => 'Lista de reproducción';

  @override
  String get connectionError => 'Error de conexión';

  @override
  String get twoColumnGrid => 'Cuadrícula de 2 columnas';

  @override
  String get threeColumnGrid => 'Cuadrícula de 3 columnas';

  @override
  String get fromProviders => 'De proveedores';

  @override
  String get resume => 'Continuar';

  @override
  String get about => 'Acerca de';

  @override
  String get inProgress => 'En progreso';

  @override
  String narratedBy(String narrators) {
    return 'Narrado por $narrators';
  }

  @override
  String get unknownNarrator => 'Narrador desconocido';

  @override
  String get unknownAuthor => 'Autor desconocido';

  @override
  String get loadingChapters => 'Cargando capítulos...';

  @override
  String get noChapterInfoAvailable =>
      'No hay información de capítulos disponible';

  @override
  String percentComplete(int percent) {
    return '$percent% completado';
  }

  @override
  String get theAudioDbApiKey => 'Clave API de TheAudioDB';

  @override
  String get theAudioDbApiKeyHint =>
      'Usa \"2\" para nivel gratuito o clave premium';

  @override
  String get audiobookLibraries => 'Bibliotecas de audiolibros';

  @override
  String get chooseAudiobookLibraries =>
      'Elige qué bibliotecas de Audiobookshelf incluir';

  @override
  String get unknownLibrary => 'Biblioteca desconocida';

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
  String get noSeriesFound => 'No se encontraron series';

  @override
  String get ensembleBugReport => 'Informe de errores de Ensemble';

  @override
  String byOwner(String owner) {
    return 'Por $owner';
  }

  @override
  String get noSeriesAvailable =>
      'No hay series disponibles en tu biblioteca de audiolibros.\nDesliza para actualizar.';

  @override
  String get pullToLoadSeries =>
      'Desliza hacia abajo para cargar series\ndesde Music Assistant';

  @override
  String get search => 'Buscar';

  @override
  String get metadataApisDescription =>
      'Las imágenes de artistas se obtienen automáticamente de Deezer. Añade claves API a continuación para biografías de artistas y descripciones de álbumes.';

  @override
  String get lastFmApiKey => 'Clave API de Last.fm';

  @override
  String get lastFmApiKeyHint => 'Obtén una clave gratuita en last.fm/api';

  @override
  String get swipeToSwitchDevice => 'Desliza para cambiar dispositivo';

  @override
  String chapterNumber(int number) {
    return 'Capítulo $number';
  }

  @override
  String get pcmAudio => 'Audio PCM';

  @override
  String get playOn => 'Reproducir en...';

  @override
  String get addAlbumToQueueOn => 'Añadir álbum a la cola en...';

  @override
  String get addToQueueOn => 'Añadir a la cola en...';

  @override
  String startRadioOn(String name) {
    return 'Iniciar radio de $name en...';
  }

  @override
  String get book => 'libro';

  @override
  String get audiobookSingular => 'audiolibro';

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
      other: 'canciones',
      one: 'canción',
    );
    return '$count $_temp0';
  }

  @override
  String get materialYouDescription => 'Usar colores del sistema (Android 12+)';

  @override
  String get accentColor => 'Color de acento';

  @override
  String get players => 'Dispositivos';

  @override
  String get preferLocalPlayer => 'Preferir dispositivo local';

  @override
  String get preferLocalPlayerDescription =>
      'Seleccionar siempre este dispositivo primero cuando esté disponible';

  @override
  String get smartSortPlayers => 'Orden inteligente';

  @override
  String get smartSortPlayersDescription =>
      'Ordenar por estado (reproduciendo, encendido, apagado) en lugar de alfabéticamente';

  @override
  String get disableAutoSwitch => 'Disable Auto-Switch';

  @override
  String get disableAutoSwitchDescription =>
      'Never automatically switch to a different player';

  @override
  String get playerStateUnavailable => 'No disponible';

  @override
  String get playerStateOff => 'Apagado';

  @override
  String get playerStateIdle => 'Inactivo';

  @override
  String get playerStateExternalSource => 'Fuente Externa';

  @override
  String get playerSelected => 'Seleccionado';

  @override
  String get actionQueuedForSync => 'Se sincronizará cuando esté en línea';

  @override
  String pendingOfflineActions(int count) {
    return '$count sincronización pendiente';
  }

  @override
  String get hintsAndTips => 'Consejos y Sugerencias';

  @override
  String get showHints => 'Mostrar Sugerencias';

  @override
  String get showHintsDescription =>
      'Mostrar consejos útiles para descubrir funciones';

  @override
  String get display => 'Display';

  @override
  String get showProviderIcons => 'Show Provider Icons';

  @override
  String get showProviderIconsDescription =>
      'Display provider logos on album art';

  @override
  String get pullToSelectPlayers => 'Desliza para seleccionar dispositivos';

  @override
  String get holdToSync => 'Mantén presionado para sync';

  @override
  String get swipeToAdjustVolume => 'Desliza para ajustar volumen';

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
