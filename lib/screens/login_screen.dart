import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
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
      final serverUrl = _serverUrlController.text.trim();
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
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),

              // Logo
              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(height: 16),

              // Welcome text
              const Text(
                'Welcome to Amass',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              const Text(
                'Connect to your Music Assistant server',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 48),

              // Server URL
              const Text(
                'Server Address',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _serverUrlController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g., music.example.com or 192.168.1.100',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF2a2a2a),
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
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),

              const SizedBox(height: 24),

              // Port
              const Text(
                'Port',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _portController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '8095',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF2a2a2a),
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
                keyboardType: TextInputType.number,
                textInputAction: _requiresAuth ? TextInputAction.next : TextInputAction.done,
                onSubmitted: (_) => _requiresAuth ? null : _connect(),
              ),

              const SizedBox(height: 24),

              // Authentication toggle
              Row(
                children: [
                  Checkbox(
                    value: _requiresAuth,
                    onChanged: _isConnecting ? null : (value) {
                      setState(() {
                        _requiresAuth = value ?? false;
                      });
                    },
                    fillColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return Colors.white24;
                      }
                      return states.contains(WidgetState.selected)
                          ? Colors.white
                          : Colors.white54;
                    }),
                    checkColor: const Color(0xFF1a1a1a),
                  ),
                  const Text(
                    'Requires authentication',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),

              // Authentication fields
              if (_requiresAuth) ...[
                const SizedBox(height: 16),

                const Text(
                  'Username',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Username',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF2a2a2a),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.person_rounded,
                      color: Colors.white54,
                    ),
                  ),
                  enabled: !_isConnecting,
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 16),

                const Text(
                  'Password',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF2a2a2a),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_rounded,
                      color: Colors.white54,
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
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_rounded, color: Colors.red, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

              // Connect button
              ElevatedButton(
                onPressed: _isConnecting ? null : _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1a1a1a),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isConnecting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1a1a1a)),
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
              const Text(
                'Need help? Make sure your Music Assistant server is running and accessible from this device.',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
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
