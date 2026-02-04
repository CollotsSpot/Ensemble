import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../l10n/app_localizations.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import '../screens/audiobook_series_screen.dart';
import '../utils/page_transitions.dart';

class SeriesRow extends StatefulWidget {
  final String title;
  final Future<List<AudiobookSeries>> Function() loadSeries;
  final double? rowHeight;
  /// Optional: synchronous getter for cached data (for instant display)
  final List<AudiobookSeries>? Function()? getCachedSeries;

  const SeriesRow({
    super.key,
    required this.title,
    required this.loadSeries,
    this.rowHeight,
    this.getCachedSeries,
  });

  @override
  State<SeriesRow> createState() => _SeriesRowState();
}

class _SeriesRowState extends State<SeriesRow> with AutomaticKeepAliveClientMixin {
  List<AudiobookSeries> _series = [];
  bool _isLoading = true;
  bool _hasLoaded = false;

  // Cache for series cover images
  final Map<String, List<String>> _seriesCovers = {};
  final Set<String> _loadingCovers = {};
  // Cache for series book counts
  final Map<String, int> _seriesBookCounts = {};
  // Cache for extracted colors from covers
  final Map<String, List<Color>> _seriesExtractedColors = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Get cached data synchronously BEFORE first build (no spinner flash)
    final cached = widget.getCachedSeries?.call();
    if (cached != null && cached.isNotEmpty) {
      _series = cached;
      _isLoading = false;
    }
    _loadSeries();
  }

  Future<void> _loadSeries() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    // Load fresh data (always update)
    try {
      final freshSeries = await widget.loadSeries();
      if (mounted && freshSeries.isNotEmpty) {
        setState(() {
          _series = freshSeries;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSeriesCovers(String seriesId, MusicAssistantProvider maProvider) async {
    if (_loadingCovers.contains(seriesId) || _seriesCovers.containsKey(seriesId)) {
      return;
    }

    _loadingCovers.add(seriesId);

    try {
      final books = await maProvider.api?.getSeriesAudiobooks(seriesId);
      if (books != null && books.isNotEmpty && mounted) {
        final covers = <String>[];
        for (final book in books.take(9)) {
          final imageUrl = maProvider.getImageUrl(book);
          if (imageUrl != null) {
            covers.add(imageUrl);
          }
        }
        if (mounted) {
          setState(() {
            _seriesCovers[seriesId] = covers;
            _seriesBookCounts[seriesId] = books.length;
          });
          // Precache images for smooth hero animations
          _precacheSeriesCovers(covers);
          // Extract colors asynchronously (delayed to avoid jank during scroll)
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _extractSeriesColors(seriesId, covers);
          });
        }
      }
    } finally {
      _loadingCovers.remove(seriesId);
    }
  }

  /// Precache series cover images for smooth hero animations
  void _precacheSeriesCovers(List<String> covers) {
    if (!mounted) return;
    for (final url in covers) {
      precacheImage(
        CachedNetworkImageProvider(url),
        context,
      ).catchError((_) => false);
    }
  }

  /// Extract colors from series book covers for empty cell backgrounds
  Future<void> _extractSeriesColors(String seriesId, List<String> covers) async {
    if (_seriesExtractedColors.containsKey(seriesId) || covers.isEmpty) return;

    final extractedColors = <Color>[];

    for (final url in covers.take(4)) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          CachedNetworkImageProvider(url),
          maximumColorCount: 8,
        );

        if (palette.darkMutedColor != null) {
          extractedColors.add(palette.darkMutedColor!.color);
        }
        if (palette.mutedColor != null) {
          extractedColors.add(palette.mutedColor!.color);
        }
        if (palette.darkVibrantColor != null) {
          extractedColors.add(palette.darkVibrantColor!.color);
        }
        if (palette.dominantColor != null) {
          final hsl = HSLColor.fromColor(palette.dominantColor!.color);
          extractedColors.add(hsl.withLightness((hsl.lightness * 0.4).clamp(0.1, 0.3)).toColor());
        }
      } catch (e) {
        _logger.log('📚 Error extracting colors: $e');
      }
    }

    if (extractedColors.isNotEmpty && mounted) {
      setState(() {
        _seriesExtractedColors[seriesId] = extractedColors;
      });
    }
  }

  static final _logger = DebugLogger();

  Widget _buildContent(double contentHeight, ColorScheme colorScheme, TextTheme textTheme, MusicAssistantProvider maProvider) {
    // Only show loading if we have no data at all
    if (_series.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_series.isEmpty) {
      return Center(
        child: Text(
          S.of(context)!.noSeriesFound,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }

    const textAreaHeight = 44.0;
    final artworkSize = contentHeight - textAreaHeight;
    final cardWidth = artworkSize;
    final itemExtent = cardWidth + 12;

    return ScrollConfiguration(
      behavior: const _StretchScrollBehavior(),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: _series.length,
        itemExtent: itemExtent,
        cacheExtent: 500,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        itemBuilder: (context, index) {
          final s = _series[index];

          // Load covers if not cached
          if (!_seriesCovers.containsKey(s.id) && !_loadingCovers.contains(s.id)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadSeriesCovers(s.id, maProvider);
            });
          }

          return Container(
            key: ValueKey(s.id),
            width: cardWidth,
            margin: const EdgeInsets.symmetric(horizontal: 6.0),
            child: _SeriesCard(
              series: s,
              covers: _seriesCovers[s.id],
              cachedBookCount: _seriesBookCounts[s.id],
              extractedColors: _seriesExtractedColors[s.id],
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('SeriesRow:${widget.title}');
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final maProvider = context.read<MusicAssistantProvider>();

    final totalHeight = widget.rowHeight ?? 237.0;
    const titleHeight = 44.0;
    final contentHeight = totalHeight - titleHeight;

    final result = RepaintBoundary(
      child: SizedBox(
        height: totalHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
              child: Text(
                widget.title,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onBackground,
                ),
              ),
            ),
            Expanded(
              child: _buildContent(contentHeight, colorScheme, textTheme, maProvider),
            ),
          ],
        ),
      ),
    );
    _logger.endBuild('SeriesRow:${widget.title}');
    return result;
  }
}

class _SeriesCard extends StatelessWidget {
  final AudiobookSeries series;
  final List<String>? covers;
  final int? cachedBookCount;
  final List<Color>? extractedColors;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  // Fallback colors when no extracted colors available
  static const _fallbackColors = [
    Color(0xFF2D3436), // Dark slate
    Color(0xFF34495E), // Dark blue-grey
    Color(0xFF4A3728), // Dark brown
    Color(0xFF2C3E50), // Midnight blue
    Color(0xFF3D3D3D), // Charcoal
    Color(0xFF4A4458), // Dark purple-grey
    Color(0xFF3E4A47), // Dark teal-grey
    Color(0xFF4A3F35), // Dark warm grey
  ];

  const _SeriesCard({
    required this.series,
    required this.covers,
    this.cachedBookCount,
    this.extractedColors,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final heroTag = 'series_cover_home_${series.id}';

    return GestureDetector(
      onTap: () {
        // PERF: Use FadeSlidePageRoute for consistent hero animation timing
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: AudiobookSeriesScreen(
              series: series,
              heroTag: heroTag,
              initialCovers: covers,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Use AspectRatio to guarantee square cover
          Hero(
            tag: heroTag,
            // RepaintBoundary caches the rendered grid for smooth animation
            child: RepaintBoundary(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12), // Match detail screen
                  child: _buildCoverGrid(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            series.name,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Builder(
            builder: (context) {
              final count = series.bookCount ?? cachedBookCount;
              if (count == null) return const SizedBox.shrink();
              return Text(
                '$count ${count == 1 ? 'book' : 'books'}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCoverGrid() {
    if (covers == null || covers!.isEmpty) {
      // Static placeholder
      return Container(
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.collections_bookmark_rounded,
            size: 48,
            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
        ),
      );
    }

    // Determine grid size
    int gridSize;
    if (covers!.length == 1) {
      gridSize = 1;
    } else if (covers!.length <= 4) {
      gridSize = 2;
    } else {
      gridSize = 3;
    }

    // Pad covers to fill grid
    final displayCovers = List<String?>.filled(gridSize * gridSize, null);
    for (var i = 0; i < covers!.length && i < displayCovers.length; i++) {
      displayCovers[i] = covers![i];
    }

    // Use series ID to pick consistent colors
    final colorSeed = series.id.hashCode;

    // Get colors for empty cells
    final emptyColors = (extractedColors != null && extractedColors!.isNotEmpty)
        ? extractedColors!
        : _fallbackColors;

    // Build grid using Column/Row (parent AspectRatio ensures square)
    return Column(
      children: List.generate(gridSize, (row) {
        return Expanded(
          child: Row(
            children: List.generate(gridSize, (col) {
              final index = row * gridSize + col;
              final coverUrl = displayCovers[index];

              return Expanded(
                child: coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 192,
                        memCacheHeight: 192,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, __) => Container(
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: colorScheme.surfaceContainerHighest,
                        ),
                      )
                    : _buildEmptyCell(colorSeed, index, emptyColors),
              );
            }),
          ),
        );
      }),
    );
  }

  /// Builds an empty cell with either a solid color or a nested grid
  Widget _buildEmptyCell(int colorSeed, int cellIndex, List<Color> emptyColors) {
    // Tone down colors
    final colors = emptyColors.map((c) {
      final hsl = HSLColor.fromColor(c);
      return hsl
          .withSaturation((hsl.saturation * 0.5).clamp(0.05, 0.25))
          .withLightness((hsl.lightness * 0.7).clamp(0.08, 0.20))
          .toColor();
    }).toList();

    // Use combined seed for deterministic but varied patterns
    final seed = colorSeed + cellIndex * 17;

    // Determine nested grid size: 1 (solid), 2 (2x2), or 3 (3x3)
    // Distribution: ~50% solid, ~30% 2x2, ~20% 3x3
    final sizeRoll = seed.abs() % 100;
    int nestedSize;
    if (sizeRoll < 50) {
      nestedSize = 1;
    } else if (sizeRoll < 80) {
      nestedSize = 2;
    } else {
      nestedSize = 3;
    }

    if (nestedSize == 1) {
      final colorIndex = seed.abs() % colors.length;
      return Container(color: colors[colorIndex]);
    }

    // Build nested grid (seamless)
    return Column(
      children: List.generate(nestedSize, (row) {
        return Expanded(
          child: Row(
            children: List.generate(nestedSize, (col) {
              final nestedIndex = row * nestedSize + col;
              final nestedSeed = seed + nestedIndex * 7;
              final colorIndex = nestedSeed.abs() % colors.length;
              return Expanded(
                child: Container(color: colors[colorIndex]),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _StretchScrollBehavior extends ScrollBehavior {
  const _StretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}
