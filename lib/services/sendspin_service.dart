import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'debug_logger.dart';
import 'settings_service.dart';
import 'device_id_service.dart';

/// Connection state for Sendspin player
enum SendspinConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Callback types for Sendspin events
typedef SendspinPlayCallback = void Function(String streamUrl, Map<String, dynamic> trackInfo);
typedef SendspinPauseCallback = void Function();
typedef SendspinStopCallback = void Function();
typedef SendspinSeekCallback = void Function(int positionSeconds);
typedef SendspinVolumeCallback = void Function(int volumeLevel);
typedef SendspinAudioDataCallback = void Function(Uint8List audioData);
typedef SendspinStreamStartCallback = void Function(Map<String, dynamic>? trackInfo);
typedef SendspinStreamEndCallback = void Function();

/// Service to manage Sendspin WebSocket connection for local playback
/// Sendspin is the replacement for builtin_player in MA 2.7.0b20+
///
/// Connection strategy (smart fallback for external access):
/// 1. If server is HTTPS, try external wss://{server}/sendspin first
/// 2. Fall back to local_ws_url from API (ws://local-ip:8927/sendspin)
/// 3. WebRTC fallback as last resort (requires TURN servers)
class SendspinService {
  final String serverUrl;
  final _logger = DebugLogger();

  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  // Connection state
  SendspinConnectionState _state = SendspinConnectionState.disconnected;
  SendspinConnectionState get state => _state;

  final _stateController = StreamController<SendspinConnectionState>.broadcast();
  Stream<SendspinConnectionState> get stateStream => _stateController.stream;

  // Player info
  String? _playerId;
  String? _playerName;
  String? _connectedUrl;

  String? get playerId => _playerId;
  String? get playerName => _playerName;

  // Event callbacks
  SendspinPlayCallback? onPlay;
  SendspinPauseCallback? onPause;
  SendspinStopCallback? onStop;
  SendspinSeekCallback? onSeek;
  SendspinVolumeCallback? onVolume;
  SendspinAudioDataCallback? onAudioData;
  SendspinStreamStartCallback? onStreamStart;
  SendspinStreamEndCallback? onStreamEnd;

  // Audio data stream for raw PCM frames
  final _audioDataController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get audioDataStream => _audioDataController.stream;

  // Track audio streaming state
  bool _isStreamingAudio = false;
  int _audioFramesReceived = 0;

  // Player state for reporting to server
  bool _isPowered = true;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _position = 0;
  int _volume = 100;
  bool _isMuted = false;

  bool _isDisposed = false;

  // Auth token for proxy authentication (MA 2.7.1+)
  String? _authToken;

  // Connection deduplication guard - prevents multiple concurrent auth attempts
  Completer<bool>? _connectionInProgress;

  SendspinService(this.serverUrl);

  /// Set the MA auth token for proxy authentication
  void setAuthToken(String? token) {
    _authToken = token;
  }

  /// Initialize and connect to Sendspin server
  /// Uses persistent player ID and username-based naming
  Future<bool> connect() async {
    if (_isDisposed) return false;
    if (_state == SendspinConnectionState.connected) return true;

    // Deduplicate concurrent connection attempts
    if (_connectionInProgress != null) {
      _logger.log('Sendspin: Connection already in progress, waiting...');
      return _connectionInProgress!.future;
    }
    _connectionInProgress = Completer<bool>();

    _updateState(SendspinConnectionState.connecting);

    try {
      // Get persistent player ID and name
      _playerId = await DeviceIdService.getOrCreateDevicePlayerId();
      _playerName = await SettingsService.getLocalPlayerName();

      _logger.log('Sendspin: Connecting as "$_playerName" (ID: $_playerId)');

      // Try connection strategies in order
      bool connected = false;

      // Strategy 1: If server is HTTPS, try external wss:// first
      // Use proxy auth for MA 2.7.1+ - the proxy requires authentication before hello
      if (_isHttpsServer()) {
        final externalUrl = _buildExternalSendspinUrl();
        _logger.log('Sendspin: Trying external URL: $externalUrl');
        connected = await _tryConnect(externalUrl, timeout: const Duration(seconds: 5), useProxyAuth: true);
      }

      // Note: Local network connections (ws://ip:8927/sendspin) are handled
      // by the provider calling connectWithUrl() directly, not by this method.

      if (!connected) {
        _logger.log('Sendspin: External proxy connection failed');
        _updateState(SendspinConnectionState.error);
        _connectionInProgress?.complete(false);
        _connectionInProgress = null;
        return false;
      }

      _connectionInProgress?.complete(true);
      _connectionInProgress = null;
      return true;
    } catch (e) {
      _logger.log('Sendspin: Connection error: $e');
      _updateState(SendspinConnectionState.error);
      _connectionInProgress?.complete(false);
      _connectionInProgress = null;
      return false;
    }
  }

  /// Connect with a specific WebSocket URL (called by provider with local_ws_url)
  /// If useProxyAuth is true, will authenticate with MA token (needed for proxy connections)
  Future<bool> connectWithUrl(String wsUrl, {bool useProxyAuth = false}) async {
    if (_isDisposed) return false;
    if (_state == SendspinConnectionState.connected) return true;

    // Deduplicate concurrent connection attempts
    if (_connectionInProgress != null) {
      _logger.log('Sendspin: Connection already in progress, waiting...');
      return _connectionInProgress!.future;
    }
    _connectionInProgress = Completer<bool>();

    _updateState(SendspinConnectionState.connecting);

    try {
      _playerId = await DeviceIdService.getOrCreateDevicePlayerId();
      _playerName = await SettingsService.getLocalPlayerName();

      _logger.log('Sendspin: Connecting with URL: $wsUrl');

      final connected = await _tryConnect(wsUrl, timeout: const Duration(seconds: 5), useProxyAuth: useProxyAuth);

      if (!connected) {
        _updateState(SendspinConnectionState.error);
        _connectionInProgress?.complete(false);
        _connectionInProgress = null;
        return false;
      }

      _connectionInProgress?.complete(true);
      _connectionInProgress = null;
      return true;
    } catch (e) {
      _logger.log('Sendspin: Connection error: $e');
      _updateState(SendspinConnectionState.error);
      _connectionInProgress?.complete(false);
      _connectionInProgress = null;
      return false;
    }
  }

  /// Attempt to connect to a specific WebSocket URL
  /// If useProxyAuth is true and we have an auth token, authenticate first (for MA 2.7.1+ proxy)
  Future<bool> _tryConnect(String url, {Duration timeout = const Duration(seconds: 5), bool useProxyAuth = false}) async {
    try {
      // Connect to the base URL without query params - we send player info in hello message
      _logger.log('Sendspin: Connecting to $url${useProxyAuth ? ' (with proxy auth)' : ''}');

      // Create WebSocket connection
      final webSocket = await WebSocket.connect(url).timeout(timeout);

      _channel = IOWebSocketChannel(webSocket);
      _connectedUrl = url;

      // Set up message listener BEFORE sending hello
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      // If using proxy auth (MA 2.7.1+), authenticate first
      if (useProxyAuth && _authToken != null) {
        _logger.log('Sendspin: Sending proxy auth with token');
        _sendMessage({
          'type': 'auth',
          'token': _authToken,
        }, allowDuringHandshake: true);

        // Wait for auth_ok response
        final authOk = await _waitForAuth().timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );

        if (!authOk) {
          _logger.log('Sendspin: Proxy authentication failed or timed out');
          await _channel?.sink.close();
          _channel = null;
          return false;
        }
        _logger.log('Sendspin: Proxy auth successful, proceeding with hello');
      }

      // Send client/hello message immediately after connecting
      // This is required by the Sendspin protocol - server waits for this
      // Message format follows aiosendspin protocol spec
      _logger.log('Sendspin: Sending client/hello with player_id=$_playerId');
      _sendMessage({
        'type': 'client/hello',
        'payload': {
          'client_id': _playerId,
          'name': _playerName,
          'version': 1,  // Protocol version (integer)
          'supported_roles': ['player@v1'],
          'player_support': {
            'supported_formats': [
              {
                'codec': 'pcm',
                'channels': 2,
                'sample_rate': 48000,
                'bit_depth': 16,
              },
            ],
            'buffer_capacity': 1048576,  // 1MB buffer
            'supported_commands': ['volume', 'mute'],
          },
        },
      }, allowDuringHandshake: true);

      // Wait for server acknowledgment (server sends welcome/registered after hello)
      final ackReceived = await _waitForAck().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );

      if (!ackReceived) {
        _logger.log('Sendspin: No acknowledgment from server after hello');
        await _channel?.sink.close();
        _channel = null;
        return false;
      }

      _logger.log('Sendspin: Connected and registered successfully');
      _updateState(SendspinConnectionState.connected);
      _startHeartbeat();

      return true;
    } catch (e) {
      _logger.log('Sendspin: Connection attempt failed: $e');
      return false;
    }
  }

  /// Wait for server acknowledgment after connection
  Completer<bool>? _ackCompleter;
  Completer<bool>? _authCompleter;

  Future<bool> _waitForAck() async {
    _ackCompleter = Completer<bool>();
    return _ackCompleter!.future;
  }

  Future<bool> _waitForAuth() async {
    _authCompleter = Completer<bool>();
    return _authCompleter!.future;
  }

  /// Handle incoming WebSocket messages
  /// WebSocket can send text frames (JSON control messages) or binary frames (PCM audio data)
  void _handleMessage(dynamic message) {
    // Check if this is binary audio data (Uint8List) or text (String)
    if (message is List<int>) {
      _handleBinaryAudioData(Uint8List.fromList(message));
      return;
    }

    // Handle text messages (JSON)
    if (message is! String) {
      _logger.log('Sendspin: Unexpected message type: ${message.runtimeType}');
      return;
    }

    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;

      _logger.log('Sendspin: Received message type: $type');

      switch (type) {
        case 'server/hello':
          // Server acknowledged our client/hello - we're registered!
          _logger.log('Sendspin: Received server/hello - connection successful');
          final payload = data['payload'] as Map<String, dynamic>?;
          if (payload != null) {
            _logger.log('Sendspin: Server name: ${payload['name']}, version: ${payload['version']}');
            _logger.log('Sendspin: Active roles: ${payload['active_roles']}');
          }
          if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
            _ackCompleter!.complete(true);
          }
          // Send initial client/state immediately after handshake (required by spec)
          // Note: These must use allowDuringHandshake since state is still 'connecting'
          _sendInitialState();
          // Also send initial time sync
          _sendClientTime(allowDuringHandshake: true);
          break;

        case 'server/time':
          // Server responded to our time sync - can be used to calculate clock offset
          // For now, just log it (proper sync would use Kalman filter)
          _logger.log('Sendspin: Received server/time response');
          break;

        case 'group/update':
          // Group state update - store for reference but no response needed
          _logger.log('Sendspin: Received group/update');
          final groupPayload = data['payload'] as Map<String, dynamic>?;
          if (groupPayload != null) {
            _logger.log('Sendspin: Group state: ${groupPayload['playback_state']}');
          }
          break;

        case 'stream/start':
          // Server is starting to send audio data
          _logger.log('Sendspin: Audio stream starting');
          _isStreamingAudio = true;
          _audioFramesReceived = 0;
          _isPlaying = true;
          _isPaused = false;
          // Notify provider to start PCM player and foreground service
          final streamPayload = data['payload'] as Map<String, dynamic>?;
          onStreamStart?.call(streamPayload);
          break;

        case 'stream/end':
          // Server finished sending audio data
          _logger.log('Sendspin: Audio stream ended (received $_audioFramesReceived frames)');
          _isStreamingAudio = false;
          _isPlaying = false;
          // Notify provider to stop PCM player
          onStreamEnd?.call();
          break;

        case 'auth_ok':
          // Proxy authentication successful (MA 2.7.1+)
          _logger.log('Sendspin: Proxy authentication successful');
          if (_authCompleter != null && !_authCompleter!.isCompleted) {
            _authCompleter!.complete(true);
          }
          break;

        case 'ack':
        case 'connected':
        case 'registered':
          // Legacy/fallback acknowledgment types
          if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
            _ackCompleter!.complete(true);
          }
          break;

        case 'play':
          // Server wants us to play audio (URL-based, not raw PCM)
          final streamUrl = data['url'] as String?;
          final trackInfo = data['track'] as Map<String, dynamic>? ?? {};
          if (streamUrl != null && onPlay != null) {
            _isPlaying = true;
            _isPaused = false;
            onPlay!(streamUrl, trackInfo);
          }
          break;

        case 'pause':
          _isPaused = true;
          _isPlaying = false;
          onPause?.call();
          break;

        case 'stop':
          _isPlaying = false;
          _isPaused = false;
          _isStreamingAudio = false;
          onStop?.call();
          break;

        case 'seek':
          final position = data['position'] as int?;
          if (position != null) {
            _position = position;
            onSeek?.call(position);
          }
          break;

        case 'volume':
          final level = data['level'] as int?;
          if (level != null) {
            _volume = level;
            onVolume?.call(level);
          }
          break;

        case 'ping':
          // Respond to server ping
          _sendMessage({'type': 'pong'});
          break;

        case 'error':
          final errorMsg = data['message'] as String?;
          _logger.log('Sendspin: Server error: $errorMsg');
          break;

        default:
          _logger.log('Sendspin: Unknown message type: $type');
      }
    } catch (e) {
      _logger.log('Sendspin: Error handling JSON message: $e');
    }
  }

  /// Handle binary audio data (PCM frames from server)
  /// Sendspin binary frame format:
  /// - Byte 0: message type (uint8) - Type 4 = audio data
  /// - Bytes 1-8: timestamp (int64 microseconds, little-endian) for synchronization
  /// - Bytes 9+: actual PCM audio data (16-bit stereo 48kHz)
  void _handleBinaryAudioData(Uint8List frame) {
    // Minimum frame size: 1 (type) + 8 (timestamp) + 2 (at least one sample)
    if (frame.length < 11) {
      _logger.log('Sendspin: Binary frame too short: ${frame.length} bytes');
      return;
    }

    // Parse header
    final messageType = frame[0];

    // Type 4 = audio data, other types may be used for other purposes
    if (messageType != 4) {
      _logger.log('Sendspin: Unexpected binary message type: $messageType');
      return;
    }

    // Extract timestamp (bytes 1-8, little-endian int64)
    final timestampBytes = ByteData.sublistView(frame, 1, 9);
    final timestamp = timestampBytes.getInt64(0, Endian.little);

    // Extract actual PCM audio data (everything after the 9-byte header)
    final audioData = Uint8List.sublistView(frame, 9);

    _audioFramesReceived++;

    // Log periodically to avoid spam
    if (_audioFramesReceived == 1) {
      _logger.log('Sendspin: Receiving audio data (first frame: ${frame.length} bytes, audio: ${audioData.length} bytes, ts: $timestamp)');
    } else if (_audioFramesReceived % 100 == 0) {
      _logger.log('Sendspin: Received $_audioFramesReceived audio frames');
    }

    // Emit only the PCM audio data (without header) to stream for consumers
    if (!_audioDataController.isClosed) {
      _audioDataController.add(audioData);
    }

    // Call callback if registered
    onAudioData?.call(audioData);
  }

  /// Handle WebSocket errors
  void _handleError(dynamic error) {
    _logger.log('Sendspin: WebSocket error: $error');
    _updateState(SendspinConnectionState.error);
    _scheduleReconnect();
  }

  /// Handle WebSocket close
  void _handleDone() {
    _logger.log('Sendspin: WebSocket closed');
    _updateState(SendspinConnectionState.disconnected);
    _scheduleReconnect();
  }

  /// Send a JSON message to the server
  /// allowDuringHandshake: set to true to send messages before connection is established (e.g., hello)
  void _sendMessage(Map<String, dynamic> message, {bool allowDuringHandshake = false}) {
    if (_channel == null) return;

    // During handshake, we need to send hello even though state is still 'connecting'
    if (!allowDuringHandshake && _state != SendspinConnectionState.connected) return;

    try {
      final json = jsonEncode(message);
      _logger.log('Sendspin: Sending message: ${message['type']}');
      _channel!.sink.add(json);
    } catch (e) {
      _logger.log('Sendspin: Error sending message: $e');
    }
  }

  /// Report current player state to server
  /// Uses Sendspin protocol 'client/state' message format
  void reportState({
    bool? powered,
    bool? playing,
    bool? paused,
    int? position,
    int? volume,
    bool? muted,
  }) {
    if (powered != null) _isPowered = powered;
    if (playing != null) _isPlaying = playing;
    if (paused != null) _isPaused = paused;
    if (position != null) _position = position;
    if (volume != null) _volume = volume;
    if (muted != null) _isMuted = muted;

    // Determine player state for Sendspin protocol
    // Valid values: 'synchronized', 'error', 'external_source'
    // When connected, we're always synchronized (ready to receive audio)
    const playerState = 'synchronized';

    _sendMessage({
      'type': 'client/state',
      'payload': {
        'player': {
          'state': playerState,
          'volume': _volume,
          'muted': _isMuted,
          'position': _position,
        },
      },
    });
  }

  /// Check if server URL is HTTPS
  bool _isHttpsServer() {
    return serverUrl.startsWith('https://') ||
           serverUrl.startsWith('wss://') ||
           (!serverUrl.contains('://') && !serverUrl.contains(':'));
  }

  /// Build external Sendspin WebSocket URL from server URL
  String _buildExternalSendspinUrl() {
    var url = serverUrl;

    // Convert HTTP(S) to WS(S)
    if (url.startsWith('https://')) {
      url = 'wss://${url.substring(8)}';
    } else if (url.startsWith('http://')) {
      url = 'ws://${url.substring(7)}';
    } else if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      url = 'wss://$url';
    }

    // Remove trailing slash and add /sendspin path
    url = url.replaceAll(RegExp(r'/+$'), '');

    // Remove any existing path and add /sendspin
    final uri = Uri.parse(url);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/sendspin',
    ).toString();
  }

  /// Start heartbeat timer using Sendspin's client/time for clock synchronization
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendClientTime();
    });
  }

  /// Send client/time message for clock synchronization (Sendspin protocol)
  void _sendClientTime({bool allowDuringHandshake = false}) {
    final timestampMicroseconds = DateTime.now().microsecondsSinceEpoch;
    _sendMessage({
      'type': 'client/time',
      'payload': {
        'client_transmitted': timestampMicroseconds,
      },
    }, allowDuringHandshake: allowDuringHandshake);
  }

  /// Send initial client/state immediately after handshake (required by Sendspin spec)
  /// Must use allowDuringHandshake since state is still 'connecting' at this point
  void _sendInitialState() {
    _logger.log('Sendspin: Sending initial client/state');
    _sendMessage({
      'type': 'client/state',
      'payload': {
        'player': {
          'state': 'synchronized',
          'volume': _volume,
          'muted': _isMuted,
          'position': _position,
        },
      },
    }, allowDuringHandshake: true);
  }

  /// Stop heartbeat timer
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_isDisposed) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isDisposed && _state != SendspinConnectionState.connected) {
        _logger.log('Sendspin: Attempting reconnection...');
        if (_connectedUrl != null) {
          connectWithUrl(_connectedUrl!);
        }
      }
    });
  }

  /// Update connection state
  void _updateState(SendspinConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Disconnect from server using Sendspin's client/goodbye message
  Future<void> disconnect() async {
    _stopHeartbeat();
    _reconnectTimer?.cancel();

    if (_channel != null) {
      // Send graceful goodbye per Sendspin protocol
      _sendMessage({
        'type': 'client/goodbye',
        'payload': {
          'reason': 'user_request',
        },
      });
      await _channel!.sink.close();
      _channel = null;
    }

    _updateState(SendspinConnectionState.disconnected);
  }

  /// Dispose the service
  void dispose() {
    _isDisposed = true;
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _stateController.close();
    _audioDataController.close();
  }
}
