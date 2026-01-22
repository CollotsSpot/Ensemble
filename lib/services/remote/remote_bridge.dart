import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:ensemble/services/remote/webrtc_connection.dart';
import 'package:ensemble/services/debug_logger.dart';

/// A WebRTC-to-WebSocket bridge that allows MusicAssistantAPI to work unchanged
/// for remote connections. All traffic is tunneled through a local WebSocket server.
///
/// Architecture:
/// ```
/// MusicAssistantAPI → localhost:port → RemoteBridge → WebRTC → MA Server
/// Sendspin → localhost:port/sendspin → RemoteBridge → WebRTC (sendspin channel) → MA Server
/// ```
class RemoteBridge {
  HttpServer? _server;
  WebRTCConnection? _webrtcConnection;
  int? _port;

  // API client (MusicAssistantAPI)
  WebSocket? _apiClientSocket;
  StreamSubscription? _apiClientSubscription;
  StreamSubscription? _apiWebrtcSubscription;

  // Sendspin client (local player audio)
  WebSocket? _sendspinClientSocket;
  StreamSubscription? _sendspinClientSubscription;
  StreamSubscription? _sendspinTextSubscription;
  StreamSubscription? _sendspinBinarySubscription;

  Timer? _healthCheckTimer;

  // Cached server hello to replay when WS client connects
  String? _cachedServerHello;

  // Debug counters
  int _apiMessagesSent = 0;
  int _apiMessagesReceived = 0;
  int _sendspinMessagesSent = 0;
  int _sendspinMessagesReceived = 0;
  DateTime? _lastMessageReceived;

  final DebugLogger _logger = DebugLogger();

  int? get port => _port;
  bool get isRunning => _server != null;
  bool get isSendspinReady => _webrtcConnection?.isSendspinConnected ?? false;

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

      // Step 5: Subscribe to WebRTC API messages to forward to API client
      _apiWebrtcSubscription = _webrtcConnection!.rawMessages.listen((message) {
        _apiMessagesReceived++;
        _lastMessageReceived = DateTime.now();
        if (_apiClientSocket != null) {
          _logger.log('RemoteBridge: WebRTC API → WS: ${message.substring(0, message.length > 100 ? 100 : message.length)}...');
          _apiClientSocket!.add(message);
        }
      });

      // Step 6: Subscribe to Sendspin WebRTC messages (text) to forward to Sendspin client
      _sendspinTextSubscription = _webrtcConnection!.sendspinTextMessages.listen((message) {
        _sendspinMessagesReceived++;
        _lastMessageReceived = DateTime.now();
        if (_sendspinClientSocket != null) {
          _logger.log('RemoteBridge: WebRTC Sendspin text → WS: ${message.substring(0, message.length > 100 ? 100 : message.length)}...');
          _sendspinClientSocket!.add(message);
        }
      });

      // Step 7: Subscribe to Sendspin WebRTC messages (binary audio) to forward to Sendspin client
      _sendspinBinarySubscription = _webrtcConnection!.sendspinBinaryMessages.listen((data) {
        _sendspinMessagesReceived++;
        if (_sendspinClientSocket != null) {
          // Forward binary audio data to Sendspin client
          _sendspinClientSocket!.add(data);
        }
      });

      // Step 8: Start health check timer
      _startHealthCheck();

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
    final path = request.uri.path;
    _logger.log('RemoteBridge: Incoming HTTP request: $path');

    if (WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);

        // Route based on path: /sendspin for audio, anything else for API
        if (path == '/sendspin') {
          _handleSendspinConnection(socket);
        } else {
          _handleApiConnection(socket);
        }
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

  /// Handle a new API WebSocket client connection.
  void _handleApiConnection(WebSocket socket) {
    _logger.log('RemoteBridge: API client connected');

    // Only allow one API client at a time
    if (_apiClientSocket != null) {
      _logger.log('RemoteBridge: Closing existing API client connection');
      _apiClientSubscription?.cancel();
      _apiClientSocket?.close();
    }

    _apiClientSocket = socket;

    // Step 1: Send cached server hello immediately
    if (_cachedServerHello != null) {
      _logger.log('RemoteBridge: Sending cached server hello to API client');
      _apiClientSocket!.add(_cachedServerHello!);
    }

    // Step 2: Forward all messages from API client to WebRTC (ma-api channel)
    _apiClientSubscription = _apiClientSocket!.listen(
      (message) {
        if (message is String && _webrtcConnection != null) {
          _apiMessagesSent++;
          _logger.log('RemoteBridge: API WS → WebRTC: ${message.substring(0, message.length > 100 ? 100 : message.length)}...');
          _webrtcConnection!.sendRaw(message);
        }
      },
      onDone: () {
        _logger.log('RemoteBridge: API client disconnected');
        _apiClientSocket = null;
        _apiClientSubscription = null;
      },
      onError: (error) {
        _logger.log('RemoteBridge: API client error: $error');
        _apiClientSocket = null;
        _apiClientSubscription = null;
      },
    );
  }

  /// Handle a new Sendspin WebSocket client connection (for audio streaming).
  void _handleSendspinConnection(WebSocket socket) {
    _logger.log('RemoteBridge: Sendspin client connected');

    // Only allow one Sendspin client at a time
    if (_sendspinClientSocket != null) {
      _logger.log('RemoteBridge: Closing existing Sendspin client connection');
      _sendspinClientSubscription?.cancel();
      _sendspinClientSocket?.close();
    }

    _sendspinClientSocket = socket;

    // Forward all messages from Sendspin client to WebRTC (sendspin channel)
    _sendspinClientSubscription = _sendspinClientSocket!.listen(
      (message) {
        if (_webrtcConnection != null) {
          _sendspinMessagesSent++;
          if (message is String) {
            // Text message (JSON control)
            _logger.log('RemoteBridge: Sendspin WS text → WebRTC: ${message.substring(0, message.length > 100 ? 100 : message.length)}...');
            _webrtcConnection!.sendSendspinText(message);
          } else if (message is List<int>) {
            // Binary message (would be audio data from client, unlikely but handle it)
            _webrtcConnection!.sendSendspinBinary(Uint8List.fromList(message));
          }
        }
      },
      onDone: () {
        _logger.log('RemoteBridge: Sendspin client disconnected');
        _sendspinClientSocket = null;
        _sendspinClientSubscription = null;
      },
      onError: (error) {
        _logger.log('RemoteBridge: Sendspin client error: $error');
        _sendspinClientSocket = null;
        _sendspinClientSubscription = null;
      },
    );
  }

  /// Handle WebRTC disconnection.
  void _handleWebRTCDisconnection() {
    _logger.log('RemoteBridge: WebRTC disconnected, closing all WS clients');

    // Close API client
    _apiClientSocket?.close();
    _apiClientSocket = null;
    _apiClientSubscription?.cancel();
    _apiClientSubscription = null;

    // Close Sendspin client
    _sendspinClientSocket?.close();
    _sendspinClientSocket = null;
    _sendspinClientSubscription?.cancel();
    _sendspinClientSubscription = null;
  }

  /// Start periodic health check to monitor connection state
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final dcState = _webrtcConnection?.dataChannelStateDebug ?? 'no connection';
      final sendspinState = _webrtcConnection?.isSendspinConnected ?? false;
      final wcState = _webrtcConnection?.state.toString() ?? 'no connection';
      final timeSinceLastMsg = _lastMessageReceived != null
          ? DateTime.now().difference(_lastMessageReceived!).inSeconds
          : -1;
      _logger.log('RemoteBridge: Health check - API DC:$dcState, Sendspin:$sendspinState, WC:$wcState, '
          'API sent:$_apiMessagesSent recv:$_apiMessagesReceived, '
          'Sendspin sent:$_sendspinMessagesSent recv:$_sendspinMessagesReceived, '
          'lastRecv:${timeSinceLastMsg}s ago');
    });
  }

  /// Stop the bridge and disconnect from the remote server.
  Future<void> stop() async {
    _logger.log('RemoteBridge: Stopping bridge');

    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;

    // Cancel API subscriptions
    _apiClientSubscription?.cancel();
    _apiClientSubscription = null;
    _apiWebrtcSubscription?.cancel();
    _apiWebrtcSubscription = null;

    // Cancel Sendspin subscriptions
    _sendspinClientSubscription?.cancel();
    _sendspinClientSubscription = null;
    _sendspinTextSubscription?.cancel();
    _sendspinTextSubscription = null;
    _sendspinBinarySubscription?.cancel();
    _sendspinBinarySubscription = null;

    // Close client sockets
    await _apiClientSocket?.close();
    _apiClientSocket = null;
    await _sendspinClientSocket?.close();
    _sendspinClientSocket = null;

    await _server?.close(force: true);
    _server = null;
    _port = null;

    await _webrtcConnection?.disconnect();
    _webrtcConnection = null;

    _cachedServerHello = null;

    _logger.log('RemoteBridge: Bridge stopped');
  }
}
