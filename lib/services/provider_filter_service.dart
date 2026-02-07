import '../models/media_item.dart';
import '../models/player.dart';
import '../models/provider_instance.dart';
import '../services/sync_service.dart';

/// Service for filtering media items and players based on user settings.
///
/// Extracted from MusicAssistantProvider to reduce complexity.
class ProviderFilterService {
  /// Provider filter from MA user settings (empty = all providers allowed)
  final List<String> providerFilter;

  /// Player filter from MA user settings (empty = all players allowed)
  final List<String> playerFilter;

  /// Available music providers discovered from MA
  final List<ProviderInstance> availableMusicProviders;

  /// Library data for provider counting
  final List<dynamic> artists;
  final List<dynamic> albums;
  final List<dynamic> tracks;
  final List<dynamic> podcasts;
  final List<dynamic> radioStations;

  ProviderFilterService({
    required this.providerFilter,
    required this.playerFilter,
    required this.availableMusicProviders,
    required this.artists,
    required this.albums,
    required this.tracks,
    required this.podcasts,
    required this.radioStations,
  });

  // ===========================================================================
  // PROVIDER FILTER (from MA user settings)
  // ===========================================================================

  /// Whether provider filtering is active
  bool get hasProviderFilter => providerFilter.isNotEmpty;

  /// Check if a media item should be visible based on provider filter.
  ///
  /// Returns true if:
  /// - No filter is active (empty list = all providers allowed)
  /// - The item has at least one provider mapping in the allowed list
  /// - The item's primary provider is in the allowed list
  bool isItemAllowedByProviderFilter(MediaItem item) {
    // No filter = show everything
    if (providerFilter.isEmpty) return true;

    // Check if item's provider mappings include any allowed provider
    final mappings = item.providerMappings;
    if (mappings != null && mappings.isNotEmpty) {
      for (final mapping in mappings) {
        if (providerFilter.contains(mapping.providerInstance)) {
          return true;
        }
      }
    }

    // Also check primary provider field (for items without full mappings)
    if (providerFilter.contains(item.provider)) {
      return true;
    }

    return false;
  }

  /// Filter a list of media items based on provider filter.
  List<T> filterByProvider<T extends MediaItem>(List<T> items) {
    if (providerFilter.isEmpty) return items;
    return items.where(isItemAllowedByProviderFilter).toList();
  }

  /// Filter search results map based on provider filter.
  Map<String, List<MediaItem>> filterSearchResults(Map<String, List<MediaItem>> results) {
    if (providerFilter.isEmpty) return results;
    return {
      for (final entry in results.entries)
        entry.key: entry.value.where(isItemAllowedByProviderFilter).toList(),
    };
  }

  // ===========================================================================
  // PLAYER FILTER (from MA user settings)
  // ===========================================================================

  /// Whether player filtering is active
  bool get hasPlayerFilter => playerFilter.isNotEmpty;

  /// Check if a player should be visible based on player filter.
  bool isPlayerAllowedByFilter(Player player) {
    if (playerFilter.isEmpty) return true;
    return playerFilter.contains(player.playerId);
  }

  /// Filter a list of players based on player filter.
  List<Player> filterPlayers(List<Player> players) {
    if (playerFilter.isEmpty) return players;
    return players.where(isPlayerAllowedByFilter).toList();
  }

  // ===========================================================================
  // PROVIDER COUNTING
  // ===========================================================================

  /// Get providers that have content in artists library (with item counts).
  Map<String, int> getProvidersWithArtists() {
    return _getProvidersWithCounts(artists);
  }

  /// Get providers that have content in albums library (with item counts).
  Map<String, int> getProvidersWithAlbums() {
    return _getProvidersWithCounts(albums);
  }

  /// Get providers that have content in tracks library (with item counts).
  Map<String, int> getProvidersWithTracks() {
    return _getProvidersWithCounts(tracks);
  }

  /// Get providers that have content in playlists (with item counts).
  Map<String, int> getProvidersWithPlaylists() {
    return _getProvidersWithCounts(SyncService.instance.cachedPlaylists);
  }

  /// Get providers that have audiobooks (with item counts).
  Map<String, int> getProvidersWithAudiobooks() {
    return _getProvidersWithCounts(SyncService.instance.cachedAudiobooks);
  }

  /// Get providers that have radio stations (with item counts).
  Map<String, int> getProvidersWithRadio() {
    return _getProvidersWithCounts(radioStations);
  }

  /// Get providers that have podcasts (with item counts).
  ///
  /// Only counts mappings where inLibrary is true - this indicates which provider
  /// the user actually added the podcast from (vs providers that can play it).
  Map<String, int> getProvidersWithPodcasts() {
    final counts = <String, int>{};
    for (final item in podcasts) {
      final mappings = (item as MediaItem).providerMappings;
      if (mappings != null) {
        for (final mapping in mappings) {
          // Only count if this provider "owns" the item (user added it from this account)
          if (mapping.inLibrary) {
            final instanceId = mapping.providerInstance;
            if (instanceId.isNotEmpty) {
              counts[instanceId] = (counts[instanceId] ?? 0) + 1;
            }
          }
        }
      }
    }
    return counts;
  }

  /// Internal helper to count items per provider from a list of media items.
  ///
  /// Only counts mappings where inLibrary is true - this indicates which provider
  /// the user actually added the item from (vs providers that can play it).
  Map<String, int> _getProvidersWithCounts(List<dynamic> items) {
    final counts = <String, int>{};
    for (final item in items) {
      if (item is! MediaItem) continue;
      final mediaItem = item as MediaItem;
      final mappings = mediaItem.providerMappings;
      if (mappings != null) {
        for (final mapping in mappings) {
          // Only count if this provider "owns" the item (user added it from this account)
          if (mapping.inLibrary) {
            final instanceId = mapping.providerInstance;
            if (instanceId.isNotEmpty) {
              counts[instanceId] = (counts[instanceId] ?? 0) + 1;
            }
          }
        }
      }
    }
    return counts;
  }

  /// Get ProviderInstance objects for providers that have content in a category.
  ///
  /// Returns list of (ProviderInstance, itemCount) tuples, sorted by name.
  List<(ProviderInstance, int)> getRelevantProvidersForCategory(String category) {
    final Map<String, int> counts;
    switch (category) {
      case 'artists':
        counts = getProvidersWithArtists();
        break;
      case 'albums':
        counts = getProvidersWithAlbums();
        break;
      case 'tracks':
        counts = getProvidersWithTracks();
        break;
      case 'playlists':
        counts = getProvidersWithPlaylists();
        break;
      case 'audiobooks':
        counts = getProvidersWithAudiobooks();
        break;
      case 'radio':
        counts = getProvidersWithRadio();
        break;
      case 'podcasts':
        counts = getProvidersWithPodcasts();
        break;
      default:
        counts = {};
    }

    // Build list of providers that support this category, with their item counts
    // Only include providers that have at least 1 item (hides providers not synced to library)
    // Multiple instances of the same domain are allowed (e.g., two Spotify accounts)
    // but we dedupe if names match exactly (same account re-added with new instance ID)
    final result = <(ProviderInstance, int)>[];
    final addedInstanceIds = <String>{};
    final addedNames = <String, int>{}; // Track name -> count to dedupe same-name providers

    for (final provider in availableMusicProviders) {
      // Only include providers that support this content type AND have items
      if (provider.supportsContentType(category)) {
        final count = counts[provider.instanceId] ?? 0;
        if (count > 0) {
          final existingCount = addedNames[provider.name];
          if (existingCount == null) {
            // First provider with this name
            result.add((provider, count));
            addedInstanceIds.add(provider.instanceId);
            addedNames[provider.name] = count;
          } else if (count > existingCount) {
            // Same name but more items - likely same account re-added, keep better one
            result.removeWhere((r) => r.$1.name == provider.name);
            result.add((provider, count));
            addedInstanceIds.add(provider.instanceId);
            addedNames[provider.name] = count;
          }
        }
      }
    }

    // Also include providers that have items but aren't in availableMusicProviders
    // (e.g., search-only providers like iTunes, or orphaned items from removed providers)
    // For these synthetic providers, dedupe by domain since we don't have account-specific names
    final addedRealDomains = result.map((r) => r.$1.domain).toSet();
    final addedSyntheticDomains = <String>{};

    for (final entry in counts.entries) {
      if (!addedInstanceIds.contains(entry.key) && entry.value > 0) {
        // Create a synthetic ProviderInstance from the instance ID
        // Format is typically "domain--uniqueId" (e.g., "itunes--abc123")
        final instanceId = entry.key;
        final domain = instanceId.contains('--')
            ? instanceId.split('--').first
            : instanceId;

        // Skip if this domain is already represented by a real provider or synthetic
        if (addedRealDomains.contains(domain)) continue;
        if (addedSyntheticDomains.contains(domain)) continue;

        // Only add if this domain supports the category
        final capabilities = ProviderInstance.providerCapabilities[domain];
        if (capabilities != null && capabilities.contains(category)) {
          result.add((
            ProviderInstance(
              instanceId: instanceId,
              domain: domain,
              name: _formatProviderName(domain),
              available: true,
            ),
            entry.value,
          ));
          addedSyntheticDomains.add(domain);
        }
      }
    }

    // Sort by name
    result.sort((a, b) => a.$1.name.compareTo(b.$1.name));
    return result;
  }

  /// Format a provider domain into a readable display name.
  String _formatProviderName(String domain) {
    const names = {
      'spotify': 'Spotify',
      'tidal': 'Tidal',
      'qobuz': 'Qobuz',
      'deezer': 'Deezer',
      'ytmusic': 'YouTube Music',
      'soundcloud': 'SoundCloud',
      'apple_music': 'Apple Music',
      'amazon_music': 'Amazon Music',
      'plex': 'Plex',
      'jellyfin': 'Jellyfin',
      'emby': 'Emby',
      'subsonic': 'Subsonic',
      'opensubsonic': 'OpenSubsonic',
      'gmusic': 'Google Music',
      'bandcamp': 'Bandcamp',
      'youtube': 'YouTube',
      'itunes': 'iTunes/Apple',
      'spotifyfree': 'Spotify Free',
      'tunein': 'TuneIn',
      'radio_net': 'Radio.net',
      'dirble': 'Dirble',
      'freq': 'FREQ',
      'radionomy': 'Radionomy',
    };
    return names[domain] ?? domain.split('_').map((s) => s[0].toUpperCase() + s.substring(1)).join(' ');
  }
}
