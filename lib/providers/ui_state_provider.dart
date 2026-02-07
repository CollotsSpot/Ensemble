import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import '../models/provider_instance.dart';

/// Provider for UI-only state that doesn't belong to any specific domain.
///
/// Manages:
/// - Search state (query and results)
/// - Provider and player filters (from MA user settings)
/// - User-controlled provider enable/disable
/// - Loading states
/// - Home refresh counter
///
/// This state is UI-focused and doesn't involve business logic operations.
class UIStateProvider extends ChangeNotifier {
  // Search state
  String _lastSearchQuery = '';
  Map<String, List<MediaItem>> _lastSearchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
  };

  // Provider filter from MA user settings (empty = all providers allowed)
  List<String> _providerFilter = [];

  // Player filter from MA user settings (empty = all players allowed)
  List<String> _playerFilter = [];

  // User-controlled music provider filter (local settings in Ensemble)
  // Empty list means all providers are enabled (no filtering)
  List<String> _enabledProviderIds = [];

  // Available music providers discovered from MA
  List<ProviderInstance> _availableMusicProviders = [];

  // Loading states
  bool _isLoading = false;
  bool _isLoadingRadio = false;
  bool _isLoadingPodcasts = false;

  // Home refresh counter - increments to signal home screen to refresh all rows
  int _homeRefreshCounter = 0;

  // Getters
  String get lastSearchQuery => _lastSearchQuery;
  Map<String, List<MediaItem>> get lastSearchResults => _lastSearchResults;
  List<String> get providerFilter => _providerFilter;
  List<String> get playerFilter => _playerFilter;
  List<String> get enabledProviderIds => _enabledProviderIds;
  List<ProviderInstance> get availableMusicProviders => _availableMusicProviders;
  bool get isLoading => _isLoading;
  bool get isLoadingRadio => _isLoadingRadio;
  bool get isLoadingPodcasts => _isLoadingPodcasts;
  int get homeRefreshCounter => _homeRefreshCounter;

  /// Whether provider filtering is active
  bool get hasProviderFilter => _providerFilter.isNotEmpty;

  /// Whether player filtering is active
  bool get hasPlayerFilter => _playerFilter.isNotEmpty;

  /// Whether user provider filter is active
  bool get hasEnabledProviderFilter => _enabledProviderIds.isNotEmpty;

  // Search state management
  void saveSearchState(String query, Map<String, List<MediaItem>> results) {
    _lastSearchQuery = query;
    _lastSearchResults = results;
    notifyListeners();
  }

  void clearSearchState() {
    _lastSearchQuery = '';
    _lastSearchResults = {'artists': [], 'albums': [], 'tracks': []};
    notifyListeners();
  }

  // Filter management
  void setProviderFilter(List<String> filter) {
    _providerFilter = filter;
    notifyListeners();
  }

  void setPlayerFilter(List<String> filter) {
    _playerFilter = filter;
    notifyListeners();
  }

  void setAvailableMusicProviders(List<ProviderInstance> providers) {
    _availableMusicProviders = providers;
    notifyListeners();
  }

  void setEnabledProviderIds(List<String> enabledIds) {
    _enabledProviderIds = enabledIds;
    notifyListeners();
  }

  /// Toggle a specific music provider on/off
  void toggleProviderEnabled(String instanceId, bool enabled) {
    final allIds = _availableMusicProviders.map((p) => p.instanceId).toList();

    // Don't allow disabling the last provider
    if (!enabled && _enabledProviderIds.isNotEmpty && _enabledProviderIds.length <= 1) {
      return;
    }

    // Update local state
    if (_enabledProviderIds.isEmpty && !enabled) {
      // Switch to explicit mode
      _enabledProviderIds = allIds.where((id) => id != instanceId).toList();
    } else if (enabled) {
      if (!_enabledProviderIds.contains(instanceId)) {
        _enabledProviderIds = [..._enabledProviderIds, instanceId];
      }
    } else {
      _enabledProviderIds = _enabledProviderIds.where((id) => id != instanceId).toList();
    }

    notifyListeners();
  }

  /// Check if a provider should be visible based on both filters
  bool isProviderEnabled(String instanceId) {
    // Check MA user filter (server-side restriction)
    if (hasProviderFilter && !_providerFilter.contains(instanceId)) {
      return false;
    }

    // Check user filter (local preference)
    if (hasEnabledProviderFilter && !_enabledProviderIds.contains(instanceId)) {
      return false;
    }

    return true;
  }

  /// Check if a player should be visible based on MA user filter
  bool isPlayerAllowed(String playerId) {
    if (!hasPlayerFilter) return true;
    return _playerFilter.contains(playerId);
  }

  // Loading state management
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setLoadingRadio(bool loading) {
    _isLoadingRadio = loading;
    notifyListeners();
  }

  void setLoadingPodcasts(bool loading) {
    _isLoadingPodcasts = loading;
    notifyListeners();
  }

  void incrementHomeRefreshCounter() {
    _homeRefreshCounter++;
    notifyListeners();
  }
}
