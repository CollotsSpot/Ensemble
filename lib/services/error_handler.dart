import 'debug_logger.dart';

/// Error types for user-friendly messages
enum ErrorType {
  connection,
  authentication,
  network,
  playback,
  library,
  remote,       // Remote connection (WebRTC) errors
  dataChannel,  // WebRTC data channel errors
  signaling,    // WebRTC signaling server errors
  unknown,
}

class ErrorInfo {
  final ErrorType type;
  final String userMessage;
  final String technicalMessage;
  final bool canRetry;

  ErrorInfo({
    required this.type,
    required this.userMessage,
    required this.technicalMessage,
    this.canRetry = true,
  });
}

class ErrorHandler {
  static final _logger = DebugLogger();

  /// Convert technical errors into user-friendly error messages
  static ErrorInfo handleError(dynamic error, {String context = ''}) {
    _logger.log('❌ Error in $context: $error');

    final errorStr = error.toString().toLowerCase();

    // Connection errors
    if (errorStr.contains('not connected') ||
        errorStr.contains('disconnected') ||
        errorStr.contains('connection closed')) {
      return ErrorInfo(
        type: ErrorType.connection,
        userMessage: 'Not connected to Music Assistant',
        technicalMessage: error.toString(),
        canRetry: true,
      );
    }

    // Network errors
    if (errorStr.contains('socket') ||
        errorStr.contains('network') ||
        errorStr.contains('timeout') ||
        errorStr.contains('failed host lookup')) {
      return ErrorInfo(
        type: ErrorType.network,
        userMessage: 'Network connection failed. Please check your connection.',
        technicalMessage: error.toString(),
        canRetry: true,
      );
    }

    // Authentication errors
    if (errorStr.contains('401') ||
        errorStr.contains('unauthorized') ||
        errorStr.contains('authentication') ||
        errorStr.contains('auth')) {
      return ErrorInfo(
        type: ErrorType.authentication,
        userMessage: 'Authentication failed. Please check your credentials.',
        technicalMessage: error.toString(),
        canRetry: false,
      );
    }

    // Unavailable content errors - these won't resolve with retry
    if (errorStr.contains('no playable') ||
        errorStr.contains('lack available providers') ||
        errorStr.contains('no available providers')) {
      return ErrorInfo(
        type: ErrorType.playback,
        userMessage: 'These tracks are unavailable. The music provider may not have them available for streaming.',
        technicalMessage: error.toString(),
        canRetry: false,
      );
    }

    // Playback errors
    if (errorStr.contains('queue') ||
        errorStr.contains('player') ||
        errorStr.contains('track')) {
      return ErrorInfo(
        type: ErrorType.playback,
        userMessage: 'Playback failed. Please try again.',
        technicalMessage: error.toString(),
        canRetry: true,
      );
    }

    // Library/content errors
    if (errorStr.contains('library') ||
        errorStr.contains('not found') ||
        errorStr.contains('no result')) {
      return ErrorInfo(
        type: ErrorType.library,
        userMessage: 'Failed to load content. Please try again.',
        technicalMessage: error.toString(),
        canRetry: true,
      );
    }

    // WebRTC/Remote connection errors
    if (errorStr.contains('webrtc') ||
        errorStr.contains('remote peer') ||
        errorStr.contains('remote server disconnected')) {
      return ErrorInfo(
        type: ErrorType.remote,
        userMessage: 'Remote connection lost. Attempting to reconnect...',
        technicalMessage: error.toString(),
        canRetry: true,
      );
    }

    // Data channel errors
    if (errorStr.contains('data channel') ||
        errorStr.contains('datachannel')) {
      return ErrorInfo(
        type: ErrorType.dataChannel,
        userMessage: 'Remote data connection failed. Please try reconnecting.',
        technicalMessage: error.toString(),
        canRetry: true,
      );
    }

    // Signaling errors
    if (errorStr.contains('signaling') ||
        errorStr.contains('ice') ||
        errorStr.contains('peer connection failed')) {
      return ErrorInfo(
        type: ErrorType.signaling,
        userMessage: 'Failed to establish remote connection. Please try again.',
        technicalMessage: error.toString(),
        canRetry: true,
      );
    }

    // Unknown errors
    return ErrorInfo(
      type: ErrorType.unknown,
      userMessage: 'An unexpected error occurred. Please try again.',
      technicalMessage: error.toString(),
      canRetry: true,
    );
  }

  /// Get user-friendly message for specific operations
  static String getOperationErrorMessage(String operation, dynamic error) {
    final errorInfo = handleError(error, context: operation);
    return errorInfo.userMessage;
  }

  /// Check if error is retryable
  static bool isRetryable(dynamic error) {
    final errorInfo = handleError(error);
    return errorInfo.canRetry;
  }

  /// Log error with context
  static void logError(String context, dynamic error, {StackTrace? stackTrace}) {
    _logger.log('❌ [$context] $error');
    if (stackTrace != null) {
      _logger.log('Stack trace: $stackTrace');
    }
  }
}
