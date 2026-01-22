import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ensemble/services/remote/webrtc_connection.dart';
import 'package:ensemble/services/debug_logger.dart';

/// A WebRTC-to-WebSocket bridge that allows MusicAssistantAPI to work unchanged
/// for remote connections. All traffic is tunneled through a local WebSocket server.
///
/// Architecture:
/// ```
/// MusicAssistantAPI → localhost:port → RemoteBridge → WebRTC → MA Server
/// ```
class RemoteBridge {
  HttpServer? _server;
  WebSocket? _clientSocket;
  WebRTCConnection? _webrtcConnection;
  int? _port;

  StreamSubscription? _clientSubscription;
  StreamSubscription? _webrtcSubscription;

  // Cached server hello to replay when WS client connects
  String? _cachedServerHello;

  final DebugLogger _logger = DebugLogger();

  int? get port => _port;
  bool get isRunning => _server != null;

  /// Start the bridge and connect to the remote MA server.
  /// Returns the local port number to connect to, or null if failed.
  Future<int?> start(String remoteId, String username, String password) async {
    _logger.log('RemoteBridge: Starting bridge for remote ID: $remoteId');

    try {
      // Step 1: Connect to MA via WebRTC
      _webrtcConnection = WebRTCConnection();

      _webrtcConnection!.onStateChanged = (state) {
        _logger.log('RemoteBridge: WebRTC state: $state');
        if (state == WebRTCConnectionState.disconnected ||
            state == WebRTCConnectionState.failed) {
          _handleWebRTCDisconnection();
        }
      };

      _webrtcConnection!.onError = (error) {
        _logger.log('RemoteBridge: WebRTC error: $error');
      };

      final connected = await _webrtcConnection!.connect(remoteId);
      if (!connected) {
        _logger.log('RemoteBridge: WebRTC connection failed');
        await stop();
        return null;
      }

      _logger.log('RemoteBridge: WebRTC connected, authenticating...');

      // Step 2: Authenticate with MA
      final authenticated = await _authenticate(username, password);
      if (!authenticated) {
        _logger.log('RemoteBridge: Authentication failed');
        await stop();
        return null;
      }

      _logger.log('RemoteBridge: Authentication successful');

      // Step 3: Cache the server hello (it was already received by WebRTCConnection)
      if (_webrtcConnection!.serverInfo != null) {
        _cachedServerHello = jsonEncode(_webrtcConnection!.serverInfo);
        _logger.log('RemoteBridge: Cached server hello');
      }

      // Step 4: Start local WebSocket server
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      _logger.log('RemoteBridge: Local WS server started on port $_port');

      // Handle incoming connections
      _server!.listen(_handleHttpRequest);

      // Step 5: Subscribe to WebRTC messages to forward to WS client
      _webrtcSubscription = _webrtcConnection!.rawMessages.listen((message) {
        if (_clientSocket != null) {
          _logger.log('RemoteBridge: WebRTC → WS: ${message.substring(0, message.length > 100 ? 100 : message.length)}...');
          _clientSocket!.add(message);
        }
      });

      return _port;
    } catch (e) {
      _logger.log('RemoteBridge: Start failed: $e');
      await stop();
      return null;
    }
  }

  /// Authenticate with the MA server over WebRTC.
  Future<bool> _authenticate(String username, String password) async {
    try {
      // Step 1: Login to get access token
      _logger.log('RemoteBridge: Sending auth/login...');
      final loginResult = await _webrtcConnection!.sendRequest('auth/login', {
        'username': username,
        'password': password,
        'device_name': 'Ensemble Mobile App',
      });

      _logger.log('RemoteBridge: Login result: $loginResult');

      // Check for error response
      if (loginResult.containsKey('error_code')) {
        _logger.log('RemoteBridge: Login error: ${loginResult['details']}');
        return false;
      }

      String? accessToken;
      if (loginResult['result'] != null) {
        final result = loginResult['result'];
        if (result is Map<String, dynamic>) {
          if (result['success'] == true) {
            accessToken = result['access_token'] as String?;
            final user = result['user'] as Map<String, dynamic>?;
            _logger.log('RemoteBridge: Login successful! User: ${user?['username']}');
          }
        }
      }

      if (accessToken == null) {
        _logger.log('RemoteBridge: No access token received');
        return false;
      }

      // Step 2: Authenticate the session with the token
      _logger.log('RemoteBridge: Authenticating session with token...');
      final authResult = await _webrtcConnection!.sendRequest('auth', {
        'token': accessToken,
      });

      _logger.log('RemoteBridge: Auth result: $authResult');

      if (authResult.containsKey('error_code')) {
        _logger.log('RemoteBridge: Session auth failed: ${authResult['details']}');
        return false;
      }

      _logger.log('RemoteBridge: Session authenticated successfully!');
      return true;
    } catch (e) {
      _logger.log('RemoteBridge: Auth error: $e');
      return false;
    }
  }

  /// Handle incoming HTTP requests and upgrade to WebSocket.
  void _handleHttpRequest(HttpRequest request) async {
    _logger.log('RemoteBridge: Incoming HTTP request: ${request.uri.path}');

    if (WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleClientConnection(socket);
      } catch (e) {
        _logger.log('RemoteBridge: WebSocket upgrade failed: $e');
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }
    } else {
      // Not a WebSocket request
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
    }
  }

  /// Handle a new WebSocket client connection.
  void _handleClientConnection(WebSocket socket) {
    _logger.log('RemoteBridge: WS client connected');

    // Only allow one client at a time
    if (_clientSocket != null) {
      _logger.log('RemoteBridge: Closing existing client connection');
      _clientSubscription?.cancel();
      _clientSocket?.close();
    }

    _clientSocket = socket;

    // Step 1: Send cached server hello immediately
    if (_cachedServerHello != null) {
      _logger.log('RemoteBridge: Sending cached server hello to client');
      _clientSocket!.add(_cachedServerHello!);
    }

    // Step 2: Forward all messages from WS client to WebRTC
    _clientSubscription = _clientSocket!.listen(
      (message) {
        if (message is String && _webrtcConnection != null) {
          _logger.log('RemoteBridge: WS → WebRTC: ${message.substring(0, message.length > 100 ? 100 : message.length)}...');
          _webrtcConnection!.sendRaw(message);
        }
      },
      onDone: () {
        _logger.log('RemoteBridge: WS client disconnected');
        _clientSocket = null;
        _clientSubscription = null;
      },
      onError: (error) {
        _logger.log('RemoteBridge: WS client error: $error');
        _clientSocket = null;
        _clientSubscription = null;
      },
    );
  }

  /// Handle WebRTC disconnection.
  void _handleWebRTCDisconnection() {
    _logger.log('RemoteBridge: WebRTC disconnected, closing WS client');
    _clientSocket?.close();
    _clientSocket = null;
    _clientSubscription?.cancel();
    _clientSubscription = null;
  }

  /// Stop the bridge and disconnect from the remote server.
  Future<void> stop() async {
    _logger.log('RemoteBridge: Stopping bridge');

    _clientSubscription?.cancel();
    _clientSubscription = null;

    _webrtcSubscription?.cancel();
    _webrtcSubscription = null;

    await _clientSocket?.close();
    _clientSocket = null;

    await _server?.close(force: true);
    _server = null;
    _port = null;

    await _webrtcConnection?.disconnect();
    _webrtcConnection = null;

    _cachedServerHello = null;

    _logger.log('RemoteBridge: Bridge stopped');
  }
}
