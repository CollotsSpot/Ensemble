/// Utility methods for network-related operations.
///
/// Extracted from MusicAssistantProvider to isolate network logic.
class NetworkUtils {
  /// Check if a hostname is a local/private network address.
  ///
  /// Returns true for:
  /// - Private IPv4 ranges (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
  /// - localhost (127.x.x.x)
  /// - .local domains (mDNS/Bonjour)
  /// - .ts.net domains (Tailscale VPN - treat as local since it's a VPN)
  static bool isLocalNetworkHost(String host) {
    return host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.16.') ||
        host.startsWith('172.17.') ||
        host.startsWith('172.18.') ||
        host.startsWith('172.19.') ||
        host.startsWith('172.2') ||
        host.startsWith('172.30.') ||
        host.startsWith('172.31.') ||
        host == 'localhost' ||
        host.startsWith('127.') ||
        host.endsWith('.local') ||
        host.endsWith('.ts.net'); // Tailscale - treat as local since it's a VPN
  }
}
