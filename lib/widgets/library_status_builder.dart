import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../services/library_status_service.dart';

/// A widget that rebuilds when the library/favorite status of an item changes.
///
/// This widget listens to the centralized [LibraryStatusService] and only
/// rebuilds when the status of the specified item changes.
///
/// Example:
/// ```dart
/// LibraryStatusBuilder(
///   itemKey: LibraryStatusService.makeKey('album', album.provider, album.itemId),
///   builder: (context, isInLibrary, isFavorite) {
///     return IconButton(
///       icon: Icon(isInLibrary ? Icons.library_add_check : Icons.library_add),
///       onPressed: () => toggleLibrary(),
///     );
///   },
/// )
/// ```
class LibraryStatusBuilder extends StatefulWidget {
  final String itemKey;
  final Widget Function(BuildContext context, bool isInLibrary, bool isFavorite) builder;

  const LibraryStatusBuilder({
    super.key,
    required this.itemKey,
    required this.builder,
  });

  @override
  State<LibraryStatusBuilder> createState() => _LibraryStatusBuilderState();
}

class _LibraryStatusBuilderState extends State<LibraryStatusBuilder> {
  late bool _isInLibrary;
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _updateStatus();
    LibraryStatusService.instance.addListener(_onStatusChanged);
  }

  @override
  void didUpdateWidget(LibraryStatusBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemKey != widget.itemKey) {
      _updateStatus();
    }
  }

  @override
  void dispose() {
    LibraryStatusService.instance.removeListener(_onStatusChanged);
    super.dispose();
  }

  void _updateStatus() {
    _isInLibrary = LibraryStatusService.instance.isInLibrary(widget.itemKey);
    _isFavorite = LibraryStatusService.instance.isFavorite(widget.itemKey);
  }

  void _onStatusChanged() {
    final newInLibrary = LibraryStatusService.instance.isInLibrary(widget.itemKey);
    final newFavorite = LibraryStatusService.instance.isFavorite(widget.itemKey);

    if (newInLibrary != _isInLibrary || newFavorite != _isFavorite) {
      setState(() {
        _isInLibrary = newInLibrary;
        _isFavorite = newFavorite;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _isInLibrary, _isFavorite);
  }
}

/// Mixin for StatefulWidgets that need to track library/favorite status.
///
/// This provides a simpler API for widgets that already maintain other state.
///
/// Example:
/// ```dart
/// class _MyWidgetState extends State<MyWidget> with LibraryStatusMixin {
///   @override
///   String get libraryItemKey => LibraryStatusService.makeKey('album', widget.album.provider, widget.album.itemId);
///
///   @override
///   Widget build(BuildContext context) {
///     return IconButton(
///       icon: Icon(isInLibrary ? Icons.check : Icons.add),
///       onPressed: toggleLibrary,
///     );
///   }
/// }
/// ```
mixin LibraryStatusMixin<T extends StatefulWidget> on State<T> {
  /// Override to provide the item key
  String get libraryItemKey;

  /// Whether the item is currently in the library
  bool get isInLibrary => LibraryStatusService.instance.isInLibrary(libraryItemKey);

  /// Whether the item is currently a favorite
  bool get isFavorite => LibraryStatusService.instance.isFavorite(libraryItemKey);

  @override
  void initState() {
    super.initState();
    LibraryStatusService.instance.addListener(_onLibraryStatusChanged);
  }

  @override
  void dispose() {
    LibraryStatusService.instance.removeListener(_onLibraryStatusChanged);
    super.dispose();
  }

  void _onLibraryStatusChanged() {
    // Trigger rebuild to pick up new status values
    // Defer setState to avoid calling it during build phase
    if (!mounted) return;

    // Use Future.microtask to defer setState until after the current build phase
    // This prevents "setState during build" errors while avoiding Overlay issues
    Future.microtask(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// Set library status optimistically and return previous value for rollback
  bool setLibraryStatus(bool value) {
    final previous = isInLibrary;
    LibraryStatusService.instance.markLibraryPending(libraryItemKey, previous);
    LibraryStatusService.instance.setLibraryStatus(libraryItemKey, value);
    return previous;
  }

  /// Set favorite status optimistically and return previous value for rollback
  bool setFavoriteStatus(bool value) {
    final previous = isFavorite;
    LibraryStatusService.instance.markFavoritePending(libraryItemKey, previous);
    LibraryStatusService.instance.setFavoriteStatus(libraryItemKey, value);
    return previous;
  }

  /// Complete a successful library operation
  void completeLibraryOperation() {
    LibraryStatusService.instance.completeLibraryOperation(libraryItemKey);
  }

  /// Complete a successful favorite operation
  void completeFavoriteOperation() {
    LibraryStatusService.instance.completeFavoriteOperation(libraryItemKey);
  }

  /// Rollback a failed library operation
  void rollbackLibraryOperation() {
    LibraryStatusService.instance.rollbackLibraryOperation(libraryItemKey);
  }

  /// Rollback a failed favorite operation
  void rollbackFavoriteOperation() {
    LibraryStatusService.instance.rollbackFavoriteOperation(libraryItemKey);
  }
}
