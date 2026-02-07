import 'package:flutter/material.dart';
import '../models/media_item.dart';

/// Badge widget that displays a hi-res audio indicator for tracks
/// with high quality audio (lossless codec + sample rate > 48kHz OR bit depth > 16)
class HiResBadge extends StatelessWidget {
  final String? tooltip;
  final Color? primaryColor;

  const HiResBadge({super.key, this.tooltip, this.primaryColor});

  /// Lossless audio codecs that qualify for hi-res badge
  static const _losslessCodecs = [
    'flac',
    'wav',
    'aiff',
    'alac',
    'dsf',
    'wavpack',
    'ape',
    'tak',
  ];

  /// Check if track qualifies for hi-res badge, returns tooltip text if so
  static String? getTooltip(Track track) {
    // Find first available provider mapping with audio format info
    final mapping =
        track.providerMappings?.cast<ProviderMapping?>().firstWhere(
              (m) => m != null && m.available && m.audioFormat != null,
              orElse: () => null,
            );

    final audioFormat = mapping?.audioFormat;
    if (audioFormat == null) return null;

    final contentType =
        (audioFormat['content_type'] as String?)?.toLowerCase();
    final sampleRate = audioFormat['sample_rate'] as int?;
    final bitDepth = audioFormat['bit_depth'] as int?;

    // Must be a lossless codec
    if (contentType == null) return null;
    final isLossless =
        _losslessCodecs.any((codec) => contentType.contains(codec));
    if (!isLossless) return null;

    // Must be hi-res: sample_rate > 48000 OR bit_depth > 16
    final effectiveSampleRate = sampleRate ?? 44100;
    final effectiveBitDepth = bitDepth ?? 16;

    if (effectiveSampleRate <= 48000 && effectiveBitDepth <= 16) {
      return null;
    }

    return '${effectiveSampleRate ~/ 1000}kHz $effectiveBitDepth-bit';
  }

  /// Returns HiResBadge if track qualifies for hi-res, null otherwise
  static Widget? fromTrack(Track track, {Color? primaryColor}) {
    final tooltipText = getTooltip(track);
    if (tooltipText == null) return null;
    return HiResBadge(tooltip: tooltipText, primaryColor: primaryColor);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Use adaptive primary color muted with white, fallback to theme primary
    final baseColor = primaryColor ?? colorScheme.primary;
    final color = Color.lerp(baseColor, Colors.white, 0.5)!;

    final content = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Hi-Res',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              'AUDIO',
              style: TextStyle(
                color: colorScheme.surface,
                fontSize: 8,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );

    // Only use Tooltip if an Overlay ancestor exists
    final hasOverlay = Overlay.maybeOf(context) != null;
    if (!hasOverlay) {
      return content;
    }

    return Tooltip(
      message: tooltip ?? 'Hi-Res Audio',
      child: content,
    );
  }
}
