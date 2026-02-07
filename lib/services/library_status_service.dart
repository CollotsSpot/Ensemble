import 'dart:async';
import 'package:flutter/foundation.dart';

/// Centralized service for tracking library and favorite status of media items.
///
/// This service implements the "single source of truth" pattern:
/// - All widgets query this service instead of maintaining local state
/// - Status changes notify all listeners immediately (optimistic updates)
/// - API failures trigger rollback notifications
///
/// Usage:
/// ```dart
/// // Check status
/// final isInLibrary = LibraryStatusService.instance.isInLibrary(itemKey);
///
/// // Listen to changes
/// LibraryStatusService.instance.addListener(() {
///   // Rebuild UI
/// });
///
/// // Update status (optimistically)
/// LibraryStatusService.instance.setLibraryStatus(itemKey, true);
/// ```
class LibraryStatusService extends ChangeNotifier {
  LibraryStatusService._();
  static final LibraryStatusService instance = LibraryStatusService._();

  // Status maps: itemKey -> status
  // itemKey format: "mediaType:provider:itemId" for uniqueness
  final Map<String, bool> _libraryStatus = {};
  final Map<String, bool> _favoriteStatus = {};

  // Pending operations for rollback on failure
  final Map<String, bool> _pendingLibraryOps = {};
  final Map<String, bool> _pendingFavoriteOps = {};

  /// Generate a unique key for an item
  static String makeKey(String mediaType, String provider, String itemId) {
    return '$mediaType:$provider:$itemId';
  }

  /// Check if item is in library
  bool isInLibrary(String key) => _libraryStatus[key] ?? false;

  /// Check if item is favorite
  bool isFavorite(String key) => _favoriteStatus[key] ?? false;

  /// Set library status (optimistic update)
  /// Call this immediately when user taps the button
  void setLibraryStatus(String key, bool inLibrary) {
    if (_libraryStatus[key] == inLibrary) return;

    _libraryStatus[key] = inLibrary;
    notifyListeners();
  }

  /// Set favorite status (optimistic update)
  void setFavoriteStatus(String key, bool favorite) {
    if (_favoriteStatus[key] == favorite) return;

    _favoriteStatus[key] = favorite;
    notifyListeners();
  }

  /// Initialize library status without notifying listeners.
  /// Use during initState to sync service from widget data without triggering rebuilds.
  void initLibraryStatus(String key, bool inLibrary) {
    _libraryStatus[key] ??= inLibrary;
  }

  /// Initialize favorite status without notifying listeners.
  /// Use during initState to sync service from widget data without triggering rebuilds.
  void initFavoriteStatus(String key, bool favorite) {
    _favoriteStatus[key] ??= favorite;
  }

  /// Mark operation as pending (for rollback tracking)
  void markLibraryPending(String key, bool previousValue) {
    _pendingLibraryOps[key] = previousValue;
  }

  void markFavoritePending(String key, bool previousValue) {
    _pendingFavoriteOps[key] = previousValue;
  }

  /// Complete operation successfully (clear pending)
  void completeLibraryOperation(String key) {
    _pendingLibraryOps.remove(key);
  }

  void completeFavoriteOperation(String key) {
    _pendingFavoriteOps.remove(key);
  }

  /// Rollback operation on failure
  void rollbackLibraryOperation(String key) {
    final previousValue = _pendingLibraryOps.remove(key);
    if (previousValue != null) {
      _libraryStatus[key] = previousValue;
      notifyListeners();
    }
  }

  void rollbackFavoriteOperation(String key) {
    final previousValue = _pendingFavoriteOps.remove(key);
    if (previousValue != null) {
      _favoriteStatus[key] = previousValue;
      notifyListeners();
    }
  }

  /// Bulk update from provider's library data
  /// Called when library is loaded/refreshed
  void syncFromLibrary({
    required String mediaType,
    required List<dynamic> items,
    required bool Function(dynamic item) getInLibrary,
    required bool Function(dynamic item) getFavorite,
    required String Function(dynamic item) getProvider,
    required String Function(dynamic item) getItemId,
  }) {
    bool changed = false;

    for (final item in items) {
      final key = makeKey(mediaType, getProvider(item), getItemId(item));
      final inLibrary = getInLibrary(item);
      final favorite = getFavorite(item);

      // Only update if not pending (don't overwrite optimistic updates)
      if (!_pendingLibraryOps.containsKey(key)) {
        if (_libraryStatus[key] != inLibrary) {
          _libraryStatus[key] = inLibrary;
          changed = true;
        }
      }

      if (!_pendingFavoriteOps.containsKey(key)) {
        if (_favoriteStatus[key] != favorite) {
          _favoriteStatus[key] = favorite;
          changed = true;
        }
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Update a single item's status from fresh data
  void syncSingleItem({
    required String key,
    required bool inLibrary,
    required bool favorite,
  }) {
    bool changed = false;

    if (!_pendingLibraryOps.containsKey(key) && _libraryStatus[key] != inLibrary) {
      _libraryStatus[key] = inLibrary;
      changed = true;
    }

    if (!_pendingFavoriteOps.containsKey(key) && _favoriteStatus[key] != favorite) {
      _favoriteStatus[key] = favorite;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Clear all status (on logout/disconnect)
  void clear() {
    _libraryStatus.clear();
    _favoriteStatus.clear();
    _pendingLibraryOps.clear();
    _pendingFavoriteOps.clear();
    notifyListeners();
  }

  /// Get debug info
  Map<String, dynamic> get debugInfo => {
    'libraryCount': _libraryStatus.length,
    'favoriteCount': _favoriteStatus.length,
    'pendingLibrary': _pendingLibraryOps.length,
    'pendingFavorite': _pendingFavoriteOps.length,
  };
}
