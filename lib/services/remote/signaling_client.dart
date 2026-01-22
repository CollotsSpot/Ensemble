import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:ensemble/services/debug_logger.dart';

/// Message types for the MA signaling protocol
class SignalingMessageType {
  static const String ping = 'ping';
  static const String pong = 'pong';
  static const String connectRequest = 'connect-request';
  static const String connected = 'connected';
  static const String offer = 'offer';
  static const String answer = 'answer';
  static const String iceCandidate = 'ice-candidate';
  static const String peerDisconnected = 'peer-disconnected';
  static const String error = 'error';
}

/// ICE server configuration from signaling
class IceServer {
  final String urls;
  final String? username;
  final String? credential;

  IceServer({
    required this.urls,
    this.username,
    this.credential,
  });

  factory IceServer.fromJson(Map<String, dynamic> json) {
    return IceServer(
      urls: json['urls'] as String,
      username: json['username'] as String?,
      credential: json['credential'] as String?,
    );
  }

  Map<String, dynamic> toWebRtcConfig() {
    final config = <String, dynamic>{'urls': urls};
    if (username != null) config['username'] = username;
    if (credential != null) config['credential'] = credential;
    return config;
  }
}

/// Client for connecting to the MA signaling server
class SignalingClient {
  static const String _signalingUrl = 'wss://signaling.music-assistant.io/ws';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;

  String? _sessionId;
  String? _remoteId;
  List<IceServer> _iceServers = [];
  bool _isConnected = false;

  // Callbacks
  Function(String sessionId, List<IceServer> iceServers)? onConnected;
  Function(Map<String, dynamic> answer)? onAnswer;
  Function(Map<String, dynamic> candidate)? onIceCandidate;
  Function(String error)? onError;
  Function()? onPeerDisconnected;
  Function()? onDisconnected;

  String? get sessionId => _sessionId;
  List<IceServer> get iceServers => _iceServers;
  bool get isConnected => _isConnected;

  /// Connect to the signaling server and request connection to a remote MA server
  Future<bool> connect(String remoteId) async {
    DebugLogger().log('Signaling: Connecting to $_signalingUrl');

    try {
      // Normalize remote ID (remove dashes, uppercase)
      final normalizedId = remoteId.replaceAll('-', '').toUpperCase();
      _remoteId = normalizedId;
      DebugLogger().log('Signaling: Remote ID: $normalizedId');

      _channel = WebSocketChannel.connect(Uri.parse(_signalingUrl));
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          DebugLogger().log('Signaling: WebSocket error: $error');
          onError?.call(error.toString());
          _cleanup();
        },
        onDone: () {
          DebugLogger().log('Signaling: WebSocket closed');
          onDisconnected?.call();
          _cleanup();
        },
      );

      // Start ping timer to keep connection alive
      _startPingTimer();

      // Send connect request
      _send({
        'type': SignalingMessageType.connectRequest,
        'remoteId': normalizedId,
      });

      return true;
    } catch (e) {
      DebugLogger().log('Signaling: Failed to connect: $e');
      onError?.call(e.toString());
      return false;
    }
  }

  /// Send WebRTC offer to the remote server
  void sendOffer(Map<String, dynamic> offer) {
    if (_sessionId == null || _remoteId == null) {
      DebugLogger().log('Signaling: Cannot send offer - no session');
      return;
    }

    _send({
      'type': SignalingMessageType.offer,
      'remoteId': _remoteId,
      'sessionId': _sessionId,
      'data': offer,
    });
  }

  /// Send ICE candidate to the remote server
  void sendIceCandidate(Map<String, dynamic> candidate) {
    if (_sessionId == null || _remoteId == null) {
      DebugLogger().log('Signaling: Cannot send ICE candidate - no session');
      return;
    }

    _send({
      'type': SignalingMessageType.iceCandidate,
      'remoteId': _remoteId,
      'sessionId': _sessionId,
      'data': candidate,
    });
  }

  /// Disconnect from the signaling server
  void disconnect() {
    DebugLogger().log('Signaling: Disconnecting');
    _cleanup();
  }

  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final type = message['type'] as String?;

      DebugLogger().log('Signaling: Received message type: $type');

      switch (type) {
        case SignalingMessageType.pong:
          // Ignore pong responses
          break;

        case SignalingMessageType.connected:
          _handleConnected(message);
          break;

        case SignalingMessageType.answer:
          _handleAnswer(message);
          break;

        case SignalingMessageType.iceCandidate:
          _handleIceCandidate(message);
          break;

        case SignalingMessageType.peerDisconnected:
          DebugLogger().log('Signaling: Peer disconnected');
          onPeerDisconnected?.call();
          break;

        case SignalingMessageType.error:
          final error = message['error'] as String? ?? 'Unknown error';
          DebugLogger().log('Signaling: Error from server: $error');
          onError?.call(error);
          break;

        default:
          DebugLogger().log('Signaling: Unknown message type: $type');
      }
    } catch (e) {
      DebugLogger().log('Signaling: Failed to handle message: $e');
    }
  }

  void _handleConnected(Map<String, dynamic> message) {
    _sessionId = message['sessionId'] as String?;
    _isConnected = true;

    // Parse ICE servers
    final iceServersJson = message['iceServers'] as List<dynamic>?;
    if (iceServersJson != null) {
      _iceServers = iceServersJson
          .map((s) => IceServer.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    DebugLogger().log('Signaling: Connected with session $_sessionId');
    DebugLogger().log('Signaling: Received ${_iceServers.length} ICE servers');

    onConnected?.call(_sessionId!, _iceServers);
  }

  void _handleAnswer(Map<String, dynamic> message) {
    final answer = message['data'] as Map<String, dynamic>?;
    if (answer != null) {
      DebugLogger().log('Signaling: Received answer');
      onAnswer?.call(answer);
    }
  }

  void _handleIceCandidate(Map<String, dynamic> message) {
    final candidate = message['data'] as Map<String, dynamic>?;
    if (candidate != null) {
      DebugLogger().log('Signaling: Received ICE candidate');
      onIceCandidate?.call(candidate);
    }
  }

  void _send(Map<String, dynamic> message) {
    if (_channel == null) return;

    final json = jsonEncode(message);
    DebugLogger().log('Signaling: Sending ${message['type']}');
    _channel!.sink.add(json);
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send({'type': SignalingMessageType.ping});
    });
  }

  void _cleanup() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _sessionId = null;
    _remoteId = null;
    _isConnected = false;
  }
}
