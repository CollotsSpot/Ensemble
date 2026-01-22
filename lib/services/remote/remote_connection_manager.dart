import 'dart:async';
import 'package:ensemble/services/remote/webrtc_connection.dart';
import 'package:ensemble/services/debug_logger.dart';

/// Manages remote connections to MA servers via WebRTC
class RemoteConnectionManager {
  final WebRTCConnection _connection = WebRTCConnection();

  StreamSubscription? _messageSubscription;
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  bool _isAuthenticated = false;
  String? _serverVersion;

  // Callbacks
  Function(bool connected)? onConnectionChanged;
  Function(String error)? onError;

  bool get isConnected => _connection.isConnected && _isAuthenticated;
  Stream<Map<String, dynamic>> get events => _eventController.stream;
  String? get serverVersion => _serverVersion;

  RemoteConnectionManager() {
    _connection.onStateChanged = _onConnectionStateChanged;
    _connection.onError = (error) => onError?.call(error);

    // Forward events from the data channel
    _messageSubscription = _connection.messages.listen((message) {
      // Check if this is an event (has 'event' key)
      if (message.containsKey('event')) {
        _eventController.add(message);
      }
    });
  }

  /// Connect to a remote MA server using Remote Access ID
  Future<bool> connect(String remoteId, String username, String password) async {
    DebugLogger().log('RemoteConnection: Connecting to remote ID: $remoteId');

    // Connect WebRTC
    final connected = await _connection.connect(remoteId);
    if (!connected) {
      DebugLogger().log('RemoteConnection: WebRTC connection failed');
      return false;
    }

    DebugLogger().log('RemoteConnection: WebRTC connected, authenticating...');

    // Authenticate with MA
    try {
      final authenticated = await _authenticate(username, password);
      if (!authenticated) {
        DebugLogger().log('RemoteConnection: Authentication failed');
        await _connection.disconnect();
        return false;
      }

      _isAuthenticated = true;
      DebugLogger().log('RemoteConnection: Fully connected and authenticated');
      onConnectionChanged?.call(true);
      return true;
    } catch (e) {
      DebugLogger().log('RemoteConnection: Auth error: $e');
      await _connection.disconnect();
      return false;
    }
  }

  /// Authenticate with the MA server
  Future<bool> _authenticate(String username, String password) async {
    try {
      // Step 1: Login to get access token
      DebugLogger().log('RemoteConnection: Sending auth/login...');
      final loginResult = await _connection.sendRequest('auth/login', {
        'username': username,
        'password': password,
        'device_name': 'Ensemble Mobile App',
      });

      DebugLogger().log('RemoteConnection: Login result: $loginResult');

      // Check for error response
      if (loginResult.containsKey('error_code')) {
        DebugLogger().log('RemoteConnection: Login error: ${loginResult['details']}');
        return false;
      }

      String? accessToken;
      if (loginResult['result'] != null) {
        final result = loginResult['result'];

        if (result is Map<String, dynamic>) {
          if (result['success'] == true) {
            accessToken = result['access_token'] as String?;
            final user = result['user'] as Map<String, dynamic>?;

            DebugLogger().log('RemoteConnection: Login successful!');
            DebugLogger().log('RemoteConnection: User: ${user?['username']} (${user?['role']})');
          }
        }
      }

      if (accessToken == null) {
        DebugLogger().log('RemoteConnection: No access token received');
        return false;
      }

      // Step 2: Authenticate the session with the token
      DebugLogger().log('RemoteConnection: Authenticating session with token...');
      final authResult = await _connection.sendRequest('auth', {
        'token': accessToken,
      });

      DebugLogger().log('RemoteConnection: Auth result: $authResult');

      if (authResult.containsKey('error_code')) {
        DebugLogger().log('RemoteConnection: Session auth failed: ${authResult['details']}');
        return false;
      }

      // Store the token for later use
      _accessToken = accessToken;
      DebugLogger().log('RemoteConnection: Session authenticated successfully!');
      return true;
    } catch (e) {
      DebugLogger().log('RemoteConnection: Login error: $e');
      return false;
    }
  }

  String? _accessToken;

  /// Send a command to the MA server
  Future<Map<String, dynamic>> sendCommand(
    String command, [
    Map<String, dynamic>? params,
  ]) async {
    if (!_connection.isConnected) {
      throw Exception('Not connected');
    }

    return await _connection.sendRequest(command, params);
  }

  /// Subscribe to events from the server
  Future<void> subscribe(List<String> eventTypes) async {
    await sendCommand('subscribe_events', {
      'event_types': eventTypes,
    });
  }

  /// Disconnect from the remote server
  Future<void> disconnect() async {
    _isAuthenticated = false;
    await _connection.disconnect();
    onConnectionChanged?.call(false);
  }

  void _onConnectionStateChanged(WebRTCConnectionState state) {
    DebugLogger().log('RemoteConnection: State changed to $state');

    if (state == WebRTCConnectionState.disconnected ||
        state == WebRTCConnectionState.failed) {
      _isAuthenticated = false;
      onConnectionChanged?.call(false);
    }
  }

  void dispose() {
    _messageSubscription?.cancel();
    _eventController.close();
    _connection.dispose();
  }
}
