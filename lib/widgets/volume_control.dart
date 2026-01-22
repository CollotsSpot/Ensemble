import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import '../services/settings_service.dart';

/// Volume control widget for Music Assistant players
/// For local device: controls system media volume
/// For MA players: controls player volume via API
class VolumeControl extends StatefulWidget {
  final bool compact;
  final Color? accentColor;

  const VolumeControl({super.key, this.compact = false, this.accentColor});

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  final _logger = DebugLogger();
  double? _pendingVolume;
  double? _systemVolume;
  StreamSubscription? _volumeListener;
  String? _localPlayerId;
  bool _isLocalPlayer = false;
  bool _isDragging = false;

  // Live volume update state
  int _lastVolumeUpdateTime = 0;
  static const int _volumeThrottleMs = 150;
  static const int _precisionThrottleMs = 50;

  // Precision mode state
  bool _inPrecisionMode = false;
  Timer? _precisionTimer;
  Offset? _lastDragPosition;
  double _lastLocalX = 0.0;
  bool _precisionModeEnabled = true;
  double _precisionZoomCenter = 0.0;
  double _precisionStartX = 0.0;
  static const int _precisionTriggerMs = 800;
  static const double _precisionStillnessThreshold = 5.0;
  static const double _precisionSensitivity = 0.1; // 10% range in precision mode

  // Button tap indicator state
  bool _showButtonIndicator = false;
  Timer? _buttonIndicatorTimer;

  @override
  void initState() {
    super.initState();
    _initLocalPlayer();
    _loadSettings();
  }

  Future<void> _initLocalPlayer() async {
    _localPlayerId = await SettingsService.getBuiltinPlayerId();

    final volume = await FlutterVolumeController.getVolume();
    if (mounted) {
      setState(() {
        _systemVolume = volume;
      });
    }

    _volumeListener = FlutterVolumeController.addListener((volume) {
      if (mounted && _isLocalPlayer && !_isDragging) {
        setState(() {
          _systemVolume = volume;
        });
      }
    });
  }

  Future<void> _loadSettings() async {
    final precisionEnabled = await SettingsService.getVolumePrecisionMode();
    if (mounted) {
      setState(() {
        _precisionModeEnabled = precisionEnabled;
      });
    }
  }

  void _enterPrecisionMode() {
    if (_inPrecisionMode) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _inPrecisionMode = true;
      _precisionZoomCenter = _pendingVolume ?? 0.5;
      _precisionStartX = _lastLocalX;
    });
  }

  void _exitPrecisionMode() {
    _precisionTimer?.cancel();
    _precisionTimer = null;
    if (_inPrecisionMode) {
      setState(() {
        _inPrecisionMode = false;
      });
    }
  }

  @override
  void dispose() {
    _volumeListener?.cancel();
    _precisionTimer?.cancel();
    _buttonIndicatorTimer?.cancel();
    super.dispose();
  }

  Future<void> _adjustVolume(MusicAssistantProvider maProvider, String playerId, double currentVolume, int delta) async {
    final newVolume = ((currentVolume * 100).round() + delta).clamp(0, 100);

    // Show indicator briefly on button tap
    _buttonIndicatorTimer?.cancel();
    setState(() {
      _showButtonIndicator = true;
      _pendingVolume = newVolume / 100.0;
    });
    _buttonIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showButtonIndicator = false;
          _pendingVolume = null;
        });
      }
    });

    if (_isLocalPlayer) {
      _logger.log('Volume: Setting system volume to $newVolume%');
      try {
        await FlutterVolumeController.setVolume(newVolume / 100.0);
        if (mounted) {
          setState(() {
            _systemVolume = newVolume / 100.0;
          });
        }
      } catch (e) {
        _logger.log('Volume: Error setting system volume - $e');
      }
    } else {
      _logger.log('Volume: Setting to $newVolume%');
      try {
        await maProvider.setVolume(playerId, newVolume);
      } catch (e) {
        _logger.log('Volume: Error - $e');
      }
    }
  }

  void _sendVolumeUpdate(MusicAssistantProvider maProvider, String playerId, double volume) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final throttleMs = _inPrecisionMode ? _precisionThrottleMs : _volumeThrottleMs;

    if (now - _lastVolumeUpdateTime >= throttleMs) {
      _lastVolumeUpdateTime = now;
      final volumeLevel = (volume * 100).round();

      if (_isLocalPlayer) {
        FlutterVolumeController.setVolume(volume);
      } else {
        maProvider.setVolume(playerId, volumeLevel);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      return const SizedBox.shrink();
    }

    _isLocalPlayer = _localPlayerId != null && player.playerId == _localPlayerId;

    // Use pending volume during drag or button tap to prevent stale state issues
    final currentVolume = (_isDragging || _showButtonIndicator)
        ? (_pendingVolume ?? (_isLocalPlayer ? (_systemVolume ?? 0.5) : player.volume.toDouble() / 100.0))
        : _isLocalPlayer
            ? (_systemVolume ?? 0.5)
            : player.volume.toDouble() / 100.0;

    // Use accent color if provided, otherwise fall back to theme primary
    final accentColor = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    if (widget.compact) {
      return IconButton(
        icon: Icon(
          currentVolume < 0.01
              ? Icons.volume_off
              : currentVolume < 0.3
                  ? Icons.volume_down
                  : Icons.volume_up,
          color: Colors.white70,
        ),
        onPressed: () async {
          // In compact mode, toggle between 0 and 50%
          final newVolume = currentVolume < 0.01 ? 50 : 0;
          await _adjustVolume(maProvider, player.playerId, newVolume / 100.0, 0);
        },
      );
    }

    return Row(
      children: [
        // Volume decrease button
        IconButton(
          icon: const Icon(
            Icons.volume_down,
            color: Colors.white70,
          ),
          onPressed: () => _adjustVolume(maProvider, player.playerId, currentVolume, -1),
        ),
        // Slider with floating teardrop indicator
        Expanded(
          child: SizedBox(
            height: 48,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sliderWidth = constraints.maxWidth;
                // Calculate thumb position for the custom slider track
                final thumbPosition = sliderWidth * currentVolume.clamp(0.0, 1.0);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // The slider with gesture detection for precision mode
                    GestureDetector(
                      onHorizontalDragStart: (details) {
                        setState(() {
                          _isDragging = true;
                          _pendingVolume = currentVolume;
                          _lastDragPosition = details.globalPosition;
                          _lastLocalX = details.localPosition.dx;
                        });
                      },
                      onHorizontalDragUpdate: (details) {
                        if (!_isDragging) return;

                        final currentPosition = details.globalPosition;

                        // Check for stillness to trigger precision mode
                        if (_precisionModeEnabled && _lastDragPosition != null) {
                          final movement = (currentPosition - _lastDragPosition!).distance;

                          if (movement < _precisionStillnessThreshold) {
                            // Finger is still - start precision timer
                            if (_precisionTimer == null && !_inPrecisionMode) {
                              _precisionTimer = Timer(
                                Duration(milliseconds: _precisionTriggerMs),
                                _enterPrecisionMode,
                              );
                            }
                          } else {
                            // Finger moved - cancel timer
                            _precisionTimer?.cancel();
                            _precisionTimer = null;
                          }
                        }
                        _lastDragPosition = currentPosition;
                        _lastLocalX = details.localPosition.dx;

                        double newVolume;

                        if (_inPrecisionMode) {
                          // PRECISION MODE: Movement from entry point maps to zoomed range
                          final offsetX = details.localPosition.dx - _precisionStartX;
                          final normalizedOffset = offsetX / sliderWidth;
                          final volumeChange = normalizedOffset * _precisionSensitivity;
                          newVolume = (_precisionZoomCenter + volumeChange).clamp(0.0, 1.0);
                        } else {
                          // NORMAL MODE: Position-based (like standard slider)
                          newVolume = (details.localPosition.dx / sliderWidth).clamp(0.0, 1.0);
                        }

                        if ((newVolume - (_pendingVolume ?? 0)).abs() > 0.001) {
                          setState(() {
                            _pendingVolume = newVolume;
                          });
                          _sendVolumeUpdate(maProvider, player.playerId, newVolume);
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        if (!_isDragging) return;

                        // Send final volume
                        final finalVolume = _pendingVolume ?? currentVolume;
                        final volumeLevel = (finalVolume * 100).round();

                        if (_isLocalPlayer) {
                          FlutterVolumeController.setVolume(finalVolume);
                          _systemVolume = finalVolume;
                        } else {
                          maProvider.setVolume(player.playerId, volumeLevel);
                        }

                        _exitPrecisionMode();
                        _lastDragPosition = null;
                        setState(() {
                          _isDragging = false;
                          _pendingVolume = null;
                        });
                      },
                      // Custom slider track (no Overlay needed - Flutter 3.38 Slider uses OverlayPortal)
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: SizedBox(
                            height: 20,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // Inactive track (full width, thinner)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 8.5,
                                  child: Container(
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(1.5),
                                    ),
                                  ),
                                ),
                                // Active track
                                Positioned(
                                  left: 0,
                                  top: 7,
                                  child: Container(
                                    width: sliderWidth * currentVolume.clamp(0.0, 1.0),
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _inPrecisionMode ? accentColor : Colors.white,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                                // Thumb
                                Positioned(
                                  left: (sliderWidth * currentVolume.clamp(0.0, 1.0)) - 6,
                                  top: 4,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: _inPrecisionMode ? accentColor : Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Floating teardrop indicator (visible when dragging or button tap)
                    if (_isDragging || _showButtonIndicator)
                      Positioned(
                        left: thumbPosition - 16,
                        top: -28,
                        child: CustomPaint(
                          size: const Size(32, 32),
                          painter: _TeardropPainter(
                            color: _inPrecisionMode ? accentColor : Colors.white,
                            volume: (currentVolume * 100).round(),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        // Volume increase button
        IconButton(
          icon: const Icon(
            Icons.volume_up,
            color: Colors.white70,
          ),
          onPressed: () => _adjustVolume(maProvider, player.playerId, currentVolume, 1),
        ),
      ],
    );
  }
}

/// Custom painter for upside-down teardrop volume indicator
class _TeardropPainter extends CustomPainter {
  final Color color;
  final int volume;

  _TeardropPainter({required this.color, required this.volume});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Draw upside-down teardrop shape
    final path = Path();

    // Start at bottom point (the tip pointing down toward slider)
    path.moveTo(center.dx, size.height - 2);

    // Curve up to the left side of the circle
    path.quadraticBezierTo(
      center.dx - radius * 0.8,
      center.dy + radius * 0.3,
      center.dx - radius,
      center.dy - radius * 0.2,
    );

    // Arc around the top (the bulb)
    path.arcToPoint(
      Offset(center.dx + radius, center.dy - radius * 0.2),
      radius: Radius.circular(radius),
      clockwise: true,
    );

    // Curve down to the bottom point
    path.quadraticBezierTo(
      center.dx + radius * 0.8,
      center.dy + radius * 0.3,
      center.dx,
      size.height - 2,
    );

    path.close();
    canvas.drawPath(path, paint);

    // Draw the volume number (no % symbol)
    final textColor = color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$volume',
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Position text in the center of the bulb (slightly above center)
    final textOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - radius * 0.4 - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant _TeardropPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.volume != volume;
  }
}
