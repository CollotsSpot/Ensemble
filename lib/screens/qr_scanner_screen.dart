import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../l10n/app_localizations.dart';

/// A screen for scanning QR codes to get the Remote Access ID.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _controller;
  bool _hasScanned = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      formats: [BarcodeFormat.qrCode], // Only scan QR codes
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        final remoteId = _extractRemoteId(code);

        if (remoteId != null && remoteId.isNotEmpty) {
          _hasScanned = true;
          Navigator.of(context).pop(remoteId);
          return;
        } else {
          // Show what was scanned for debugging
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Scanned: $code'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  /// Extract the remote ID from various QR code formats
  String? _extractRemoteId(String code) {
    // Format 1: Raw remote ID (alphanumeric)
    if (RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(code) && code.length >= 8) {
      return code;
    }

    // Format 2: ma://remote/<id>
    if (code.startsWith('ma://remote/')) {
      return code.replaceFirst('ma://remote/', '');
    }

    // Format 3: URL from app.music-assistant.io
    // Examples:
    // - https://app.music-assistant.io/?cloudInstanceId=<id>
    // - https://app.music-assistant.io/#/home?cloudInstanceId=<id>
    if (code.contains('music-assistant.io')) {
      final uri = Uri.tryParse(code);
      if (uri != null) {
        // Check query parameters in main URL
        final queryParams = ['cloudInstanceId', 'cloud_instance_id', 'remoteid', 'remote_id', 'id'];
        for (final param in queryParams) {
          final value = uri.queryParameters[param];
          if (value != null && value.isNotEmpty) {
            return value;
          }
        }

        // Check fragment (hash) for query params: #/home?cloudInstanceId=xxx
        final fragment = uri.fragment;
        if (fragment.contains('?')) {
          final fragmentQuery = fragment.split('?').last;
          final fragmentParams = Uri.splitQueryString(fragmentQuery);
          for (final param in queryParams) {
            final value = fragmentParams[param];
            if (value != null && value.isNotEmpty) {
              return value;
            }
          }
        }

        // Check if ID is in path segments
        for (final segment in uri.pathSegments) {
          if (segment.length >= 8 && RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(segment)) {
            return segment;
          }
        }
      }
    }

    // Format 4: Other URL formats - try to extract from query params or path
    if (code.contains('://')) {
      final uri = Uri.tryParse(code);
      if (uri != null) {
        // Check common query param names
        for (final param in ['id', 'remoteid', 'remote_id', 'cloudInstanceId']) {
          final value = uri.queryParameters[param];
          if (value != null && value.isNotEmpty) {
            return value;
          }
        }
        // Last path segment if it looks like an ID
        if (uri.pathSegments.isNotEmpty) {
          final last = uri.pathSegments.last;
          if (last.length >= 8 && RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(last)) {
            return last;
          }
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(S.of(context)!.scanQrCode),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Toggle torch
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 64,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Camera error: ${error.errorCode.name}',
                      style: TextStyle(color: colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.errorDetails?.message ?? S.of(context)!.cameraPermissionDenied,
                      style: TextStyle(color: colorScheme.error.withOpacity(0.7)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            },
          ),

          // Scan overlay with instruction
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Scan frame
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withOpacity(0.8),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(height: 32),
                // Instruction text
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        S.of(context)!.pointCameraAtQr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      if (_statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
