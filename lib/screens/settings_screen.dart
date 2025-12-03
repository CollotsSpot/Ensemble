import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../theme/theme_provider.dart';
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
  }

  @override
  void dispose() {
    _lastFmApiKeyController.dispose();
    _audioDbApiKeyController.dispose();
    super.dispose();
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
    final provider = context.watch<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          color: colorScheme.onBackground,
        ),
        title: Text(
          'Settings',
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
                MaterialPageRoute(
                  builder: (context) => const DebugLogScreen(),
                ),
              );
            },
            color: colorScheme.onBackground,
            tooltip: 'Debug Logs',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Logo - same size as login screen (50% of screen width)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
              child: Image.asset(
                'assets/images/ensemble_icon_transparent.png',
                width: MediaQuery.of(context).size.width * 0.5,
                fit: BoxFit.contain,
              ),
            ),

            // Connection status bar - edge to edge
            Transform.translate(
              offset: const Offset(-24, 0), // Compensate for parent padding
              child: Container(
                width: MediaQuery.of(context).size.width,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.3),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getStatusIcon(provider.connectionState),
                          color: _getStatusColor(provider.connectionState, colorScheme),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getStatusText(provider.connectionState),
                          style: textTheme.titleMedium?.copyWith(
                            color: _getStatusColor(provider.connectionState, colorScheme),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (provider.serverUrl != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        provider.serverUrl!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Disconnect button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  'Disconnect',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  side: BorderSide(color: colorScheme.error.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Theme section
            Text(
              'Theme',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme Mode',
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
                          segments: const [
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.light,
                              label: Text('Light'),
                              icon: Icon(Icons.light_mode_rounded),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.dark,
                              label: Text('Dark'),
                              icon: Icon(Icons.dark_mode_rounded),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.system,
                              label: Text('System'),
                              icon: Icon(Icons.auto_mode_rounded),
                            ),
                          ],
                          selected: {themeProvider.themeMode},
                          onSelectionChanged: (Set<ThemeMode> newSelection) {
                            themeProvider.setThemeMode(newSelection.first);
                          },
                          style: ButtonStyle(
                            backgroundColor: MaterialStateProperty.resolveWith((states) {
                              if (states.contains(MaterialState.selected)) {
                                return colorScheme.primaryContainer;
                              }
                              return Colors.transparent;
                            }),
                            foregroundColor: MaterialStateProperty.resolveWith((states) {
                              if (states.contains(MaterialState.selected)) {
                                return colorScheme.onPrimaryContainer;
                              }
                              return colorScheme.onSurfaceVariant;
                            }),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
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
                      'Material You',
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Use system colors (Android 12+)',
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
                      'Adaptive Theme',
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Extract colors from album and artist artwork',
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

            Text(
              'Metadata APIs (Optional)',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add API keys to fetch artist biographies and album descriptions when Music Assistant doesn\'t have them',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onBackground.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _lastFmApiKeyController,
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Last.fm API Key',
                hintText: 'Get free key at last.fm/api',
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
                labelText: 'TheAudioDB API Key (Premium)',
                hintText: 'Use "2" for free tier or premium key',
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
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DebugLogScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.bug_report_rounded),
                label: const Text('View Debug Logs'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.onBackground,
                  side: BorderSide(color: colorScheme.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
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
    switch (state) {
      case MAConnectionState.connected:
        return 'Connected';
      case MAConnectionState.authenticated:
        return 'Authenticated';
      case MAConnectionState.connecting:
        return 'Connecting...';
      case MAConnectionState.authenticating:
        return 'Authenticating...';
      case MAConnectionState.error:
        return 'Connection Error';
      case MAConnectionState.disconnected:
        return 'Disconnected';
    }
  }
}
