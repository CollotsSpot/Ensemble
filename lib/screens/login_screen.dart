import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/profile_service.dart';
import '../services/auth/auth_strategy.dart';
import '../services/debug_logger.dart';
import '../services/remote/remote_bridge.dart';
import '../widgets/debug/debug_console.dart';
import '../l10n/app_localizations.dart';
import 'home_screen.dart';
import 'qr_scanner_screen.dart';

enum ConnectionMode { local, remote }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _authServerUrlController = TextEditingController(); // For separate auth server (Authelia)
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _remoteIdController = TextEditingController(); // Remote Access ID
  final FocusNode _usernameFocusNode = FocusNode();

  bool _isConnecting = false;
  bool _isDetectingAuth = false;
  AuthStrategy? _detectedAuthStrategy;
  String? _detectedAuthType;
  String? _error;
  bool _showDebug = false;
  List<String> _debugLogs = [];
  String? _resolvedServerUrl; // The actual URL after fallback (e.g., HTTP if HTTPS failed)
  bool _usedHttpFallback = false; // True if HTTPS failed and we fell back to HTTP

  // Remote connection state
  ConnectionMode _connectionMode = ConnectionMode.local;

  // Static bridge instance - persists across screen transitions
  static RemoteBridge? _remoteBridge;

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
    _remoteIdController.dispose();
    _usernameFocusNode.dispose();
    // Note: Don't stop _remoteBridge here - it needs to stay alive for the session
    // It will be stopped when the app closes or user disconnects
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

    // Tailscale URLs (*.ts.net) - default to http:// since VPN tunnel is already encrypted
    if (url.endsWith('.ts.net') || url.contains('.ts.net:')) {
      return 'http://$url';
    }

    // For domain names, default to https://
    return 'https://$url';
  }

  /// Check if the URL is using HTTP (for security warning display)
  bool _isHttpConnection(String url) {
    final normalized = _normalizeServerUrl(url);
    return normalized.startsWith('http://') && !normalized.startsWith('https://');
  }

  /// Check if the URL is a Tailscale URL (safe for HTTP)
  bool _isTailscaleUrl(String url) {
    final normalized = url.trim().toLowerCase();
    return normalized.contains('.ts.net');
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
        _error = S.of(context)!.pleaseEnterServerAddress;
      });
      return;
    }

    setState(() {
      _isDetectingAuth = true;
      _error = null;
      _detectedAuthStrategy = null;
      _detectedAuthType = null;
      _resolvedServerUrl = null;
      _usedHttpFallback = false;
      _debugLogs.clear();
    });

    try {
      final serverUrl = _buildServerUrl();
      _addDebugLog('Built server URL: $serverUrl');

      final provider = context.read<MusicAssistantProvider>();

      _addDebugLog('Starting auth detection...');
      // Auto-detect authentication requirements
      final strategy = await provider.authManager.detectAuthStrategy(serverUrl);

      // Check if auth manager used a different URL (e.g., HTTP fallback)
      final resolvedUrl = provider.authManager.lastSuccessfulUrl;
      if (resolvedUrl != null && resolvedUrl != serverUrl) {
        _addDebugLog('URL resolved via fallback: $resolvedUrl');
        _usedHttpFallback = serverUrl.startsWith('https://') && resolvedUrl.startsWith('http://');
      }

      _addDebugLog('Detection complete. Strategy: ${strategy?.name ?? 'null'}');

      if (strategy == null) {
        setState(() {
          _error = S.of(context)!.cannotDetermineAuth;
          _isDetectingAuth = false;
        });
        return;
      }

      setState(() {
        _detectedAuthStrategy = strategy;
        _detectedAuthType = _getAuthTypeName(strategy.name);
        _resolvedServerUrl = resolvedUrl;
        _isDetectingAuth = false;
      });

      // If no auth required, connect immediately
      if (strategy.name == 'none') {
        await _connect();
      } else {
        // Auth required - focus username field after a brief delay
        // to allow the new fields to build
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _usernameFocusNode.requestFocus();
          }
        });
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
        return S.of(context)!.noAuthentication;
      case 'basic':
        return S.of(context)!.httpBasicAuth;
      case 'authelia':
        return S.of(context)!.authelia;
      case 'music_assistant':
        return S.of(context)!.musicAssistantLogin;
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
        _error = S.of(context)!.pleaseEnterServerAddress;
      });
      return;
    }

    // Validate owner name - only required if NOT using MA auth
    // (MA auth will get display_name from user profile after login)
    final isMaAuth = _detectedAuthStrategy?.name == 'music_assistant';
    if (!isMaAuth && _ownerNameController.text.trim().isEmpty) {
      setState(() {
        _error = S.of(context)!.pleaseEnterName;
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      // Use the resolved URL if available (e.g., from HTTP fallback), otherwise build it
      final serverUrl = _resolvedServerUrl ?? _buildServerUrl();
      _addDebugLog('Using server URL for connection: $serverUrl');
      final port = _portController.text.trim();

      // Validate port (if provided)
      int? portNum;
      if (port.isNotEmpty) {
        portNum = int.tryParse(port);
        if (portNum == null || portNum < 1 || portNum > 65535) {
          setState(() {
            _error = S.of(context)!.pleaseEnterValidPort;
            _isConnecting = false;
          });
          return;
        }
      }

      // Save owner name (if provided) and port to settings
      // For MA auth, the owner name will be set from user profile after login
      if (!isMaAuth && _ownerNameController.text.trim().isNotEmpty) {
        final ownerName = _ownerNameController.text.trim();
        await SettingsService.setOwnerName(ownerName);

        // Create/activate profile in local database for manual name entry
        if (DatabaseService.instance.isInitialized) {
          await ProfileService.instance.onManualNameEntered(ownerName);
        }
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
            _error = S.of(context)!.pleaseEnterCredentials;
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
            _error = S.of(context)!.authFailed;
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
            _error = S.of(context)!.pleaseEnterCredentials;
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
              _error = S.of(context)!.maLoginFailed;
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
        // Clear remote access ID since this is a direct/local connection
        await SettingsService.clearRemoteAccessId();

        // For first-time users, wait for player selection so the welcome
        // overlay can appear immediately without home screen flash.
        // This matches the logic in AppStartup._checkAndConnect().
        final hasCompletedOnboarding = await SettingsService.getHasCompletedOnboarding();
        if (!hasCompletedOnboarding) {
          // First-time user: wait for connection + player selection
          for (int i = 0; i < 20; i++) {
            await Future.delayed(const Duration(milliseconds: 250));
            if (provider.selectedPlayer != null) break;
          }
        }

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
          _error = S.of(context)!.connectionFailed;
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

  /// Connect via remote bridge (WebRTC tunnel)
  Future<void> _connectRemote() async {
    final remoteId = _remoteIdController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (remoteId.isEmpty) {
      setState(() {
        _error = S.of(context)!.pleaseEnterRemoteId;
      });
      return;
    }

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _error = S.of(context)!.pleaseEnterCredentials;
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    _addDebugLog('Starting remote connection to: $remoteId');

    try {
      // Start the remote bridge
      _remoteBridge = RemoteBridge();
      final port = await _remoteBridge!.start(remoteId, username, password);

      if (port == null) {
        setState(() {
          _error = S.of(context)!.remoteConnectionFailed;
          _isConnecting = false;
        });
        return;
      }

      _addDebugLog('Remote bridge started on port $port');

      // Save credentials BEFORE connecting - needed for MA authentication via bridge
      await SettingsService.setUsername(username);
      await SettingsService.setPassword(password);

      // Connect to the local bridge endpoint
      final serverUrl = 'ws://localhost:$port';
      final provider = context.read<MusicAssistantProvider>();

      _addDebugLog('Connecting to bridge at $serverUrl');
      // Pass remoteId as cloud URL for Sendspin to connect directly
      await provider.connectToServer(serverUrl, isRemoteMode: true, remoteCloudUrl: remoteId);

      // Wait for connection
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (provider.isConnected) break;
      }

      if (provider.isConnected) {
        _addDebugLog('Connected successfully via remote bridge');

        // Save remote access ID and credentials for future auto-reconnect
        await SettingsService.setRemoteAccessId(remoteId);
        await SettingsService.setUsername(username);
        await SettingsService.setPassword(password);

        // For first-time users, wait for player selection
        final hasCompletedOnboarding = await SettingsService.getHasCompletedOnboarding();
        if (!hasCompletedOnboarding) {
          for (int i = 0; i < 20; i++) {
            await Future.delayed(const Duration(milliseconds: 250));
            if (provider.selectedPlayer != null) break;
          }
        }

        // Navigate to home screen
        if (mounted) {
          FocusScope.of(context).unfocus();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } else {
        setState(() {
          _error = S.of(context)!.connectionFailed;
          _isConnecting = false;
        });
      }
    } catch (e) {
      _addDebugLog('Remote connection error: $e');
      setState(() {
        _error = 'Remote connection failed: ${e.toString()}';
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
          padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 78.0),
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

              const SizedBox(height: 32),

              // Connection Mode Toggle
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _isConnecting ? null : () {
                          setState(() {
                            _connectionMode = ConnectionMode.local;
                            _error = null;
                            _detectedAuthStrategy = null;
                            _detectedAuthType = null;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _connectionMode == ConnectionMode.local
                                ? colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.home_rounded,
                                size: 20,
                                color: _connectionMode == ConnectionMode.local
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface.withOpacity(0.6),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                S.of(context)!.localConnection,
                                style: TextStyle(
                                  color: _connectionMode == ConnectionMode.local
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface.withOpacity(0.6),
                                  fontWeight: _connectionMode == ConnectionMode.local
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: _isConnecting ? null : () {
                          setState(() {
                            _connectionMode = ConnectionMode.remote;
                            _error = null;
                            _detectedAuthStrategy = null;
                            _detectedAuthType = null;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _connectionMode == ConnectionMode.remote
                                ? colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cloud_rounded,
                                size: 20,
                                color: _connectionMode == ConnectionMode.remote
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface.withOpacity(0.6),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                S.of(context)!.remoteConnection,
                                style: TextStyle(
                                  color: _connectionMode == ConnectionMode.remote
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface.withOpacity(0.6),
                                  fontWeight: _connectionMode == ConnectionMode.remote
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // REMOTE MODE: Remote Access ID + Credentials
              if (_connectionMode == ConnectionMode.remote) ...[
                Text(
                  S.of(context)!.remoteAccessId,
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onBackground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  S.of(context)!.remoteAccessIdHint,
                  style: TextStyle(
                    color: colorScheme.onBackground.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _remoteIdController,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'abc123def456',
                          hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                          filled: true,
                          fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: Icon(
                            Icons.vpn_key_rounded,
                            color: colorScheme.onSurface.withOpacity(0.54),
                          ),
                        ),
                        enabled: !_isConnecting,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filled(
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      onPressed: _isConnecting ? null : () async {
                        final result = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (context) => const QrScannerScreen(),
                          ),
                        );
                        if (result != null && result.isNotEmpty) {
                          _remoteIdController.text = result;
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Username for remote
                Text(
                  S.of(context)!.username,
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onBackground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _usernameController,
                  focusNode: _connectionMode == ConnectionMode.remote ? _usernameFocusNode : null,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: S.of(context)!.username,
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

                // Password for remote
                Text(
                  S.of(context)!.password,
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
                    hintText: S.of(context)!.password,
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
                  onSubmitted: (_) => _connectRemote(),
                ),

                const SizedBox(height: 16),
              ],

              // LOCAL MODE: Server URL, Port, etc.
              if (_connectionMode == ConnectionMode.local) ...[
              Text(
                S.of(context)!.serverAddress,
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
                  hintText: S.of(context)!.serverAddressHint,
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
                  S.of(context)!.yourName,
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
                    hintText: S.of(context)!.yourFirstName,
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
                S.of(context)!.portOptional,
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onBackground,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                S.of(context)!.portDescription,
                style: TextStyle(
                  color: colorScheme.onBackground.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _portController,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: S.of(context)!.portHint,
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
                              S.of(context)!.detectedAuthType(_detectedAuthType!),
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
                                  S.of(context)!.serverRequiresAuth,
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

              // HTTP connection info banner
              if (_resolvedServerUrl != null && _isHttpConnection(_resolvedServerUrl!))
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: _isTailscaleUrl(_serverUrlController.text)
                        ? colorScheme.secondaryContainer.withOpacity(0.3)
                        : colorScheme.errorContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: _isTailscaleUrl(_serverUrlController.text)
                        ? null
                        : Border.all(color: colorScheme.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isTailscaleUrl(_serverUrlController.text)
                            ? Icons.vpn_lock_rounded
                            : Icons.warning_amber_rounded,
                        color: _isTailscaleUrl(_serverUrlController.text)
                            ? colorScheme.secondary
                            : colorScheme.error,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isTailscaleUrl(_serverUrlController.text)
                                  ? S.of(context)!.tailscaleVpnConnection
                                  : S.of(context)!.unencryptedConnection,
                              style: TextStyle(
                                color: _isTailscaleUrl(_serverUrlController.text)
                                    ? colorScheme.onSecondaryContainer
                                    : colorScheme.onErrorContainer,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _isTailscaleUrl(_serverUrlController.text)
                                    ? S.of(context)!.usingHttpOverTailscale
                                    : _usedHttpFallback
                                        ? S.of(context)!.httpsFailedUsingHttp
                                        : S.of(context)!.httpNotEncrypted,
                                style: TextStyle(
                                  color: (_isTailscaleUrl(_serverUrlController.text)
                                      ? colorScheme.onSecondaryContainer
                                      : colorScheme.onErrorContainer).withOpacity(0.7),
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
                    S.of(context)!.authServerUrlOptional,
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context)!.authServerUrlDescription,
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
                      hintText: S.of(context)!.authServerUrlHint,
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
                  S.of(context)!.username,
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onBackground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _usernameController,
                  focusNode: _usernameFocusNode,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: S.of(context)!.username,
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
                  S.of(context)!.password,
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
                    hintText: S.of(context)!.password,
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
              ], // End of local mode conditional

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
              DebugToggleButton(
                isVisible: _showDebug,
                onToggle: () => setState(() => _showDebug = !_showDebug),
              ),

              // Debug panel
              if (_showDebug) ...[
                const SizedBox(height: 16),
                DebugConsole(
                  onClear: () => setState(() => _debugLogs.clear()),
                ),
                const SizedBox(height: 16),
              ],

              // Connect button (changes based on state)
              ElevatedButton(
                onPressed: (_isConnecting || _isDetectingAuth)
                    ? null
                    : _connectionMode == ConnectionMode.remote
                        ? _connectRemote
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
                          Text(
                            S.of(context)!.detectingAuth,
                            style: const TextStyle(
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
                            _connectionMode == ConnectionMode.remote
                                ? S.of(context)!.connect
                                : (_detectedAuthStrategy == null ? S.of(context)!.detectAndConnect : S.of(context)!.connect),
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
