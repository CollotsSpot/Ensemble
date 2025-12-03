/// Network constants for ports and URLs
class NetworkConstants {
  NetworkConstants._();

  /// Default Music Assistant WebSocket port (used for non-proxied connections)
  static const int defaultWsPort = 8095;

  /// Default HTTPS port (implicit, not usually specified in URLs)
  static const int defaultHttpsPort = 443;

  /// Default HTTP port
  static const int defaultHttpPort = 80;
}
