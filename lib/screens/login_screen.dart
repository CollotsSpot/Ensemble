import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/settings_service.dart';
import '../services/auth/auth_strategy.dart';
import '../services/debug_logger.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '8095');
  final TextEditingController _authServerUrlController = TextEditingController(); // For separate auth server (Authelia)
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isConnecting = false;
  bool _isDetectingAuth = false;
  AuthStrategy? _detectedAuthStrategy;
  String? _detectedAuthType;
  String? _error;
  bool _showDebug = false;
  List<String> _debugLogs = [];

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final savedPort = await SettingsService.getWebSocketPort();
    final savedAuthServerUrl = await SettingsService.getAuthServerUrl();
    final savedOwnerName = await SettingsService.getOwnerName();

    if (savedPort != null) {
      setState(() {
        _portController.text = savedPort.toString();
      });
    }

    if (savedAuthServerUrl != null) {
      setState(() {
        _authServerUrlController.text = savedAuthServerUrl;
      });
    }

    if (savedOwnerName != null) {
      setState(() {
        _ownerNameController.text = savedOwnerName;
      });
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _ownerNameController.dispose();
    _portController.dispose();
    _authServerUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _normalizeServerUrl(String url) {
    // Remove any trailing slashes
    url = url.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    // If URL already has a protocol, return it
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    // If it's an IP address or localhost, default to http://
    if (url.startsWith('192.') ||
        url.startsWith('10.') ||
        url.startsWith('172.') ||
        url == 'localhost' ||
        url.startsWith('127.')) {
      return 'http://$url';
    }

    // For domain names, default to https://
    return 'https://$url';
  }

  String _buildServerUrl() {
    // Normalize the base URL
    var url = _normalizeServerUrl(_serverUrlController.text.trim());

    // Parse to check if port is already included
    final uri = Uri.parse(url);

    // Get port from field
    final portText = _portController.text.trim();
    if (portText.isEmpty) {
      return url; // No port specified, use URL as-is
    }

    final port = int.tryParse(portText);
    if (port == null) {
      return url; // Invalid port, use URL as-is
    }

    // Skip adding port if it's the default for the scheme
    final isDefaultPort = (uri.scheme == 'https' && port == 443) ||
                          (uri.scheme == 'http' && port == 80);

    if (isDefaultPort) {
      return url; // Don't add default ports
    }

    // Build URL with custom port
    return '${uri.scheme}://${uri.host}:$port';
  }

  void _addDebugLog(String message) {
    setState(() {
      _debugLogs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
  }

  Future<void> _detectAuthRequirements() async {
    if (_serverUrlController.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter your Music Assistant server address';
      });
      return;
    }

    setState(() {
      _isDetectingAuth = true;
      _error = null;
      _detectedAuthStrategy = null;
      _detectedAuthType = null;
      _debugLogs.clear();
    });

    try {
      final serverUrl = _buildServerUrl();
      _addDebugLog('Built server URL: $serverUrl');

      final provider = context.read<MusicAssistantProvider>();

      _addDebugLog('Starting auth detection...');
      // Auto-detect authentication requirements
      final strategy = await provider.authManager.detectAuthStrategy(serverUrl);

      _addDebugLog('Detection complete. Strategy: ${strategy?.name ?? 'null'}');

      if (strategy == null) {
        setState(() {
          _error = 'Cannot determine authentication requirements. Please check server URL.';
          _isDetectingAuth = false;
        });
        return;
      }

      setState(() {
        _detectedAuthStrategy = strategy;
        _detectedAuthType = _getAuthTypeName(strategy.name);
        _isDetectingAuth = false;
      });

      // If no auth required, connect immediately
      if (strategy.name == 'none') {
        await _connect();
      }
    } catch (e) {
      setState(() {
        _error = 'Auth detection failed: ${e.toString()}';
        _isDetectingAuth = false;
      });
    }
  }

  String _getAuthTypeName(String strategyName) {
    switch (strategyName) {
      case 'none':
        return 'No Authentication';
      case 'basic':
        return 'HTTP Basic Auth';
      case 'authelia':
        return 'Authelia';
      case 'music_assistant':
        return 'Music Assistant Login';
      default:
        return 'Unknown';
    }
  }

  IconData _getAuthIcon(String strategyName) {
    switch (strategyName) {
      case 'none':
        return Icons.lock_open_rounded;
      case 'basic':
        return Icons.vpn_key_rounded;
      case 'authelia':
        return Icons.shield_rounded;
      case 'music_assistant':
        return Icons.music_note_rounded;
      default:
        return Icons.security_rounded;
    }
  }

  Future<void> _connect() async {
    if (_serverUrlController.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter your Music Assistant server address';
      });
      return;
    }

    // Validate owner name - only required if NOT using MA auth
    // (MA auth will get display_name from user profile after login)
    final isMaAuth = _detectedAuthStrategy?.name == 'music_assistant';
    if (!isMaAuth && _ownerNameController.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter your name';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      final serverUrl = _buildServerUrl();
      final port = _portController.text.trim();

      // Validate port
      if (port.isEmpty) {
        setState(() {
          _error = 'Please enter a port number';
          _isConnecting = false;
        });
        return;
      }

      final portNum = int.tryParse(port);
      if (portNum == null || portNum < 1 || portNum > 65535) {
        setState(() {
          _error = 'Please enter a valid port number (1-65535)';
          _isConnecting = false;
        });
        return;
      }

      // Save owner name (if provided) and port to settings
      // For MA auth, the owner name will be set from user profile after login
      if (!isMaAuth && _ownerNameController.text.trim().isNotEmpty) {
        await SettingsService.setOwnerName(_ownerNameController.text.trim());
      }
      await SettingsService.setWebSocketPort(portNum);

      final provider = context.read<MusicAssistantProvider>();

      // Handle authentication based on detected strategy
      // Note: isMaAuth is already defined earlier in this method

      if (_detectedAuthStrategy != null && _detectedAuthStrategy!.name != 'none' && !isMaAuth) {
        // Pre-connect auth (Authelia, Basic Auth)
        final username = _usernameController.text.trim();
        final password = _passwordController.text.trim();

        if (username.isEmpty || password.isEmpty) {
          setState(() {
            _error = 'Please enter username and password';
            _isConnecting = false;
          });
          return;
        }

        // Get auth server URL (if provided for Authelia)
        String? authServerUrl;
        if (_detectedAuthStrategy!.name == 'authelia') {
          final authUrl = _authServerUrlController.text.trim();
          if (authUrl.isNotEmpty) {
            authServerUrl = _normalizeServerUrl(authUrl);
          }
        }

        // Attempt login with detected strategy
        final success = await provider.authManager.login(
          serverUrl,
          username,
          password,
          _detectedAuthStrategy!,
          authServerUrl: authServerUrl,
        );

        if (!success) {
          setState(() {
            _error = 'Authentication failed. Please check your credentials.';
            _isConnecting = false;
          });
          return;
        }

        // Save credentials for future auto-login
        await SettingsService.setUsername(username);
        await SettingsService.setPassword(password);

        // Save auth server URL if provided
        if (authServerUrl != null && authServerUrl.isNotEmpty) {
          await SettingsService.setAuthServerUrl(authServerUrl);
        } else {
          await SettingsService.setAuthServerUrl(null);
        }

        // Save auth credentials to settings
        final serialized = provider.authManager.serializeCredentials();
        if (serialized != null) {
          await SettingsService.setAuthCredentials(serialized);
        }
      }

      // Connect to server
      await provider.connectToServer(serverUrl);

      // Post-connect auth (Music Assistant native auth)
      if (isMaAuth) {
        final username = _usernameController.text.trim();
        final password = _passwordController.text.trim();

        if (username.isEmpty || password.isEmpty) {
          setState(() {
            _error = 'Please enter username and password';
            _isConnecting = false;
          });
          return;
        }

        _addDebugLog('Authenticating with Music Assistant...');

        // Check if we have a stored MA token first
        final storedToken = await SettingsService.getMaAuthToken();
        bool authSuccess = false;

        if (storedToken != null && provider.api != null) {
          _addDebugLog('Trying stored MA token...');
          authSuccess = await provider.api!.authenticateWithToken(storedToken);
        }

        if (!authSuccess) {
          _addDebugLog('Logging in with credentials...');
          // Login with credentials over WebSocket
          final accessToken = await provider.api?.loginWithCredentials(username, password);

          if (accessToken == null) {
            setState(() {
              _error = 'Music Assistant login failed. Please check your credentials.';
              _isConnecting = false;
            });
            return;
          }

          // Try to create a long-lived token for future use
          final longLivedToken = await provider.api?.createLongLivedToken();
          final tokenToStore = longLivedToken ?? accessToken;

          // Save the token for future auto-login
          await SettingsService.setMaAuthToken(tokenToStore);
          _addDebugLog('MA token saved for future logins');
        }

        // Save credentials for future auto-login
        await SettingsService.setUsername(username);
        await SettingsService.setPassword(password);

        // Save auth strategy info
        await SettingsService.setAuthCredentials({
          'strategy': 'music_assistant',
          'data': {'username': username},
        });
      }

      // Wait for connection and authentication to complete
      // MA auth happens asynchronously after connect, so we need to wait longer
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (provider.isConnected) break;
      }

      if (provider.isConnected) {
        // Navigate to home screen
        if (mounted) {
          // Ensure keyboard is closed before navigating
          FocusScope.of(context).unfocus();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } else {
        setState(() {
          _error = 'Could not connect to server. Please check the address and try again.';
          _isConnecting = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Connection failed: ${e.toString()}';
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Determine if we need auth fields
    final needsAuth = _detectedAuthStrategy != null && _detectedAuthStrategy!.name != 'none';

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 48.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),

              // Logo
              Builder(
                builder: (context) {
                  final width = MediaQuery.of(context).size.width * 0.5;
                  return Center(
                    child: Image.asset(
                      'assets/images/ensemble_icon_transparent.png',
                      width: width,
                      fit: BoxFit.contain,
                    ),
                  );
                },
              ),

              const SizedBox(height: 48),

              // Server URL
              Text(
                'Server Address',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onBackground,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _serverUrlController,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'e.g., music.example.com or 192.168.1.100',
                  hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                  filled: true,
                  fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(
                    Icons.dns_rounded,
                    color: colorScheme.onSurface.withOpacity(0.54),
                  ),
                ),
                enabled: !_isConnecting && !_isDetectingAuth,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),

              const SizedBox(height: 24),

              // Your Name - only show AFTER auth detection AND only for non-MA auth
              // (MA auth gets display_name from user profile automatically)
              // Show for: 'none' (no auth), 'authelia', 'basic_auth', etc.
              // Hide for: 'music_assistant' (gets name from profile)
              if (_detectedAuthStrategy != null &&
                  _detectedAuthStrategy!.name != 'music_assistant') ...[
                Text(
                  'Your Name',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onBackground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _ownerNameController,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Your first name',
                    hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                    filled: true,
                    fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.person_rounded,
                      color: colorScheme.onSurface.withOpacity(0.54),
                    ),
                  ),
                  enabled: !_isConnecting && !_isDetectingAuth,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 24),
              ],

              // Port
              Text(
                'Port',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onBackground,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _portController,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: '8095',
                  hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                  filled: true,
                  fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(
                    Icons.settings_ethernet_rounded,
                    color: colorScheme.onSurface.withOpacity(0.54),
                  ),
                ),
                enabled: !_isConnecting && !_isDetectingAuth,
                keyboardType: TextInputType.number,
                textInputAction: needsAuth ? TextInputAction.next : TextInputAction.done,
                onSubmitted: (_) => needsAuth ? null : _detectedAuthStrategy == null ? _detectAuthRequirements() : _connect(),
              ),

              const SizedBox(height: 24),

              // Detected auth method indicator
              if (_detectedAuthType != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: needsAuth
                        ? colorScheme.primaryContainer.withOpacity(0.3)
                        : colorScheme.tertiaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: needsAuth
                          ? colorScheme.primary.withOpacity(0.3)
                          : colorScheme.tertiary.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getAuthIcon(_detectedAuthStrategy!.name),
                        color: needsAuth ? colorScheme.primary : colorScheme.tertiary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Detected: $_detectedAuthType',
                              style: TextStyle(
                                color: needsAuth
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onTertiaryContainer,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (needsAuth)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'This server requires authentication',
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer.withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Authentication fields (shown only if auth required)
              if (needsAuth) ...[
                // Auth Server URL (only for Authelia)
                if (_detectedAuthStrategy?.name == 'authelia') ...[
                  Text(
                    'Auth Server URL (Optional)',
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Leave empty if authentication is on the same server',
                    style: TextStyle(
                      color: colorScheme.onBackground.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _authServerUrlController,
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'e.g., auth.example.com (if different from server)',
                      hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                      filled: true,
                      fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(
                        Icons.shield_rounded,
                        color: colorScheme.onSurface.withOpacity(0.54),
                      ),
                    ),
                    enabled: !_isConnecting,
                    textInputAction: TextInputAction.next,
                  ),

                  const SizedBox(height: 24),
                ],

                Text(
                  'Username',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onBackground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _usernameController,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Username',
                    hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                    filled: true,
                    fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.person_rounded,
                      color: colorScheme.onSurface.withOpacity(0.54),
                    ),
                  ),
                  enabled: !_isConnecting,
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 16),

                Text(
                  'Password',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onBackground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _passwordController,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                    filled: true,
                    fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.lock_rounded,
                      color: colorScheme.onSurface.withOpacity(0.54),
                    ),
                  ),
                  obscureText: true,
                  enabled: !_isConnecting,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _connect(),
                ),

                const SizedBox(height: 16),
              ],

              const SizedBox(height: 16),

              // Error message
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_rounded, color: colorScheme.error, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

              // Debug toggle button
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showDebug = !_showDebug;
                  });
                },
                icon: Icon(
                  _showDebug ? Icons.bug_report : Icons.bug_report_outlined,
                  size: 16,
                ),
                label: Text(
                  _showDebug ? 'Hide Debug' : 'Show Debug',
                  style: const TextStyle(fontSize: 12),
                ),
              ),

              // Debug panel
              if (_showDebug) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.terminal, color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          const Text(
                            'Debug Console',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              final logs = DebugLogger().getAllLogs();
                              // Copy to clipboard
                              if (logs.isNotEmpty) {
                                // Simple copy - in real app would use Clipboard API
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Logs copied! (Feature coming soon)'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(50, 20),
                            ),
                            icon: const Icon(Icons.copy, size: 10, color: Colors.green),
                            label: const Text(
                              'Copy',
                              style: TextStyle(fontSize: 10, color: Colors.green),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              DebugLogger().clear();
                              setState(() {
                                _debugLogs.clear();
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(40, 20),
                            ),
                            child: const Text(
                              'Clear',
                              style: TextStyle(fontSize: 10, color: Colors.green),
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.green, height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          reverse: true,
                          child: Builder(
                            builder: (context) {
                              // Get all logs from DebugLogger singleton
                              final allLogs = DebugLogger().logs;
                              final recentLogs = allLogs.length > 50
                                  ? allLogs.sublist(allLogs.length - 50)
                                  : allLogs;

                              return recentLogs.isEmpty
                                  ? const Text(
                                      'No debug logs yet. Try detecting auth.',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 10,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: recentLogs
                                          .map((log) => Padding(
                                                padding: const EdgeInsets.only(bottom: 2),
                                                child: Text(
                                                  log,
                                                  style: const TextStyle(
                                                    color: Colors.green,
                                                    fontSize: 10,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ))
                                          .toList(),
                                    );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Connect button (changes based on state)
              ElevatedButton(
                onPressed: (_isConnecting || _isDetectingAuth)
                    ? null
                    : (_detectedAuthStrategy == null ? _detectAuthRequirements : _connect),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isDetectingAuth
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Detecting authentication...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : _isConnecting
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                            ),
                          )
                        : Text(
                            _detectedAuthStrategy == null ? 'Detect & Connect' : 'Connect',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
