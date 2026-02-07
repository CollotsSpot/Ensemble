import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../theme/theme_provider.dart';
import '../theme/app_theme.dart';
import '../utils/page_transitions.dart';
import '../providers/navigation_provider.dart';
import '../widgets/global_player_overlay.dart';
import 'debug_log_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _lastFmApiKeyController = TextEditingController();
  final _audioDbApiKeyController = TextEditingController();
  // Main rows (default on)
  bool _showRecentAlbums = true;
  bool _showDiscoverArtists = true;
  bool _showDiscoverAlbums = true;
  // Favorites rows (default off)
  bool _showFavoriteAlbums = false;
  bool _showFavoriteArtists = false;
  bool _showFavoriteTracks = false;
  bool _showFavoritePlaylists = false;
  bool _showFavoriteRadioStations = false;
  bool _showFavoritePodcasts = false;
  // Audiobook home rows (default off)
  bool _showContinueListeningAudiobooks = false;
  bool _showDiscoverAudiobooks = false;
  bool _showDiscoverSeries = false;
  // Home row order
  List<String> _homeRowOrder = List.from(SettingsService.defaultHomeRowOrder);
  // Player settings
  bool _smartSortPlayers = false;
  bool _volumePrecisionMode = true;
  // Hint settings
  bool _showHints = true;
  // Display settings
  bool _showProviderIcons = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final lastFmKey = await SettingsService.getLastFmApiKey();
    if (lastFmKey != null) {
      _lastFmApiKeyController.text = lastFmKey;
    }

    final audioDbKey = await SettingsService.getTheAudioDbApiKey();
    if (audioDbKey != null) {
      _audioDbApiKeyController.text = audioDbKey;
    }

    // Load home screen settings
    final showRecent = await SettingsService.getShowRecentAlbums();
    final showDiscArtists = await SettingsService.getShowDiscoverArtists();
    final showDiscAlbums = await SettingsService.getShowDiscoverAlbums();
    final showFavAlbums = await SettingsService.getShowFavoriteAlbums();
    final showFavArtists = await SettingsService.getShowFavoriteArtists();
    final showFavTracks = await SettingsService.getShowFavoriteTracks();
    final showFavPlaylists = await SettingsService.getShowFavoritePlaylists();
    final showFavRadio = await SettingsService.getShowFavoriteRadioStations();
    final showFavPodcasts = await SettingsService.getShowFavoritePodcasts();

    // Load audiobook home row settings
    final showContinueAudiobooks = await SettingsService.getShowContinueListeningAudiobooks();
    final showDiscAudiobooks = await SettingsService.getShowDiscoverAudiobooks();
    final showDiscSeries = await SettingsService.getShowDiscoverSeries();

    // Load home row order
    final rowOrder = await SettingsService.getHomeRowOrder();

    // Load player settings
    final smartSort = await SettingsService.getSmartSortPlayers();
    final volumePrecision = await SettingsService.getVolumePrecisionMode();

    // Load hint settings
    final showHints = await SettingsService.getShowHints();

    // Load display settings
    final showProviderIcons = await SettingsService.getShowProviderIcons();

    if (mounted) {
      setState(() {
        _showRecentAlbums = showRecent;
        _showDiscoverArtists = showDiscArtists;
        _showDiscoverAlbums = showDiscAlbums;
        _showFavoriteAlbums = showFavAlbums;
        _showFavoriteArtists = showFavArtists;
        _showFavoriteTracks = showFavTracks;
        _showFavoritePlaylists = showFavPlaylists;
        _showFavoriteRadioStations = showFavRadio;
        _showFavoritePodcasts = showFavPodcasts;
        _showContinueListeningAudiobooks = showContinueAudiobooks;
        _showDiscoverAudiobooks = showDiscAudiobooks;
        _showDiscoverSeries = showDiscSeries;
        _homeRowOrder = rowOrder;
        _smartSortPlayers = smartSort;
        _volumePrecisionMode = volumePrecision;
        _showHints = showHints;
        _showProviderIcons = showProviderIcons;
      });
    }
  }

  @override
  void dispose() {
    _lastFmApiKeyController.dispose();
    _audioDbApiKeyController.dispose();
    super.dispose();
  }

  // Helper to get row display info
  Map<String, String> _getRowInfo(String rowId) {
    final s = S.of(context)!;
    switch (rowId) {
      case 'recent-albums':
        return {'title': s.recentlyPlayed, 'subtitle': s.showRecentlyPlayedAlbums};
      case 'discover-artists':
        return {'title': s.discoverArtists, 'subtitle': s.showRandomArtists};
      case 'discover-albums':
        return {'title': s.discoverAlbums, 'subtitle': s.showRandomAlbums};
      case 'continue-listening':
        return {'title': s.continueListening, 'subtitle': s.showAudiobooksInProgress};
      case 'discover-audiobooks':
        return {'title': s.discoverAudiobooks, 'subtitle': s.showRandomAudiobooks};
      case 'discover-series':
        return {'title': s.discoverSeries, 'subtitle': s.showRandomSeries};
      case 'favorite-albums':
        return {'title': s.favoriteAlbums, 'subtitle': s.showFavoriteAlbums};
      case 'favorite-artists':
        return {'title': s.favoriteArtists, 'subtitle': s.showFavoriteArtists};
      case 'favorite-tracks':
        return {'title': s.favoriteTracks, 'subtitle': s.showFavoriteTracks};
      case 'favorite-playlists':
        return {'title': s.favoritePlaylists, 'subtitle': s.showFavoritePlaylists};
      case 'favorite-radio-stations':
        return {'title': s.favoriteRadioStations, 'subtitle': s.showFavoriteRadioStations};
      case 'favorite-podcasts':
        return {'title': s.favoritePodcasts, 'subtitle': s.showFavoritePodcasts};
      default:
        return {'title': rowId, 'subtitle': ''};
    }
  }

  // Helper to get row enabled state
  bool _getRowEnabled(String rowId) {
    switch (rowId) {
      case 'recent-albums':
        return _showRecentAlbums;
      case 'discover-artists':
        return _showDiscoverArtists;
      case 'discover-albums':
        return _showDiscoverAlbums;
      case 'continue-listening':
        return _showContinueListeningAudiobooks;
      case 'discover-audiobooks':
        return _showDiscoverAudiobooks;
      case 'discover-series':
        return _showDiscoverSeries;
      case 'favorite-albums':
        return _showFavoriteAlbums;
      case 'favorite-artists':
        return _showFavoriteArtists;
      case 'favorite-tracks':
        return _showFavoriteTracks;
      case 'favorite-playlists':
        return _showFavoritePlaylists;
      case 'favorite-radio-stations':
        return _showFavoriteRadioStations;
      case 'favorite-podcasts':
        return _showFavoritePodcasts;
      default:
        return false;
    }
  }

  // Helper to set row enabled state
  void _setRowEnabled(String rowId, bool value) {
    setState(() {
      switch (rowId) {
        case 'recent-albums':
          _showRecentAlbums = value;
          SettingsService.setShowRecentAlbums(value);
          break;
        case 'discover-artists':
          _showDiscoverArtists = value;
          SettingsService.setShowDiscoverArtists(value);
          break;
        case 'discover-albums':
          _showDiscoverAlbums = value;
          SettingsService.setShowDiscoverAlbums(value);
          break;
        case 'continue-listening':
          _showContinueListeningAudiobooks = value;
          SettingsService.setShowContinueListeningAudiobooks(value);
          break;
        case 'discover-audiobooks':
          _showDiscoverAudiobooks = value;
          SettingsService.setShowDiscoverAudiobooks(value);
          break;
        case 'discover-series':
          _showDiscoverSeries = value;
          SettingsService.setShowDiscoverSeries(value);
          break;
        case 'favorite-albums':
          _showFavoriteAlbums = value;
          SettingsService.setShowFavoriteAlbums(value);
          break;
        case 'favorite-artists':
          _showFavoriteArtists = value;
          SettingsService.setShowFavoriteArtists(value);
          break;
        case 'favorite-tracks':
          _showFavoriteTracks = value;
          SettingsService.setShowFavoriteTracks(value);
          break;
        case 'favorite-playlists':
          _showFavoritePlaylists = value;
          SettingsService.setShowFavoritePlaylists(value);
          break;
        case 'favorite-radio-stations':
          _showFavoriteRadioStations = value;
          SettingsService.setShowFavoriteRadioStations(value);
          break;
        case 'favorite-podcasts':
          _showFavoritePodcasts = value;
          SettingsService.setShowFavoritePodcasts(value);
          break;
      }
    });
  }

  Future<void> _disconnect() async {
    final provider = context.read<MusicAssistantProvider>();
    await provider.disconnect();

    // Clear saved server URL so login screen shows
    await SettingsService.clearServerUrl();

    if (mounted) {
      // Navigate to login screen and clear the navigation stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use select to only rebuild when connectionState changes
    final connectionState = context.select<MusicAssistantProvider, MAConnectionState>((p) => p.connectionState);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            // Settings is rendered conditionally in HomeScreen (not pushed as a route),
            // so Navigator.pop would pop the entire HomeScreen causing a black screen.
            // Instead, switch tab back to Home and restore the mini player.
            GlobalPlayerOverlay.showPlayer();
            navigationProvider.setSelectedIndex(0);
          },
          color: colorScheme.onBackground,
        ),
        title: Text(
          S.of(context)!.settings,
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_rounded),
            onPressed: () {
              Navigator.push(
                context,
                FadeSlidePageRoute(child: const DebugLogScreen()),
              );
            },
            color: colorScheme.onBackground,
            tooltip: S.of(context)!.debugLogs,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Logo - same size as login screen (50% of screen width)
            // Use color filter to make logo dark in light theme
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 48.0),
              child: Theme.of(context).brightness == Brightness.light
                  ? ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF1a1a1a), // Dark color for light theme
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        'assets/images/ensemble_icon_transparent.png',
                        width: MediaQuery.of(context).size.width * 0.5,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Image.asset(
                      'assets/images/ensemble_icon_transparent.png',
                      width: MediaQuery.of(context).size.width * 0.5,
                      fit: BoxFit.contain,
                    ),
            ),

            // Connection status box - centered with border radius like theme boxes
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getStatusIcon(connectionState),
                    color: _getStatusColor(connectionState, colorScheme),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getStatusText(connectionState),
                    style: textTheme.titleMedium?.copyWith(
                      color: _getStatusColor(connectionState, colorScheme),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Disconnect button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.tonalIcon(
                onPressed: _disconnect,
                icon: const Icon(Icons.logout_rounded),
                label: Text(
                  S.of(context)!.disconnect,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer.withOpacity(0.4),
                  foregroundColor: colorScheme.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Theme section
            Text(
              S.of(context)!.theme,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context)!.themeMode,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, _) {
                      return SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          segments: [
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.light,
                              label: Text(S.of(context)!.light),
                              icon: const Icon(Icons.light_mode_rounded),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.dark,
                              label: Text(S.of(context)!.dark),
                              icon: const Icon(Icons.dark_mode_rounded),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.system,
                              label: Text(S.of(context)!.system),
                              icon: const Icon(Icons.auto_mode_rounded),
                            ),
                          ],
                          selected: {themeProvider.themeMode},
                          onSelectionChanged: (Set<ThemeMode> newSelection) {
                            themeProvider.setThemeMode(newSelection.first);
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return colorScheme.primaryContainer;
                              }
                              return colorScheme.surfaceVariant.withOpacity(0.5);
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return colorScheme.onPrimaryContainer;
                              }
                              return colorScheme.onSurfaceVariant;
                            }),
                            side: WidgetStateProperty.all(BorderSide.none),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Accent color picker
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                final isDisabled = themeProvider.useMaterialTheme;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.of(context)!.accentColor,
                        style: TextStyle(
                          color: isDisabled
                              ? colorScheme.onSurface.withOpacity(0.4)
                              : colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: accentColorOptions.map((color) {
                          final isSelected = themeProvider.customColor.value == color.value;
                          return GestureDetector(
                            onTap: isDisabled ? null : () {
                              themeProvider.setCustomColor(color);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isDisabled ? color.withOpacity(0.3) : color,
                                shape: BoxShape.circle,
                                border: isSelected && !isDisabled
                                    ? Border.all(color: colorScheme.onSurface, width: 3)
                                    : null,
                                boxShadow: isSelected && !isDisabled
                                    ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)]
                                    : null,
                              ),
                              child: isSelected && !isDisabled
                                  ? Icon(Icons.check, color: Colors.white, size: 20)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    title: Text(
                      S.of(context)!.materialYou,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      S.of(context)!.materialYouDescription,
                      style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                    ),
                    value: themeProvider.useMaterialTheme,
                    onChanged: (value) {
                      themeProvider.setUseMaterialTheme(value);
                    },
                    activeColor: colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    title: Text(
                      S.of(context)!.adaptiveTheme,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      S.of(context)!.extractColorsFromArtwork,
                      style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                    ),
                    value: themeProvider.adaptiveTheme,
                    onChanged: (value) {
                      themeProvider.setAdaptiveTheme(value);
                    },
                    activeColor: colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Language section
            Text(
              S.of(context)!.language,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            Consumer<LocaleProvider>(
              builder: (context, localeProvider, _) {
                String getLanguageName(String? code) {
                  switch (code) {
                    case 'en':
                      return 'English';
                    case 'de':
                      return 'Deutsch';
                    case 'es':
                      return 'Español';
                    default:
                      return S.of(context)!.system;
                  }
                }

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  tileColor: colorScheme.surfaceVariant.withOpacity(0.5),
                  leading: Icon(Icons.language_rounded, color: colorScheme.onSurfaceVariant),
                  title: Text(S.of(context)!.language),
                  subtitle: Text(
                    getLanguageName(localeProvider.locale?.languageCode),
                    style: TextStyle(color: colorScheme.primary),
                  ),
                  trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (dialogContext) {
                        return AlertDialog(
                          title: Text(S.of(context)!.language),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RadioListTile<String?>(
                                title: Text(S.of(context)!.system),
                                subtitle: Text(S.of(context)!.auto),
                                value: null,
                                groupValue: localeProvider.locale?.languageCode,
                                onChanged: (value) {
                                  localeProvider.setLocale(null);
                                  Navigator.pop(dialogContext);
                                },
                              ),
                              RadioListTile<String?>(
                                title: Text(S.of(context)!.english),
                                value: 'en',
                                groupValue: localeProvider.locale?.languageCode,
                                onChanged: (value) {
                                  localeProvider.setLocale(const Locale('en'));
                                  Navigator.pop(dialogContext);
                                },
                              ),
                              RadioListTile<String?>(
                                title: Text(S.of(context)!.german),
                                value: 'de',
                                groupValue: localeProvider.locale?.languageCode,
                                onChanged: (value) {
                                  localeProvider.setLocale(const Locale('de'));
                                  Navigator.pop(dialogContext);
                                },
                              ),
                              RadioListTile<String?>(
                                title: Text(S.of(context)!.spanish),
                                value: 'es',
                                groupValue: localeProvider.locale?.languageCode,
                                onChanged: (value) {
                                  localeProvider.setLocale(const Locale('es'));
                                  Navigator.pop(dialogContext);
                                },
                              ),
                              RadioListTile<String?>(
                                title: Text(S.of(context)!.french),
                                value: 'fr',
                                groupValue: localeProvider.locale?.languageCode,
                                onChanged: (value) {
                                  localeProvider.setLocale(const Locale('fr'));
                                  Navigator.pop(dialogContext);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 32),

            // Player section
            Text(
              S.of(context)!.players,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: Text(
                  S.of(context)!.smartSortPlayers,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                subtitle: Text(
                  S.of(context)!.smartSortPlayersDescription,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                ),
                value: _smartSortPlayers,
                onChanged: (value) {
                  setState(() => _smartSortPlayers = value);
                  SettingsService.setSmartSortPlayers(value);
                },
                activeColor: colorScheme.primary,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: Text(
                  S.of(context)!.volumePrecisionMode,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                subtitle: Text(
                  S.of(context)!.volumePrecisionModeDescription,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                ),
                value: _volumePrecisionMode,
                onChanged: (value) {
                  setState(() => _volumePrecisionMode = value);
                  SettingsService.setVolumePrecisionMode(value);
                },
                activeColor: colorScheme.primary,
                contentPadding: EdgeInsets.zero,
              ),
            ),

            const SizedBox(height: 32),

            // Hints & Tips section
            Text(
              S.of(context)!.hintsAndTips,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context)!.showHintsDescription,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onBackground.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: Text(
                  S.of(context)!.showHints,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                value: _showHints,
                onChanged: (value) {
                  setState(() => _showHints = value);
                  SettingsService.setShowHints(value);
                },
                activeColor: colorScheme.primary,
                contentPadding: EdgeInsets.zero,
              ),
            ),

            const SizedBox(height: 24),

            // Display section
            Text(
              S.of(context)!.display,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: Text(
                  S.of(context)!.showProviderIcons,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                subtitle: Text(
                  S.of(context)!.showProviderIconsDescription,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                value: _showProviderIcons,
                onChanged: (value) {
                  setState(() => _showProviderIcons = value);
                  SettingsService.setShowProviderIcons(value);
                },
                activeColor: colorScheme.primary,
                contentPadding: EdgeInsets.zero,
              ),
            ),

            const SizedBox(height: 32),

            // Home Screen section
            Text(
              S.of(context)!.homeScreen,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context)!.chooseHomeScreenRows,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onBackground.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),

            // Reorderable home rows list
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _homeRowOrder.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _homeRowOrder.removeAt(oldIndex);
                    _homeRowOrder.insert(newIndex, item);
                  });
                  SettingsService.setHomeRowOrder(_homeRowOrder);
                },
                itemBuilder: (context, index) {
                  final rowId = _homeRowOrder[index];
                  final rowInfo = _getRowInfo(rowId);
                  final isEnabled = _getRowEnabled(rowId);

                  return Container(
                    key: ValueKey(rowId),
                    decoration: BoxDecoration(
                      border: index < _homeRowOrder.length - 1
                          ? Border(bottom: BorderSide(color: colorScheme.outline.withOpacity(0.2)))
                          : null,
                    ),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            child: Icon(
                              Icons.drag_handle,
                              color: colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            title: Text(
                              rowInfo['title']!,
                              style: TextStyle(color: colorScheme.onSurface),
                            ),
                            subtitle: Text(
                              rowInfo['subtitle']!,
                              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                            ),
                            value: isEnabled,
                            onChanged: (value) => _setRowEnabled(rowId, value),
                            activeColor: colorScheme.primary,
                            contentPadding: const EdgeInsets.only(right: 8),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 32),

            Text(
              S.of(context)!.metadataApis,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context)!.metadataApisDescription,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onBackground.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _lastFmApiKeyController,
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: S.of(context)!.lastFmApiKey,
                hintText: S.of(context)!.lastFmApiKeyHint,
                hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(
                  Icons.music_note_rounded,
                  color: colorScheme.onSurface.withOpacity(0.54),
                ),
                suffixIcon: _lastFmApiKeyController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _lastFmApiKeyController.clear();
                          });
                          SettingsService.setLastFmApiKey(null);
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                SettingsService.setLastFmApiKey(value.trim().isEmpty ? null : value.trim());
                setState(() {}); // Update UI to show/hide clear button
              },
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _audioDbApiKeyController,
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: S.of(context)!.theAudioDbApiKey,
                hintText: S.of(context)!.theAudioDbApiKeyHint,
                hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(
                  Icons.audiotrack_rounded,
                  color: colorScheme.onSurface.withOpacity(0.54),
                ),
                suffixIcon: _audioDbApiKeyController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _audioDbApiKeyController.clear();
                          });
                          SettingsService.setTheAudioDbApiKey(null);
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                SettingsService.setTheAudioDbApiKey(value.trim().isEmpty ? null : value.trim());
                setState(() {}); // Update UI to show/hide clear button
              },
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DebugLogScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.bug_report_rounded),
                label: Text(S.of(context)!.viewDebugLogs),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.surfaceVariant.withOpacity(0.5),
                  foregroundColor: colorScheme.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            SizedBox(height: BottomSpacing.navBarOnly), // Space for bottom nav bar
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(MAConnectionState state) {
    switch (state) {
      case MAConnectionState.connected:
      case MAConnectionState.authenticated:
        return Icons.check_circle_rounded;
      case MAConnectionState.connecting:
      case MAConnectionState.authenticating:
        return Icons.sync_rounded;
      case MAConnectionState.error:
        return Icons.error_rounded;
      case MAConnectionState.disconnected:
        return Icons.cloud_off_rounded;
    }
  }

  Color _getStatusColor(MAConnectionState state, ColorScheme colorScheme) {
    switch (state) {
      case MAConnectionState.connected:
      case MAConnectionState.authenticated:
        return Colors.green;
      case MAConnectionState.connecting:
      case MAConnectionState.authenticating:
        return Colors.orange;
      case MAConnectionState.error:
        return colorScheme.error;
      case MAConnectionState.disconnected:
        return colorScheme.onSurface.withOpacity(0.5);
    }
  }

  String _getStatusText(MAConnectionState state) {
    final s = S.of(context)!;
    switch (state) {
      case MAConnectionState.connected:
      case MAConnectionState.authenticated:
        return s.connected;
      case MAConnectionState.connecting:
      case MAConnectionState.authenticating:
        return s.connecting;
      case MAConnectionState.error:
        return s.connectionError;
      case MAConnectionState.disconnected:
        return s.disconnected;
    }
  }

}
