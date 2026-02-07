import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/music_assistant_provider.dart';
import '../../models/player.dart';
import '../../theme/design_tokens.dart';
import '../../utils/duration_formatter.dart';
import '../common/empty_state.dart';
import '../global_player_overlay.dart';

/// Panel that displays the current playback queue with drag-to-reorder
/// and swipe-left-to-delete functionality.
///
/// Uses custom AnimatedList implementation instead of great_list_view
/// to avoid grey screen bugs (ReorderableListView) and drag duplication bugs (great_list_view).
class QueuePanel extends StatefulWidget {
  final MusicAssistantProvider maProvider;
  final PlayerQueue? queue;
  final bool isLoading;
  final Color textColor;
  final Color primaryColor;
  final Color backgroundColor;
  final double topPadding;
  final VoidCallback onClose;
  final VoidCallback onRefresh;
  final ValueChanged<bool>? onDraggingChanged;
  final VoidCallback? onSwipeStart;
  final ValueChanged<double>? onSwipeUpdate; // dy delta from start (vertical swipe)
  final void Function(double velocity, double totalDy)? onSwipeEnd; // velocity and total displacement (vertical)

  const QueuePanel({
    super.key,
    required this.maProvider,
    required this.queue,
    required this.isLoading,
    required this.textColor,
    required this.primaryColor,
    required this.backgroundColor,
    required this.topPadding,
    required this.onClose,
    required this.onRefresh,
    this.onDraggingChanged,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
  });

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> with SingleTickerProviderStateMixin {
  List<QueueItem> _items = [];
  final GlobalKey _stackKey = GlobalKey();

  // Scroll controller to track list position (for swipe-to-close only at top)
  final ScrollController _scrollController = ScrollController();
  bool _isAtTop = true;
  bool _wasAtTopOnSwipeStart = true; // Capture at gesture start

  // Transfer dropdown animation
  late AnimationController _dropdownController;
  bool _showingTransferDropdown = false;

  // Drag state
  int? _dragIndex;
  int? _dragStartIndex;
  double _dragY = 0; // Y position of dragged item relative to Stack
  double _dragStartY = 0; // Y position when drag started (global)
  double _dragOffsetInItem = 0; // Offset of touch point within item
  QueueItem? _dragItem;
  double _itemHeight = 64.0;
  bool _pendingReorder = false; // True while waiting for API confirmation
  Timer? _pendingReorderTimer;

  // Optimistic update for tap-to-skip
  int? _optimisticCurrentIndex;

  // Swipe-to-close tracking (raw pointer events to bypass gesture arena)
  Offset? _swipeStart;
  Offset? _swipeLast;
  int? _swipeLastTime; // milliseconds since epoch
  bool _isSwiping = false;
  bool _swipeLocked = false; // Lock direction once established
  static const _swipeMinDistance = 8.0; // Min distance to start tracking (reduced for responsiveness)
  static const _edgeDeadZone = 48.0; // Dead zone for Android back gesture (increased)

  // Track last touch start position for edge detection in Dismissible
  // Static so it persists across widget rebuilds
  static double? _lastPointerDownX;
  static double? _lastScreenWidth;

  // Velocity tracking with multiple samples for smoother calculation
  final List<_VelocitySample> _velocitySamples = [];
  static const _maxVelocitySamples = 5;


  @override
  void initState() {
    super.initState();
    _items = List.from(widget.queue?.items ?? []);
    _dropdownController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // Track scroll position for swipe-to-close (only allowed at top)
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final atTop = _scrollController.offset <= 0;
    if (atTop != _isAtTop) {
      setState(() {
        _isAtTop = atTop;
      });
    }
  }

  @override
  void didUpdateWidget(QueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Clear optimistic state when server catches up
    if (_optimisticCurrentIndex != null) {
      final serverIndex = widget.queue?.currentIndex;
      if (serverIndex == _optimisticCurrentIndex) {
        // Server caught up - clear optimistic state
        _optimisticCurrentIndex = null;
      }
    }

    // Don't update items while dragging or waiting for reorder confirmation
    if (_dragIndex != null || _pendingReorder) return;

    final newItems = widget.queue?.items ?? [];

    // Only sync when player changes or item count changes (additions/deletions)
    // Don't sync on order changes - trust our local order after user reorders
    // This prevents stale server state from overwriting recent local changes
    final playerChanged = widget.queue?.playerId != oldWidget.queue?.playerId;
    final countChanged = newItems.length != _items.length;

    if (playerChanged || countChanged) {
      setState(() {
        _items = List.from(newItems);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _dropdownController.dispose();
    _pendingReorderTimer?.cancel();
    super.dispose();
  }


  void _handleDelete(QueueItem item, int index) async {
    // Store item for potential rollback
    final deletedItem = item;
    final deletedIndex = index;

    // Optimistic update - remove from local list
    setState(() {
      _items.removeAt(index);
    });

    // Call API with error handling
    final playerId = widget.queue?.playerId;
    if (playerId != null) {
      try {
        await widget.maProvider.api?.queueCommandDeleteItem(playerId, item.queueItemId);
      } catch (e) {
        // Rollback: re-insert the item or refresh from server
        // Refresh is safer as queue may have changed
        widget.onRefresh();
      }
    }
  }

  void _handleClearQueue() async {
    final playerId = widget.queue?.playerId;
    if (playerId == null) return;

    // Optimistic update - clear local list
    setState(() {
      _items.clear();
    });

    // Call API
    try {
      await widget.maProvider.api?.queueCommandClear(playerId);
    } catch (e) {
      // Refresh to restore if failed
      widget.onRefresh();
    }
  }

  void _openTransferDropdown() {
    if (_showingTransferDropdown) return;
    setState(() => _showingTransferDropdown = true);
    _dropdownController.forward();
  }

  void _closeTransferDropdown() {
    if (!_showingTransferDropdown) return;
    _dropdownController.reverse().then((_) {
      if (mounted) setState(() => _showingTransferDropdown = false);
    });
  }

  void _handleTransferQueue(BuildContext context) {
    if (_showingTransferDropdown) {
      _closeTransferDropdown();
    } else {
      _openTransferDropdown();
    }
  }

  List<Player> _getTargetPlayers() {
    // Use selected player (current player) as source, not the queue's player ID
    // This ensures correct filtering after queue transfer when player switches
    final sourcePlayerId = widget.maProvider.selectedPlayer?.playerId;
    if (sourcePlayerId == null) return [];
    return widget.maProvider.availablePlayers
        .where((p) => p.playerId != sourcePlayerId && p.available)
        .toList();
  }

  Widget _buildTransferDropdown() {
    final targetPlayers = _getTargetPlayers();
    final colorScheme = Theme.of(context).colorScheme;

    // Use a lighter shade of the queue panel background color
    final hsl = HSLColor.fromColor(widget.backgroundColor);
    final menuBackground = hsl.withLightness((hsl.lightness + 0.04).clamp(0.0, 1.0)).toColor();
    // Use theme's onSurface for text (matches library dropdown styling)
    final menuTextColor = colorScheme.onSurface;

    return Container(
      constraints: const BoxConstraints(maxHeight: 280, maxWidth: 220),
      decoration: BoxDecoration(
        color: menuBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title header (matches library dropdown section headers)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                S.of(context)!.transferTo,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: menuTextColor.withOpacity(0.5),
                ),
              ),
            ),

            // Player list
            if (targetPlayers.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  S.of(context)!.noOtherPlayersAvailable,
                  style: TextStyle(color: menuTextColor.withOpacity(0.5), fontSize: 14),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: targetPlayers.length,
                  itemBuilder: (context, index) {
                    final player = targetPlayers[index];

                    // Status color
                    Color statusColor;
                    if (!player.powered) {
                      statusColor = Colors.grey;
                    } else if (player.state == 'playing') {
                      statusColor = Colors.green;
                    } else {
                      statusColor = Colors.orange;
                    }

                    // Match library dropdown item styling
                    return InkWell(
                      onTap: () => _transferToPlayer(player),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.speaker_rounded, color: menuTextColor, size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                player.name,
                                style: TextStyle(color: menuTextColor),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _transferToPlayer(Player targetPlayer) async {
    final sourcePlayerId = widget.queue?.playerId;
    if (sourcePlayerId == null) return;

    // Close dropdown first
    _closeTransferDropdown();

    try {
      await widget.maProvider.api?.transferQueue(
        sourceQueueId: sourcePlayerId,
        targetQueueId: targetPlayer.playerId,
        autoPlay: true,
      );


      // Clear source player's track cache since its queue was transferred away
      widget.maProvider.clearPlayerTrackCache(sourcePlayerId);

      // Force collapse to mini player (closes queue instantly + collapses)
      GlobalPlayerOverlay.forceCollapsePlayer();

      // Switch to the target player - mini player will update to show new player
      widget.maProvider.selectPlayer(targetPlayer);
    } catch (e) {
      // Error transferring queue - handled silently
    }
  }

  void _resetSwipeState() {
    _swipeStart = null;
    _swipeLast = null;
    _swipeLastTime = null;
    _isSwiping = false;
    _swipeLocked = false;
    _velocitySamples.clear();
    // NOTE: Don't reset _lastPointerDownX - it's needed by confirmDismiss
    // which may be called after pointer up
  }

  /// Check if x position is in the edge dead zone (Android back gesture area)
  static bool _isInEdgeZone(double x, double screenWidth) {
    return x < _edgeDeadZone || x > screenWidth - _edgeDeadZone;
  }

  /// Check if last touch started in edge zone (for Dismissible to check)
  static bool get lastTouchWasInEdgeZone {
    if (_lastPointerDownX == null || _lastScreenWidth == null) return false;
    return _isInEdgeZone(_lastPointerDownX!, _lastScreenWidth!);
  }

  /// Build an invisible edge absorber that blocks horizontal drags from triggering Dismissible
  Widget _buildEdgeAbsorber({required bool left}) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: _edgeDeadZone,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {}, // Absorb horizontal drags
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
      ),
    );
  }

  void _addVelocitySample(Offset position, int timeMs) {
    _velocitySamples.add(_VelocitySample(position, timeMs));
    if (_velocitySamples.length > _maxVelocitySamples) {
      _velocitySamples.removeAt(0);
    }
  }

  double _calculateAverageVelocity() {
    if (_velocitySamples.length < 2) return 0.0;

    // Use weighted average of recent samples (more recent = higher weight)
    double totalVelocity = 0.0;
    double totalWeight = 0.0;

    for (int i = 1; i < _velocitySamples.length; i++) {
      final prev = _velocitySamples[i - 1];
      final curr = _velocitySamples[i];
      final dt = curr.timeMs - prev.timeMs;
      if (dt > 0 && dt < 100) { // Only use samples within 100ms
        final dx = curr.position.dx - prev.position.dx;
        final velocity = (dx / dt) * 1000; // px/s
        final weight = i.toDouble(); // Later samples get higher weight
        totalVelocity += velocity * weight;
        totalWeight += weight;
      }
    }

    return totalWeight > 0 ? totalVelocity / totalWeight : 0.0;
  }

  double _calculateAverageVelocityVertical() {
    if (_velocitySamples.length < 2) return 0.0;

    // Use weighted average of recent samples (more recent = higher weight)
    double totalVelocity = 0.0;
    double totalWeight = 0.0;

    for (int i = 1; i < _velocitySamples.length; i++) {
      final prev = _velocitySamples[i - 1];
      final curr = _velocitySamples[i];
      final dt = curr.timeMs - prev.timeMs;
      if (dt > 0 && dt < 100) { // Only use samples within 100ms
        final dy = curr.position.dy - prev.position.dy;
        final velocity = (dy / dt) * 1000; // px/s
        final weight = i.toDouble(); // Later samples get higher weight
        totalVelocity += velocity * weight;
        totalWeight += weight;
      }
    }

    return totalWeight > 0 ? totalVelocity / totalWeight : 0.0;
  }

  void _startDrag(int index, BuildContext itemContext, Offset globalPosition) {
    if (_dragIndex != null) return;

    // Clear any pending swipe state to prevent conflicts
    _resetSwipeState();

    final RenderBox itemBox = itemContext.findRenderObject() as RenderBox;
    final Offset itemGlobalPos = itemBox.localToGlobal(Offset.zero);
    _itemHeight = itemBox.size.height;

    // Get Stack's global position for proper coordinate conversion
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final stackGlobalPos = stackBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    // Calculate initial position relative to Stack
    _dragY = itemGlobalPos.dy - stackGlobalPos.dy;
    _dragStartY = globalPosition.dy;
    // Remember where in the item the touch started (for smooth following)
    _dragOffsetInItem = globalPosition.dy - itemGlobalPos.dy;

    setState(() {
      _dragIndex = index;
      _dragStartIndex = index;
      _dragItem = _items[index];
    });

    // Haptic feedback on drag start
    HapticFeedback.mediumImpact();

    // Notify parent that drag started
    widget.onDraggingChanged?.call(true);
  }

  void _updateDragPointer(Offset globalPosition) {
    if (_dragIndex == null) return;

    // Get Stack's global position
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final stackGlobalPos = stackBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    // Calculate overlay position relative to Stack, accounting for touch offset
    _dragY = globalPosition.dy - stackGlobalPos.dy - _dragOffsetInItem;

    // Calculate which index we're hovering over based on movement from start
    final totalOffset = globalPosition.dy - _dragStartY;
    final indexOffset = (totalOffset / _itemHeight).round();
    final targetIndex = (_dragStartIndex! + indexOffset).clamp(0, _items.length - 1);

    if (targetIndex != _dragIndex) {
      // Reorder items in the list
      setState(() {
        final item = _items.removeAt(_dragIndex!);
        _items.insert(targetIndex, item);
        _dragIndex = targetIndex;
      });
      // Haptic feedback on each reorder
      HapticFeedback.selectionClick();
    } else {
      // Just update position
      setState(() {});
    }
  }

  void _endDrag() async {
    if (_dragIndex == null || _dragStartIndex == null) return;

    final newIndex = _dragIndex!;
    final originalIndex = _dragStartIndex!;
    final item = _items[newIndex];
    final positionChanged = originalIndex != newIndex;

    // Cancel any existing timer to prevent stacking
    _pendingReorderTimer?.cancel();

    setState(() {
      _dragIndex = null;
      _dragStartIndex = null;
      _dragItem = null;
      // Block didUpdateWidget while waiting for server confirmation
      if (positionChanged) _pendingReorder = true;
    });

    // Haptic feedback on drop
    HapticFeedback.lightImpact();

    // Notify parent that drag ended
    widget.onDraggingChanged?.call(false);

    // Call API if position changed
    if (positionChanged) {
      final playerId = widget.queue?.playerId;
      // API uses relative shift: positive = down, negative = up
      final posShift = newIndex - originalIndex;
      if (playerId != null) {
        try {
          await widget.maProvider.api?.queueCommandMoveItem(playerId, item.queueItemId, posShift);
          // Allow updates again after a delay for server state to propagate
          _pendingReorderTimer = Timer(const Duration(milliseconds: 2000), () {
            if (mounted) {
              setState(() {
                _pendingReorder = false;
              });
            }
          });
        } catch (e) {
          // Clear pending state immediately on error
          if (mounted) {
            setState(() {
              _pendingReorder = false;
            });
          }
          // Refresh queue from server to get correct state
          widget.onRefresh();
        }
      } else {
        // Clear pending state
        if (mounted) {
          setState(() {
            _pendingReorder = false;
          });
        }
      }
    }
  }

  void _cancelDrag() {
    if (_dragStartIndex == null) return;

    // Restore original position
    if (_dragIndex != null && _dragIndex != _dragStartIndex) {
      setState(() {
        final item = _items.removeAt(_dragIndex!);
        _items.insert(_dragStartIndex!, item);
      });
    }

    setState(() {
      _dragIndex = null;
      _dragStartIndex = null;
      _dragItem = null;
    });

    // Notify parent that drag ended
    widget.onDraggingChanged?.call(false);
  }

  void _handleTapToSkip(QueueItem item, int index, bool isCurrentItem) async {
    if (isCurrentItem) return;

    final playerId = widget.queue?.playerId;
    if (playerId == null) return;

    // Optimistic update: immediately show tapped track as current
    setState(() {
      _optimisticCurrentIndex = index;
    });

    // Call API
    try {
      await widget.maProvider.api?.queueCommandPlayIndex(playerId, item.queueItemId);
    } catch (e) {
      // Error playing index - clear optimistic state
      if (mounted) {
        setState(() {
          _optimisticCurrentIndex = null;
        });
      }
    }
    // Note: didUpdateWidget clears _optimisticCurrentIndex when server state catches up
  }

  void _handleMoveToPlayNext(QueueItem item, int index, bool isCurrentItem) async {
    if (isCurrentItem) return;

    final playerId = widget.queue?.playerId;
    if (playerId == null) return;

    // Get current index (where the currently playing track is)
    final currentIndex = _optimisticCurrentIndex ?? widget.queue!.currentIndex ?? 0;

    // Target position is right after the current track
    final targetIndex = currentIndex + 1;

    // If already at target position, nothing to do
    if (index == targetIndex) {
      // Haptic to confirm it's already in position
      HapticFeedback.lightImpact();
      return;
    }

    // Calculate the position shift for the API
    final posShift = targetIndex - index;

    // Cancel any existing timer to prevent stacking
    _pendingReorderTimer?.cancel();

    // Optimistic update - move item in local list
    setState(() {
      final movedItem = _items.removeAt(index);
      _items.insert(targetIndex > index ? targetIndex - 1 : targetIndex, movedItem);
      _pendingReorder = true;
    });

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Call API
    try {
      await widget.maProvider.api?.queueCommandMoveItem(playerId, item.queueItemId, posShift);
      // Allow updates again after a delay for server state to propagate
      _pendingReorderTimer = Timer(const Duration(milliseconds: 2000), () {
        if (mounted) {
          setState(() {
            _pendingReorder = false;
          });
        }
      });
    } catch (e) {
      // Clear pending state immediately on error
      if (mounted) {
        setState(() {
          _pendingReorder = false;
        });
      }
      // Refresh queue from server to get correct state
      widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Listener for raw pointer events to bypass gesture arena
    // This allows swipe-to-close to work even over ListView/Dismissible
    return Listener(
      onPointerDown: (event) {
        // Store touch position for edge detection (used by Dismissible confirmDismiss)
        // Use static variables so they persist across rebuilds
        _lastPointerDownX = event.position.dx;
        _lastScreenWidth = MediaQuery.of(context).size.width;

        // Check if touch started in edge zone (Android back gesture area)
        final startedInEdgeZone = _isInEdgeZone(event.position.dx, _lastScreenWidth!);

        // Don't track swipe while dragging a queue item
        if (_dragIndex == null && !startedInEdgeZone) {
          _swipeStart = event.position;
          _swipeLast = event.position;
          _swipeLastTime = DateTime.now().millisecondsSinceEpoch;
          _isSwiping = false;
          _swipeLocked = false;
          _velocitySamples.clear();
          _addVelocitySample(event.position, _swipeLastTime!);
          // Capture scroll position at gesture start - only allow close if already at top
          _wasAtTopOnSwipeStart = _isAtTop;
        } else if (startedInEdgeZone) {
          // Clear swipe state for edge touches
          _swipeStart = null;
        }
      },
      onPointerMove: (event) {
        // Ignore swipes while dragging a queue item
        if (_swipeStart == null || _dragIndex != null) return;

        final dx = (event.position.dx - _swipeStart!.dx).abs();
        final dy = event.position.dy - _swipeStart!.dy;
        final now = DateTime.now().millisecondsSinceEpoch;

        // Track all move events for velocity calculation
        _addVelocitySample(event.position, now);
        _swipeLast = event.position;
        _swipeLastTime = now;

        // Once direction is locked, maintain it (prevents accidental cancellation)
        if (_swipeLocked && _isSwiping) {
          widget.onSwipeUpdate?.call(dy.clamp(0.0, double.infinity));
          return;
        }

        // Check if this is a vertical swipe (dy > dx * 1.2)
        final isVertical = dy.abs() > _swipeMinDistance && dy.abs() > dx * 1.2;

        if (isVertical && dy > 0 && _wasAtTopOnSwipeStart) {
          // Vertical swipe down - close gesture (only when was at top when gesture started)
          if (!_isSwiping) {
            _isSwiping = true;
            _swipeLocked = true; // Lock direction once swipe starts
            widget.onSwipeStart?.call();
          }
          widget.onSwipeUpdate?.call(dy);
        } else if (!_swipeLocked && dy.abs() > _swipeMinDistance) {
          // Direction established as horizontal - don't start swipe
          _swipeLocked = true; // Lock as non-swipe
        }
      },
      onPointerUp: (event) {
        if (_isSwiping && _swipeStart != null) {
          final velocity = _calculateAverageVelocityVertical();
          final totalDy = event.position.dy - _swipeStart!.dy;
          widget.onSwipeEnd?.call(velocity, totalDy);
        }
        _resetSwipeState();
      },
      onPointerCancel: (_) {
        if (_isSwiping) {
          widget.onSwipeEnd?.call(0, 0); // Cancel - no action
        }
        _resetSwipeState();
      },
      child: Container(
        color: widget.backgroundColor,
        child: Stack(
          children: [
            // Main content column
            Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.only(top: widget.topPadding + 4, left: 4, right: 16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: widget.textColor, size: IconSizes.lg),
                        onPressed: _showingTransferDropdown ? _closeTransferDropdown : widget.onClose,
                        padding: Spacing.paddingAll12,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Queue',
                        style: TextStyle(
                          color: widget.textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      // Transfer queue button
                      IconButton(
                        icon: Icon(
                          _showingTransferDropdown ? Icons.close : Icons.swap_horiz_rounded,
                          color: _showingTransferDropdown ? widget.primaryColor : widget.textColor.withOpacity(0.7),
                          size: IconSizes.sm,
                        ),
                        onPressed: () => _handleTransferQueue(context),
                        padding: Spacing.paddingAll12,
                      ),
                      // Clear queue button
                      IconButton(
                        icon: Icon(Icons.delete_sweep_rounded, color: widget.textColor.withOpacity(0.7), size: IconSizes.sm),
                        onPressed: _handleClearQueue,
                        padding: Spacing.paddingAll12,
                      ),
                    ],
                  ),
                ),

                // Queue content
                Expanded(
              child: widget.isLoading
                  ? Center(child: CircularProgressIndicator(color: widget.primaryColor))
                  : widget.queue == null || _items.isEmpty
                      ? EmptyState.queue(context: context)
                      : Listener(
                          // Capture pointer events anywhere while dragging
                          onPointerMove: (event) {
                            if (_dragIndex != null) {
                              _updateDragPointer(event.position);
                            }
                          },
                          onPointerUp: (event) {
                            if (_dragIndex != null) {
                              _endDrag();
                            }
                          },
                          onPointerCancel: (event) {
                            if (_dragIndex != null) {
                              _cancelDrag();
                            }
                          },
                          child: Stack(
                            key: _stackKey,
                            children: [
                              _buildQueueList(),
                              // Dragged item overlay
                              if (_dragIndex != null && _dragItem != null)
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  top: _dragY,
                                  child: Material(
                                    elevation: 8,
                                    borderRadius: BorderRadius.circular(8),
                                    child: _buildQueueItemContent(_dragItem!, _dragIndex!, false, false),
                                  ),
                                ),
                              // Edge gesture absorbers - block horizontal drags from screen edges
                              // This prevents Android back gesture from triggering Dismissible
                              _buildEdgeAbsorber(left: true),
                              _buildEdgeAbsorber(left: false),
                            ],
                          ),
                        ),
                ),
              ],
            ),

            // Floating dropdown overlay for transfer
            if (_showingTransferDropdown) ...[
              // Tap-to-dismiss backdrop
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeTransferDropdown,
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),
              // Dropdown menu with open/close animation
              Positioned(
                top: widget.topPadding + 52, // Below header
                right: 56, // Aligned with transfer button
                child: AnimatedBuilder(
                  animation: CurvedAnimation(
                    parent: _dropdownController,
                    curve: Curves.easeInOut,
                  ),
                  builder: (context, child) {
                    final value = _dropdownController.value;
                    final curvedValue = Curves.easeInOut.transform(value);

                    return ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        widthFactor: 1.0,
                        heightFactor: curvedValue,
                        child: Opacity(
                          opacity: curvedValue,
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: _buildTransferDropdown(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQueueList() {
    // Use optimistic index if set, otherwise use server state
    final currentIndex = _optimisticCurrentIndex ?? widget.queue!.currentIndex ?? 0;

    return ListView.builder(
      key: const PageStorageKey('queue_list'),
      controller: _scrollController,
      padding: Spacing.paddingH8,
      // Disable scrolling while dragging to prevent gesture conflict
      physics: _dragIndex != null
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final isCurrentItem = index == currentIndex;
        final isPastItem = index < currentIndex;
        final isDragging = _dragIndex == index;

        return Opacity(
          opacity: isDragging ? 0.3 : 1.0,
          child: _buildDismissibleItem(item, index, isCurrentItem, isPastItem),
        );
      },
    );
  }

  Widget _buildDismissibleItem(QueueItem item, int index, bool isCurrentItem, bool isPastItem) {
    return Dismissible(
      key: ValueKey(item.queueItemId),
      direction: isCurrentItem ? DismissDirection.none : DismissDirection.horizontal,
      // Swipe right (startToEnd) = move to play next
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: widget.primaryColor,
          borderRadius: BorderRadius.zero,
        ),
        child: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
      ),
      // Swipe left (endToStart) = delete
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.zero,
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
      ),
      confirmDismiss: (direction) async {
        // Block dismissal if swipe started from screen edge (Android back gesture)
        if (lastTouchWasInEdgeZone) return false;

        if (direction == DismissDirection.startToEnd) {
          // Swipe right = move to play next position
          _handleMoveToPlayNext(item, index, isCurrentItem);
          return false; // Don't dismiss - item stays in queue (just moved)
        } else {
          // Swipe left = delete
          return true;
        }
      },
      onDismissed: (direction) => _handleDelete(item, index),
      child: _buildQueueItemWithDragHandle(item, index, isCurrentItem, isPastItem),
    );
  }

  Widget _buildQueueItemWithDragHandle(QueueItem item, int index, bool isCurrentItem, bool isPastItem) {
    return Builder(
      builder: (itemContext) => _buildQueueItemContent(
        item,
        index,
        isCurrentItem,
        isPastItem,
        dragHandle: isCurrentItem
            ? SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Icon(Icons.play_arrow_rounded, color: widget.primaryColor, size: 20),
                ),
              )
            : SizedBox(
                width: 48,
                height: 48,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    _startDrag(index, itemContext, event.position);
                  },
                  // Move/up/cancel handled by parent Listener on Stack
                  child: Center(
                    child: Icon(Icons.drag_handle, color: widget.textColor.withOpacity(0.3), size: 20),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildQueueItemContent(QueueItem item, int index, bool isCurrentItem, bool isPastItem, {Widget? dragHandle}) {
    final imageUrl = widget.maProvider.api?.getImageUrl(item.track, size: 80);
    final duration = formatDurationOrEmpty(item.track.duration);

    return RepaintBoundary(
      child: Opacity(
        opacity: isPastItem ? 0.5 : 1.0,
        child: Container(
          margin: isCurrentItem ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2) : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isCurrentItem ? widget.primaryColor.withOpacity(0.15) : widget.backgroundColor,
            borderRadius: isCurrentItem ? BorderRadius.circular(12) : BorderRadius.zero,
          ),
          child: ListTile(
            dense: true,
            // Compensate for current item's 8px margin on both sides
            // Left:  Non-current: 8+0+16=24px, Current: 8+8+8=24px
            // Right: Non-current: 8+0+8+14=30px, Current: 8+8+0+14=30px
            contentPadding: EdgeInsets.only(
              left: isCurrentItem ? 8 : 16,
              right: isCurrentItem ? 0 : 8,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: SizedBox(
                width: 44,
                height: 44,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 176,
                        memCacheHeight: 176,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (context, url) => Container(
                          color: widget.textColor.withOpacity(0.1),
                          child: Icon(Icons.music_note, color: widget.textColor.withOpacity(0.3), size: 20),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: widget.textColor.withOpacity(0.1),
                          child: Icon(Icons.music_note, color: widget.textColor.withOpacity(0.3), size: 20),
                        ),
                      )
                    : Container(
                        color: widget.textColor.withOpacity(0.1),
                        child: Icon(Icons.music_note, color: widget.textColor.withOpacity(0.3), size: 20),
                      ),
              ),
            ),
            title: Text(
              item.track.name,
              style: TextStyle(
                color: isCurrentItem ? widget.primaryColor : widget.textColor,
                fontSize: 14,
                fontWeight: isCurrentItem ? FontWeight.w600 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: item.track.artists != null && item.track.artists!.isNotEmpty
                ? Text(
                    item.track.artists!.first.name,
                    style: TextStyle(
                      color: widget.textColor.withOpacity(0.6),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (duration.isNotEmpty)
                  Text(
                    duration,
                    style: TextStyle(
                      color: widget.textColor.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                dragHandle ?? Icon(Icons.drag_handle, color: widget.textColor.withOpacity(0.3), size: 20),
              ],
            ),
            onTap: () => _handleTapToSkip(item, index, isCurrentItem),
          ),
        ),
      ),
    );
  }
}

/// Helper class for velocity tracking samples
class _VelocitySample {
  final Offset position;
  final int timeMs;

  _VelocitySample(this.position, this.timeMs);
}

