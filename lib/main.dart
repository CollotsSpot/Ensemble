import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';
import 'providers/music_assistant_provider.dart';
import 'providers/navigation_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/settings_service.dart';
import 'services/database_service.dart';
import 'services/profile_service.dart';
import 'services/sync_service.dart';
import 'services/audio/massiv_audio_handler.dart';
import 'services/auth/auth_manager.dart';
import 'services/debug_logger.dart';
import 'services/hardware_volume_service.dart';
import 'services/music_assistant_api.dart' show MAConnectionState;
import 'theme/theme_provider.dart';
import 'theme/app_theme.dart';
import 'theme/system_theme_helper.dart';
import 'widgets/global_player_overlay.dart';

// Global audio handler instance
late MassivAudioHandler audioHandler;

// Global debug logger instance
final _logger = DebugLogger();

void main() {
  // All initialization must run inside the same zone as runApp() to avoid
  // "Zone mismatch" errors from Flutter's binding system
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize SharedPreferences cache early for performance
      await SettingsService.initialize();
      _logger.log('⚡ SharedPreferences cached');

      // Initialize local database
      await DatabaseService.instance.initialize();
      _logger.log('💾 Database initialized');

      // Migrate existing ownerName to profile (one-time for existing users)
      await ProfileService.instance.migrateFromOwnerName();

      // Migrate credentials to secure storage (one-time for existing users)
      await SettingsService.migrateToSecureStorage();
      _logger.log('🔐 Secure storage migration complete');

      // Load library from cache for instant startup
      await SyncService.instance.loadFromCache();
      _logger.log('📦 Library cache loaded');

      // Create auth manager for streaming headers
      final authManager = AuthManager();

      // Initialize audio_service with our custom handler
      audioHandler = await AudioService.init(
        builder: () => MassivAudioHandler(authManager: authManager),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'io.github.collotsspot.massiv.audio',
          androidNotificationChannelName: 'Ensemble Audio',
          androidNotificationOngoing: false,  // Must be false when androidStopForegroundOnPause is false
          androidNotificationIcon: 'drawable/ic_notification',
          androidShowNotificationBadge: false,
          androidStopForegroundOnPause: false,  // Keep service alive when paused for background playback
        ),
      );
      _logger.log('🎵 AudioService initialized - background playback and media notifications ENABLED');

      // Set preferred orientations
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // Set initial system UI overlay style based on platform brightness
      // SystemUIWrapper will update this dynamically when theme changes
      final platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      final isDark = platformBrightness == Brightness.dark;
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: isDark ? const Color(0xFF1a1a1a) : const Color(0xFFF5F5F5),
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
      );

      // Set up Flutter error boundary to catch and log widget build errors
      FlutterError.onError = (FlutterErrorDetails details) {
        _logger.error('Flutter error: ${details.exceptionAsString()}', context: 'FlutterError');
        _logger.error('Stack trace:\n${details.stack}', context: 'FlutterError');
        // Still report to Flutter's default handler in debug mode
        FlutterError.presentError(details);
      };

      // Catch errors from the platform dispatcher (platform channel errors)
      PlatformDispatcher.instance.onError = (error, stack) {
        _logger.error('Platform error: $error', context: 'PlatformDispatcher');
        _logger.error('Stack trace:\n$stack', context: 'PlatformDispatcher');
        return true; // Handled
      };

      runApp(const MusicAssistantApp());
    },
    (error, stackTrace) {
      _logger.error('Uncaught async error: $error', context: 'ZoneError');
      _logger.error('Stack trace:\n$stackTrace', context: 'ZoneError');
    },
  );
}

class MusicAssistantApp extends StatefulWidget {
  const MusicAssistantApp({super.key});

  @override
  State<MusicAssistantApp> createState() => _MusicAssistantAppState();
}

class _MusicAssistantAppState extends State<MusicAssistantApp> with WidgetsBindingObserver {
  late MusicAssistantProvider _musicProvider;
  late ThemeProvider _themeProvider;
  late LocaleProvider _localeProvider;
  final _hardwareVolumeService = HardwareVolumeService();
  StreamSubscription? _volumeUpSub;
  StreamSubscription? _volumeDownSub;
  StreamSubscription? _absoluteVolumeSub;
  String? _lastSelectedPlayerId;
  String? _builtinPlayerId;

  // Volume step size (percentage points per button press)
  static const int _volumeStep = 5;

  @override
  void initState() {
    super.initState();
    _musicProvider = MusicAssistantProvider();
    _themeProvider = ThemeProvider();
    _localeProvider = LocaleProvider();
    WidgetsBinding.instance.addObserver(this);
    _initHardwareVolumeControl();
    // Listen to player selection changes to toggle volume interception
    _musicProvider.addListener(_onProviderChanged);
  }

  Future<void> _initHardwareVolumeControl() async {
    try {
      _builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      await _hardwareVolumeService.init();

      _volumeUpSub = _hardwareVolumeService.onVolumeUp.listen((_) {
        _adjustVolume(_volumeStep);
      });

      _volumeDownSub = _hardwareVolumeService.onVolumeDown.listen((_) {
        _adjustVolume(-_volumeStep);
      });

      // Listen for absolute volume changes from lockscreen/background
      // (ContentObserver on system STREAM_MUSIC volume)
      _absoluteVolumeSub = _hardwareVolumeService.onAbsoluteVolumeChange.listen((volume) {
        _setAbsoluteVolume(volume);
      });
    } catch (e, stack) {
      _logger.error('Hardware volume init failed', context: 'VolumeInit', error: e, stackTrace: stack);
    }
  }

  /// Called when provider state changes - check if selected player changed
  void _onProviderChanged() {
    final currentPlayerId = _musicProvider.selectedPlayer?.playerId;
    if (currentPlayerId != _lastSelectedPlayerId) {
      _lastSelectedPlayerId = currentPlayerId;
      _updateVolumeInterception();
    }
  }

  /// Enable/disable volume button interception based on selected player.
  /// Also manages the volume observer for lockscreen volume routing.
  Future<void> _updateVolumeInterception() async {
    final player = _musicProvider.selectedPlayer;
    final isBuiltinPlayer = _builtinPlayerId != null &&
        player?.playerId == _builtinPlayerId;
    await _hardwareVolumeService.setIntercepting(!isBuiltinPlayer);

    // Start/stop volume observer for lockscreen volume changes.
    // When a remote/group player is active, observe system volume changes
    // so lockscreen hardware buttons route to the MA player.
    if (!isBuiltinPlayer && player != null) {
      // Get the effective volume to sync the system volume HUD
      final effectiveVolume = _musicProvider.groupVolumeManager.isGroupPlayer(player)
          ? (_musicProvider.groupVolumeManager.getEffectiveVolumeLevel(
                  player, _musicProvider.availablePlayersUnfiltered) ?? player.volume)
          : player.volume;
      await _hardwareVolumeService.startVolumeObserver(initialVolume: effectiveVolume);
    } else {
      await _hardwareVolumeService.stopVolumeObserver();
    }
  }

  Future<void> _adjustVolume(int delta) async {
    final player = _musicProvider.selectedPlayer;
    if (player == null) return;

    // Use effective volume for group players (player.volume returns 0
    // because MA API returns null for group player volume_level)
    final currentVolume = _musicProvider.groupVolumeManager.isGroupPlayer(player)
        ? (_musicProvider.groupVolumeManager.getEffectiveVolumeLevel(
                player, _musicProvider.availablePlayersUnfiltered) ?? player.volume)
        : player.volume;

    final newVolume = (currentVolume + delta).clamp(0, 100);
    if (newVolume != currentVolume) {
      try {
        await _musicProvider.setVolume(player.playerId, newVolume);
      } catch (e) {
        _logger.error('Hardware volume adjustment failed', context: 'VolumeControl', error: e);
      }
    }
  }

  /// Handle absolute volume change from lockscreen/background.
  /// Called when the ContentObserver detects a system volume change
  /// while a remote/group player is active.
  Future<void> _setAbsoluteVolume(int volume) async {
    final player = _musicProvider.selectedPlayer;
    if (player == null) return;

    // Don't route to builtin player - that's handled by the system directly
    if (_builtinPlayerId != null && player.playerId == _builtinPlayerId) return;

    try {
      await _musicProvider.setVolume(player.playerId, volume.clamp(0, 100));
    } catch (e) {
      _logger.error('Lockscreen volume change failed', context: 'VolumeControl', error: e);
    }
  }

  @override
  void dispose() {
    _musicProvider.removeListener(_onProviderChanged);
    _volumeUpSub?.cancel();
    _volumeDownSub?.cancel();
    _absoluteVolumeSub?.cancel();
    _hardwareVolumeService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    // Intercept back button at app level - runs BEFORE Navigator processes it
    // Priority order: device list > queue panel > expanded player > normal navigation

    // Device list has highest priority - dismiss it first
    if (GlobalPlayerOverlay.isPlayerRevealVisible) {
      GlobalPlayerOverlay.dismissPlayerReveal();
      return true; // We handled it, don't let Navigator process it
    }

    // Queue panel second - close it before collapsing player
    // Use target state (not animation value) to handle rapid open-close timing
    // Use withHaptic: false because Android back gesture provides system haptic
    if (GlobalPlayerOverlay.isQueuePanelTargetOpen) {
      GlobalPlayerOverlay.closeQueuePanel(withHaptic: false);
      return true; // We handled it, don't let Navigator process it
    }

    // Then check expanded player
    // No haptic - Android back gesture provides its own
    if (GlobalPlayerOverlay.isPlayerExpanded) {
      GlobalPlayerOverlay.collapsePlayer(withHaptic: false);
      return true; // We handled it, don't let Navigator process it
    }

    // Let Navigator handle the back gesture normally
    return super.didPopRoute();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // App came back to foreground - check connection and reconnect if needed
      _logger.log('📱 App resumed - checking WebSocket connection...');
      _musicProvider.checkAndReconnect();
    } else if (state == AppLifecycleState.paused) {
      _logger.log('📱 App paused (backgrounded)');
    } else if (state == AppLifecycleState.detached) {
      _logger.log('📱 App detached (being destroyed)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _musicProvider),
        ChangeNotifierProvider.value(value: _themeProvider),
        ChangeNotifierProvider.value(value: _localeProvider),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, _) {
          return FutureBuilder<(ColorScheme, ColorScheme)?>(
            future: themeProvider.useMaterialTheme
                ? SystemThemeHelper.getSystemColorSchemes()
                : null,
            builder: (context, snapshot) {
              // Determine which color schemes to use
              ColorScheme? lightColorScheme;
              ColorScheme? darkColorScheme;

              if (themeProvider.useMaterialTheme && snapshot.hasData && snapshot.data != null) {
                // Use system color schemes, but override background to match app design
                // Material You doesn't set background consistently, causing black screen issues
                final (light, dark) = snapshot.data!;
                lightColorScheme = light.copyWith(
                  surface: light.surface,
                  background: const Color(0xFFFAFAFA), // App's preferred light background
                );
                darkColorScheme = dark.copyWith(
                  surface: const Color(0xFF2a2a2a), // App's preferred dark surface
                  background: const Color(0xFF1a1a1a), // App's preferred dark background
                );
              } else {
                // Use custom color from theme provider
                lightColorScheme = generateLightColorScheme(themeProvider.customColor);
                darkColorScheme = generateDarkColorScheme(themeProvider.customColor);
              }

              return SystemUIWrapper(
                themeMode: themeProvider.themeMode,
                lightColorScheme: lightColorScheme,
                darkColorScheme: darkColorScheme,
                child: MaterialApp(
                  navigatorKey: navigationProvider.navigatorKey,
                  title: 'Ensemble',
                  debugShowCheckedModeBanner: false,
                  // Localization
                  localizationsDelegates: const [
                    S.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: S.supportedLocales,
                  locale: localeProvider.locale,
                  // Fallback to English when locale is not supported
                  localeListResolutionCallback: (locales, supportedLocales) {
                    // If user has set a specific locale, try to use it
                    if (localeProvider.locale != null) {
                      for (final supported in supportedLocales) {
                        if (supported.languageCode == localeProvider.locale!.languageCode) {
                          return supported;
                        }
                      }
                    }
                    // Try to match system locales
                    if (locales != null) {
                      for (final locale in locales) {
                        for (final supported in supportedLocales) {
                          if (supported.languageCode == locale.languageCode) {
                            return supported;
                          }
                        }
                      }
                    }
                    // Fallback to English (not German)
                    return const Locale('en');
                  },
                  themeMode: themeProvider.themeMode,
                  theme: AppTheme.lightTheme(colorScheme: lightColorScheme),
                  darkTheme: AppTheme.darkTheme(colorScheme: darkColorScheme),
                  builder: (context, child) {
                    // Wrap entire app with global player overlay
                    return GlobalPlayerOverlay(child: child ?? const SizedBox.shrink());
                  },
                  home: const AppStartup(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Widget that manages system UI overlay style updates efficiently
/// Only updates when theme properties actually change
class SystemUIWrapper extends StatefulWidget {
  final Widget child;
  final ThemeMode themeMode;
  final ColorScheme lightColorScheme;
  final ColorScheme darkColorScheme;

  const SystemUIWrapper({
    super.key,
    required this.child,
    required this.themeMode,
    required this.lightColorScheme,
    required this.darkColorScheme,
  });

  @override
  State<SystemUIWrapper> createState() => _SystemUIWrapperState();
}

class _SystemUIWrapperState extends State<SystemUIWrapper> {
  ThemeMode? _previousThemeMode;
  Brightness? _previousPlatformBrightness;
  ColorScheme? _previousLightColorScheme;
  ColorScheme? _previousDarkColorScheme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSystemUIIfNeeded();
  }

  @override
  void didUpdateWidget(SystemUIWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateSystemUIIfNeeded();
  }

  void _updateSystemUIIfNeeded() {
    final platformBrightness = MediaQuery.platformBrightnessOf(context);

    // Check if any relevant properties have changed
    final themeChanged = _previousThemeMode != widget.themeMode;
    final platformBrightnessChanged = _previousPlatformBrightness != platformBrightness;
    final lightColorSchemeChanged = _previousLightColorScheme != widget.lightColorScheme;
    final darkColorSchemeChanged = _previousDarkColorScheme != widget.darkColorScheme;

    if (themeChanged || platformBrightnessChanged || lightColorSchemeChanged || darkColorSchemeChanged) {
      // Determine if we should use dark theme
      final isDark = widget.themeMode == ThemeMode.dark ||
          (widget.themeMode == ThemeMode.system && platformBrightness == Brightness.dark);

      // Update system UI overlay style
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: isDark
              ? widget.darkColorScheme.surface
              : widget.lightColorScheme.surface,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
      );

      // Update cached values
      _previousThemeMode = widget.themeMode;
      _previousPlatformBrightness = platformBrightness;
      _previousLightColorScheme = widget.lightColorScheme;
      _previousDarkColorScheme = widget.darkColorScheme;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Startup widget that checks if user is logged in and auto-connects.
///
/// CRITICAL: This widget is the single source of truth for the startup transition.
/// It loads settings FIRST (before connection), then waits for the appropriate
/// conditions before showing HomeScreen. This eliminates the race condition between
/// AppStartup and GlobalPlayerOverlay that caused the home screen flash.
///
/// For first-time users: Holds dark screen until connected + player selected,
/// so the welcome overlay can appear seamlessly.
/// For returning users: Transitions as soon as connection is established.
class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  bool _isConnecting = false;
  String? _savedServerUrl;
  bool _connectionAttempted = false;

  // Welcome system state - loaded FIRST before connection check
  bool _settingsLoaded = false;
  bool _hasCompletedOnboarding = true; // Default to true (no welcome needed)

  @override
  void initState() {
    super.initState();
    _loadSettingsFirst();
  }

  /// Load settings BEFORE checking connection.
  /// This ensures we know if this is a first-time user before transitioning.
  Future<void> _loadSettingsFirst() async {
    // Load onboarding state first - this is critical for determining
    // when to transition to HomeScreen
    _hasCompletedOnboarding = await SettingsService.getHasCompletedOnboarding();

    if (!mounted) return;

    setState(() {
      _settingsLoaded = true;
    });

    _logger.log('🚀 AppStartup: Settings loaded, hasCompletedOnboarding=$_hasCompletedOnboarding');

    // Now check connection
    _checkAndConnect();
  }

  Future<void> _checkAndConnect() async {
    final serverUrl = await SettingsService.getServerUrl();

    if (!mounted) return;

    setState(() {
      _savedServerUrl = serverUrl;
    });

    // If we have a saved server URL, attempt auto-connection
    if (serverUrl != null && serverUrl.isNotEmpty) {
      setState(() {
        _isConnecting = true;
      });

      final provider = context.read<MusicAssistantProvider>();

      // Connection is handled by MusicAssistantProvider._initialize()
      // Just wait for it to complete or timeout
      _logger.log('🚀 AppStartup: Waiting for provider auto-connection to $serverUrl');

      // For first-time users, we need to wait for both connection AND player selection
      // so the welcome overlay can appear immediately without home screen flash.
      // For returning users, just wait for connection.
      final needsWelcome = !_hasCompletedOnboarding;

      // Give the provider time to connect (it restores credentials and connects in _initialize)
      // Check connection state periodically
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 250));

        if (needsWelcome) {
          // First-time user: wait for connection + player selection
          if (provider.isConnected && provider.selectedPlayer != null) {
            _logger.log('🚀 AppStartup: First-time user ready (connected + player selected)');
            break;
          }
        } else {
          // Returning user: just wait for connection
          if (provider.isConnected) {
            _logger.log('🚀 AppStartup: Connection established');
            break;
          }
        }

        if (provider.connectionState == MAConnectionState.error) {
          _logger.log('🚀 AppStartup: Connection failed with error');
          break;
        }
      }

      if (!provider.isConnected) {
        _logger.log('🚀 AppStartup: Connection still pending or failed');
      }

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionAttempted = true;
        });
      }
    } else {
      setState(() {
        _connectionAttempted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking settings or connecting
    // CRITICAL: Don't transition until settings are loaded - this prevents the race
    if (!_settingsLoaded || !_connectionAttempted || _isConnecting) {
      return Scaffold(
        backgroundColor: const Color(0xFF1a1a1a),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              if (_isConnecting) ...[
                const SizedBox(height: 16),
                Text(
                  'Connecting...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // If server URL is saved, go to home screen
    // Otherwise, show login screen
    final hasServerUrl = _savedServerUrl != null && _savedServerUrl!.isNotEmpty;
    return hasServerUrl ? const HomeScreen() : const LoginScreen();
  }
}
