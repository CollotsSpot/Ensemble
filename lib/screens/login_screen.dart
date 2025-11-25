import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../widgets/logo_text.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '8095');
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isConnecting = false;
  bool _showAdvanced = false;
  bool _requiresAuth = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedPort();
  }

  Future<void> _loadSavedPort() async {
    final savedPort = await SettingsService.getWebSocketPort();
    if (savedPort != null) {
      setState(() {
        _portController.text = savedPort.toString();
      });
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
  
  // ... existing code ...

  Future<void> _connect() async {
    if (_serverUrlController.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter your Music Assistant server address';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      final serverUrl = _normalizeServerUrl(_serverUrlController.text.trim());
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

      // Save port to settings
      await SettingsService.setWebSocketPort(portNum);

      final provider = context.read<MusicAssistantProvider>();

      // Handle authentication if needed
      if (_requiresAuth) {
        final username = _usernameController.text.trim();
        final password = _passwordController.text.trim();

        if (username.isEmpty || password.isEmpty) {
          setState(() {
            _error = 'Please enter username and password';
            _isConnecting = false;
          });
          return;
        }

        // Attempt login
        final token = await _authService.login(serverUrl, username, password);
        if (token == null) {
          setState(() {
            _error = 'Authentication failed. Please check your credentials.';
            _isConnecting = false;
          });
          return;
        }

        // Save credentials
        await SettingsService.setUsername(username);
        await SettingsService.setPassword(password);
      }

      // Connect to server
      await provider.connectToServer(serverUrl);

      // Wait a moment for connection to establish
      await Future.delayed(const Duration(milliseconds: 500));

      if (provider.isConnected) {
        // Navigate to home screen
        if (mounted) {
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

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),

              // Logo
              const Center(
                child: LogoText(fontSize: 32),
              ),

              const SizedBox(height: 16),

              // Welcome text
              Text(
                'Welcome',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onBackground,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                'Connect to your Music Assistant server',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onBackground.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
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
                enabled: !_isConnecting,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              
              // ... rest of UI ...


              const SizedBox(height: 24),

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
                enabled: !_isConnecting,
                keyboardType: TextInputType.number,
                textInputAction: _requiresAuth ? TextInputAction.next : TextInputAction.done,
                onSubmitted: (_) => _requiresAuth ? null : _connect(),
              ),

              const SizedBox(height: 24),

              // Authentication fields
              if (_requiresAuth) ...[
                const SizedBox(height: 16),

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
              ],

              const SizedBox(height: 32),

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

              // Connect button
              ElevatedButton(
                onPressed: _isConnecting ? null : _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isConnecting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
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

              const SizedBox(height: 32),

              // Help text
              Text(
                'Need help? Make sure your Music Assistant server is running and accessible from this device.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onBackground.withOpacity(0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
