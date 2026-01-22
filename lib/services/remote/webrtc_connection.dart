import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:ensemble/services/remote/signaling_client.dart';
import 'package:ensemble/services/debug_logger.dart';

/// WebRTC connection state
enum WebRTCConnectionState {
  disconnected,
  connecting,
  connected,
  failed,
}

/// Manages a WebRTC peer connection for remote MA access
class WebRTCConnection {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final SignalingClient _signalingClient = SignalingClient();
  final _uuid = const Uuid();

  WebRTCConnectionState _state = WebRTCConnectionState.disconnected;
  Completer<bool>? _connectionCompleter;
  bool _serverHelloReceived = false;
  Completer<void>? _serverHelloCompleter;

  // Message handling
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _rawMessageController = StreamController<String>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};

  // Server info
  Map<String, dynamic>? serverInfo;

  // Callbacks
  Function(WebRTCConnectionState state)? onStateChanged;
  Function(String error)? onError;

  WebRTCConnectionState get state => _state;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<String> get rawMessages => _rawMessageController.stream;
  bool get isConnected => _state == WebRTCConnectionState.connected;

  /// Connect to a remote MA server using the Remote Access ID
  Future<bool> connect(String remoteId) async {
    if (_state == WebRTCConnectionState.connecting) {
      DebugLogger().log('WebRTC: Already connecting');
      return false;
    }

    _setState(WebRTCConnectionState.connecting);
    _connectionCompleter = Completer<bool>();

    try {
      // Set up signaling callbacks
      _signalingClient.onConnected = _onSignalingConnected;
      _signalingClient.onAnswer = _onAnswer;
      _signalingClient.onIceCandidate = _onRemoteIceCandidate;
      _signalingClient.onError = _onSignalingError;
      _signalingClient.onPeerDisconnected = _onPeerDisconnected;
      _signalingClient.onDisconnected = _onSignalingDisconnected;

      // Connect to signaling server
      final connected = await _signalingClient.connect(remoteId);
      if (!connected) {
        _setState(WebRTCConnectionState.failed);
        return false;
      }

      // Wait for connection to complete (with timeout)
      final result = await _connectionCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          DebugLogger().log('WebRTC: Connection timeout');
          _onSignalingError('Connection timeout');
          return false;
        },
      );

      return result;
    } catch (e) {
      DebugLogger().log('WebRTC: Connection error: $e');
      _setState(WebRTCConnectionState.failed);
      onError?.call(e.toString());
      return false;
    }
  }

  /// Send a JSON-RPC request and wait for response
  Future<Map<String, dynamic>> sendRequest(
    String command, [
    Map<String, dynamic>? params,
  ]) async {
    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Data channel not open');
    }

    final messageId = _uuid.v4();
    final request = {
      'message_id': messageId,
      'command': command,
      if (params != null) 'args': params,
    };

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[messageId] = completer;

    final jsonStr = jsonEncode(request);
    DebugLogger().log('WebRTC: Sending request: $jsonStr');
    _dataChannel!.send(RTCDataChannelMessage(jsonStr));

    // Timeout after 30 seconds
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(messageId);
        throw TimeoutException('Request timed out: $command');
      },
    );
  }

  /// Send a raw message without waiting for response (for bridge passthrough)
  void sendRaw(String message) {
    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      DebugLogger().log('WebRTC: Cannot send raw - data channel not open');
      return;
    }

    DebugLogger().log('WebRTC: Sending raw: ${message.substring(0, message.length > 100 ? 100 : message.length)}...');
    _dataChannel!.send(RTCDataChannelMessage(message));
  }

  /// Disconnect from the remote server
  Future<void> disconnect() async {
    DebugLogger().log('WebRTC: Disconnecting');

    _signalingClient.disconnect();
    await _dataChannel?.close();
    await _peerConnection?.close();

    _dataChannel = null;
    _peerConnection = null;
    _pendingRequests.clear();
    _serverHelloReceived = false;
    _serverHelloCompleter = null;
    serverInfo = null;

    _setState(WebRTCConnectionState.disconnected);
  }

  void _setState(WebRTCConnectionState newState) {
    if (_state != newState) {
      DebugLogger().log('WebRTC: State changed: $_state -> $newState');
      _state = newState;
      onStateChanged?.call(newState);
    }
  }

  Future<void> _onSignalingConnected(String sessionId, List<IceServer> iceServers) async {
    DebugLogger().log('WebRTC: Signaling connected, creating peer connection');

    try {
      // Create peer connection with ICE servers
      final config = <String, dynamic>{
        'iceServers': iceServers.map((s) => s.toWebRtcConfig()).toList(),
        'sdpSemantics': 'unified-plan',
      };

      DebugLogger().log('WebRTC: ICE servers: ${config['iceServers']}');

      _peerConnection = await createPeerConnection(config);

      // Set up peer connection callbacks
      _peerConnection!.onIceCandidate = _onLocalIceCandidate;
      _peerConnection!.onIceConnectionState = _onIceConnectionState;
      _peerConnection!.onConnectionState = _onConnectionState;
      _peerConnection!.onDataChannel = _onDataChannel;

      // Create data channel for MA API
      final dataChannelInit = RTCDataChannelInit()
        ..ordered = true
        ..protocol = 'ma-api';

      _dataChannel = await _peerConnection!.createDataChannel('ma-api', dataChannelInit);
      _setupDataChannel(_dataChannel!);

      // Create and send offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      DebugLogger().log('WebRTC: Sending offer');
      _signalingClient.sendOffer({
        'type': offer.type,
        'sdp': offer.sdp,
      });
    } catch (e) {
      DebugLogger().log('WebRTC: Failed to create peer connection: $e');
      _onSignalingError(e.toString());
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> answer) async {
    DebugLogger().log('WebRTC: Received answer');

    try {
      final description = RTCSessionDescription(
        answer['sdp'] as String?,
        answer['type'] as String?,
      );
      await _peerConnection?.setRemoteDescription(description);
    } catch (e) {
      DebugLogger().log('WebRTC: Failed to set remote description: $e');
      _onSignalingError(e.toString());
    }
  }

  void _onLocalIceCandidate(RTCIceCandidate candidate) {
    DebugLogger().log('WebRTC: Local ICE candidate: ${candidate.candidate?.substring(0, 50)}...');

    _signalingClient.sendIceCandidate({
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  }

  Future<void> _onRemoteIceCandidate(Map<String, dynamic> candidateData) async {
    DebugLogger().log('WebRTC: Remote ICE candidate received');

    try {
      final candidate = RTCIceCandidate(
        candidateData['candidate'] as String?,
        candidateData['sdpMid'] as String?,
        candidateData['sdpMLineIndex'] as int?,
      );
      await _peerConnection?.addCandidate(candidate);
    } catch (e) {
      DebugLogger().log('WebRTC: Failed to add ICE candidate: $e');
    }
  }

  void _onIceConnectionState(RTCIceConnectionState state) {
    DebugLogger().log('WebRTC: ICE connection state: $state');

    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _onSignalingError('ICE connection failed');
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        DebugLogger().log('WebRTC: ICE disconnected, may recover');
        break;
      default:
        break;
    }
  }

  void _onConnectionState(RTCPeerConnectionState state) {
    DebugLogger().log('WebRTC: Peer connection state: $state');

    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        // Connection established, but wait for data channel
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _onSignalingError('Peer connection failed');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _setState(WebRTCConnectionState.disconnected);
        break;
      default:
        break;
    }
  }

  void _onDataChannel(RTCDataChannel channel) {
    DebugLogger().log('WebRTC: Remote data channel received: ${channel.label}');
    if (channel.label == 'ma-api') {
      _dataChannel = channel;
      _setupDataChannel(channel);
    }
  }

  void _setupDataChannel(RTCDataChannel channel) {
    channel.onDataChannelState = (state) {
      DebugLogger().log('WebRTC: Data channel state: $state');

      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        DebugLogger().log('WebRTC: Data channel open - waiting for server hello...');
        // Don't complete yet - wait for server hello
        _serverHelloCompleter = Completer<void>();
        _serverHelloCompleter!.future.then((_) {
          DebugLogger().log('WebRTC: Server hello received - connection complete!');
          _setState(WebRTCConnectionState.connected);
          _safeCompleteConnection(true);
        });
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        DebugLogger().log('WebRTC: Data channel closed');
        _setState(WebRTCConnectionState.disconnected);
      }
    };

    channel.onMessage = _onDataChannelMessage;
  }

  void _onDataChannelMessage(RTCDataChannelMessage message) {
    try {
      DebugLogger().log('WebRTC: Raw message: ${message.text.substring(0, message.text.length > 200 ? 200 : message.text.length)}...');
      final data = jsonDecode(message.text) as Map<String, dynamic>;
      final messageId = data['message_id']?.toString();

      DebugLogger().log('WebRTC: Parsed message keys: ${data.keys.toList()}, message_id: $messageId');

      // Check for server hello message (has server_id but no message_id)
      if (data.containsKey('server_id') && messageId == null && !_serverHelloReceived) {
        DebugLogger().log('WebRTC: Server hello received - server_version: ${data['server_version']}');
        serverInfo = data;
        _serverHelloReceived = true;
        _serverHelloCompleter?.complete();
        // Don't forward server hello to rawMessages - bridge caches it separately
        return;
      }

      // Check if this is a response to a pending request (for internal use like auth)
      if (messageId != null && _pendingRequests.containsKey(messageId)) {
        DebugLogger().log('WebRTC: Matched pending request $messageId');
        _pendingRequests.remove(messageId)?.complete(data);
        // Don't forward to rawMessages - this was an internal request
        return;
      }

      // Forward all other messages to rawMessages stream (for bridge passthrough)
      _rawMessageController.add(message.text);

      // Also broadcast parsed event/notification for internal listeners
      DebugLogger().log('WebRTC: No match for message_id=$messageId, pending: ${_pendingRequests.keys.toList()}');
      _messageController.add(data);
    } catch (e) {
      DebugLogger().log('WebRTC: Failed to parse message: $e');
    }
  }

  void _onSignalingError(String error) {
    DebugLogger().log('WebRTC: Signaling error: $error');
    _setState(WebRTCConnectionState.failed);
    onError?.call(error);
    _safeCompleteConnection(false);
  }

  void _onPeerDisconnected() {
    DebugLogger().log('WebRTC: Peer disconnected');
    _setState(WebRTCConnectionState.disconnected);
    onError?.call('Remote server disconnected');
  }

  void _onSignalingDisconnected() {
    DebugLogger().log('WebRTC: Signaling disconnected');
    // Only set failed if we were still connecting
    if (_state == WebRTCConnectionState.connecting) {
      _setState(WebRTCConnectionState.failed);
      _safeCompleteConnection(false);
    }
  }

  /// Safely complete the connection completer (only once)
  void _safeCompleteConnection(bool success) {
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      _connectionCompleter!.complete(success);
    }
  }

  void dispose() {
    _messageController.close();
    _rawMessageController.close();
    disconnect();
  }
}
