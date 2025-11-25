import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/debug_logger.dart';
import '../theme/theme_provider.dart';
import 'debug_log_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverUrlController = TextEditingController();
  final _portController = TextEditingController(text: '8095');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _logger = DebugLogger();
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final provider = context.read<MusicAssistantProvider>();
    _serverUrlController.text = provider.serverUrl ?? '';

    final port = await SettingsService.getWebSocketPort();
    if (port != null) {
      _portController.text = port.toString();
    }

    final username = await SettingsService.getUsername();
    if (username != null) {
      _usernameController.text = username;
    }

    final password = await SettingsService.getPassword();
    if (password != null) {
      _passwordController.text = password;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_serverUrlController.text.isEmpty) {
      _showError('Please enter a server URL');
      return;
    }

    // Validate and save port
    final port = _portController.text.trim();
    if (port.isEmpty) {
      _showError('Please enter a port number');
      return;
    }

    final portNum = int.tryParse(port);
    if (portNum == null || portNum < 1 || portNum > 65535) {
      _showError('Please enter a valid port number (1-65535)');
      return;
    }

    await SettingsService.setWebSocketPort(portNum);

    setState(() {
      _isConnecting = true;
    });

    try {
      // Attempt authentication if username/password provided
      if (_usernameController.text.trim().isNotEmpty &&
          _passwordController.text.trim().isNotEmpty) {
        _logger.log('🔐 Attempting login with credentials...');

        final token = await _authService.login(
          _serverUrlController.text,
          _usernameController.text.trim(),
          _passwordController.text.trim(),
        );

        if (token != null) {
          // Save credentials for future use
          await SettingsService.setUsername(_usernameController.text.trim());
          await SettingsService.setPassword(_passwordController.text.trim());

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✓ Authentication successful!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          _showError('Authentication failed. Please check your credentials.');
          setState(() {
            _isConnecting = false;
          });
          return;
        }
      }

      // Connect to Music Assistant
      final provider = context.read<MusicAssistantProvider>();
      await provider.connectToServer(_serverUrlController.text);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _showError('Connection failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          color: Colors.white,
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
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
            color: Colors.white,
            tooltip: 'Debug Logs',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _getStatusIcon(provider.connectionState),
                    color: _getStatusColor(provider.connectionState),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connection Status',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getStatusText(provider.connectionState),
                          style: TextStyle(
                            color: _getStatusColor(provider.connectionState),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Server URL input
            const Text(
              'Music Assistant Server',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your Music Assistant server URL or IP address',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _serverUrlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g., music.example.com or 192.168.1.100',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(
                  Icons.dns_rounded,
                  color: Colors.white54,
                ),
              ),
              enabled: !_isConnecting,
            ),

            const SizedBox(height: 24),

            // Port input
            const Text(
              'Port',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Music Assistant WebSocket port (usually 8095)',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _portController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '8095',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(
                  Icons.settings_ethernet_rounded,
                  color: Colors.white54,
                ),
              ),
              enabled: !_isConnecting,
            ),

            const SizedBox(height: 32),

            // Connect button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isConnecting ? null : _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  disabledBackgroundColor: colorScheme.primary.withOpacity(0.38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isConnecting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Text(
                        'Connect',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            if (provider.isConnected) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () async {
                    await provider.disconnect();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Disconnected from server'),
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Disconnect',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Theme section
            const Text(
              'Theme',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Theme mode selector
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Theme Mode',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, _) {
                      return SegmentedButton<ThemeMode>(
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
                              return Colors.white;
                            }
                            return Colors.transparent;
                          }),
                          foregroundColor: MaterialStateProperty.resolveWith((states) {
                            if (states.contains(MaterialState.selected)) {
                              return colorScheme.onPrimary;
                            }
                            return colorScheme.onSurface.withOpacity(0.7);
                          }),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Material You toggle
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      'Material You',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Use system colors (Android 12+)',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: themeProvider.useMaterialTheme,
                    onChanged: (value) {
                      themeProvider.setUseMaterialTheme(value);
                    },
                    activeColor: Colors.white,
                    activeTrackColor: Colors.white54,
                    contentPadding: EdgeInsets.zero,
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Adaptive theme toggle
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      'Adaptive Theme',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Extract colors from album and artist artwork',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: themeProvider.adaptiveTheme,
                    onChanged: (value) {
                      themeProvider.setAdaptiveTheme(value);
                    },
                    activeColor: Colors.white,
                    activeTrackColor: Colors.white54,
                    contentPadding: EdgeInsets.zero,
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Debug logs button
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
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Info section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Connection Info',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '• Default ports: 443 for HTTPS, 8095 for HTTP\n'
                    '• You can override the port in the WebSocket Port field\n'
                    '• Use domain name or IP address for server\n'
                    '• Make sure your device can reach the server\n'
                    '• Check debug logs if connection fails',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(MAConnectionState state) {
    switch (state) {
      case MAConnectionState.connected:
        return Icons.check_circle_rounded;
      case MAConnectionState.connecting:
        return Icons.sync_rounded;
      case MAConnectionState.error:
        return Icons.error_rounded;
      case MAConnectionState.disconnected:
        return Icons.cloud_off_rounded;
    }
  }

  Color _getStatusColor(MAConnectionState state) {
    switch (state) {
      case MAConnectionState.connected:
        return Colors.green;
      case MAConnectionState.connecting:
        return Colors.orange;
      case MAConnectionState.error:
        return Colors.red;
      case MAConnectionState.disconnected:
        return Colors.white54;
    }
  }

  String _getStatusText(MAConnectionState state) {
    switch (state) {
      case MAConnectionState.connected:
        return 'Connected';
      case MAConnectionState.connecting:
        return 'Connecting...';
      case MAConnectionState.error:
        return 'Connection Error';
      case MAConnectionState.disconnected:
        return 'Disconnected';
    }
  }
}
