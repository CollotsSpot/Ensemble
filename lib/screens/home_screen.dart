import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../l10n/app_localizations.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/navigation_provider.dart';
import '../theme/theme_provider.dart';
import '../widgets/global_player_overlay.dart';
import 'new_home_screen.dart';
import 'new_library_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<SearchScreenState> _searchScreenKey = GlobalKey<SearchScreenState>();
  DateTime? _lastBackPress;
  final _cachedNavColor = _CachedNavColor();

  @override
  void initState() {
    super.initState();
    // Register search focus callback with navigation provider
    navigationProvider.onSearchTabSelected = () {
      _searchScreenKey.currentState?.requestFocus();
    };
  }

  @override
  void dispose() {
    // Clean up callback
    navigationProvider.onSearchTabSelected = null;
    super.dispose();
  }

  void _showExitSnackBar() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context)!.pressBackToMinimize),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: navigationProvider,
      builder: (context, _) {
        final selectedIndex = navigationProvider.selectedIndex;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;

            // If player reveal (device list) is visible, dismiss it first (with animation)
            if (GlobalPlayerOverlay.isPlayerRevealVisible) {
              GlobalPlayerOverlay.dismissPlayerReveal();
              return;
            }

            // If queue panel is open, close it first (before collapsing player)
            if (GlobalPlayerOverlay.isQueuePanelOpen) {
              GlobalPlayerOverlay.closeQueuePanel();
              return;
            }

            // If global player is expanded, collapse it first
            if (GlobalPlayerOverlay.isPlayerExpanded) {
              GlobalPlayerOverlay.collapsePlayer();
              return;
            }

            // If not on home tab, navigate to home
            if (selectedIndex != 0) {
              // If leaving Settings, show player again
              if (selectedIndex == 3) {
                GlobalPlayerOverlay.showPlayer();
              }
              navigationProvider.setSelectedIndex(0);
              return;
            }

            // On home tab - check for double press to minimize
            final now = DateTime.now();
            if (_lastBackPress != null &&
                now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
              // Double press detected - minimize app (move to background)
              // This keeps the app running and connection alive
              SystemNavigator.pop();
            } else {
              // First press, show message
              _lastBackPress = now;
              _showExitSnackBar();
            }
          },
          child: Scaffold(
            backgroundColor: colorScheme.surface,
            // extendBody: true preserves the existing layout where content fills the
            // full screen and screens manage their own bottom padding (BottomSpacing).
            // Without this, Scaffold would constrain the body above the nav bar,
            // causing double bottom spacing.
            extendBody: true,
            // BottomNavigationBar requires an Overlay ancestor (for Tooltip);
            // Scaffold inside Navigator provides one. Previously it was in
            // GlobalPlayerOverlay's Stack (outside Navigator) causing crashes.
            bottomNavigationBar: _buildBottomNavigationBar(context, colorScheme),
            body: Stack(
              children: [
                // Home and Library use IndexedStack for state preservation
                Offstage(
                  offstage: selectedIndex > 1,
                  child: IndexedStack(
                    index: selectedIndex.clamp(0, 1),
                    children: const [
                      NewHomeScreen(),
                      NewLibraryScreen(),
                    ],
                  ),
                ),
                // Search and Settings are conditionally rendered (removed from tree when not visible)
                if (selectedIndex == 2)
                  SearchScreen(key: _searchScreenKey),
                if (selectedIndex == 3)
                  const SettingsScreen(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build the bottom navigation bar with adaptive colors and player expansion animation.
  /// Moved here from GlobalPlayerOverlay so it has proper Overlay ancestry
  /// (required by BottomNavigationBar's internal Tooltip widgets).
  Widget? _buildBottomNavigationBar(BuildContext context, ColorScheme colorScheme) {
    // Hide nav bar when not connected
    final isConnected = context.select<MusicAssistantProvider, bool>(
      (p) => p.isConnected,
    );
    if (!isConnected) return null;

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return ValueListenableBuilder<PlayerExpansionState>(
          valueListenable: playerExpansionNotifier,
          builder: (context, expansionState, _) {
            // Nav bar color logic - only use adaptive colors when:
            // 1. Player is expanding/expanded, OR
            // 2. On a detail screen (isOnDetailScreen)
            // On home screen with collapsed player: always use default theme colors
            final bool useAdaptiveColors = themeProvider.adaptiveTheme &&
                (expansionState.progress > 0 || themeProvider.isOnDetailScreen);

            // Nav bar background color
            final Color navBgColor;
            if (expansionState.progress > 0 && expansionState.backgroundColor != null) {
              // Player is expanding - blend from surface to player's adaptive color
              navBgColor = Color.lerp(colorScheme.surface, expansionState.backgroundColor, expansionState.progress)!;
            } else if (useAdaptiveColors) {
              // On a detail screen - use adaptive surface color for nav bar
              final adaptiveBg = themeProvider.getAdaptiveSurfaceColorFor(Theme.of(context).brightness);
              navBgColor = adaptiveBg ?? colorScheme.surface;
            } else {
              // Home screen with collapsed player - use default surface color
              navBgColor = colorScheme.surface;
            }

            // Icon color - only use adaptive colors when appropriate
            final Color baseSourceColor = (useAdaptiveColors && themeProvider.adaptiveColors != null)
                ? themeProvider.adaptiveColors!.primary
                : colorScheme.primary;

            // Blend icon color with player's primary color during expansion
            Color sourceColor = baseSourceColor;
            if (themeProvider.adaptiveTheme && expansionState.progress > 0 && expansionState.primaryColor != null) {
              sourceColor = Color.lerp(baseSourceColor, expansionState.primaryColor!, expansionState.progress)!;
            }
            final navSelectedColor = _cachedNavColor.getAdjustedColor(sourceColor, isDark);

            // Fade out and slide down nav bar as player expands
            // Use IgnorePointer when faded to prevent accidental taps
            final navOpacity = (1.0 - expansionState.progress * 2).clamp(0.0, 1.0);
            final navSlideDown = expansionState.progress * 20; // Slide down 20px as it fades

            return IgnorePointer(
              ignoring: navOpacity < 0.1,
              child: Transform.translate(
                offset: Offset(0, navSlideDown),
                child: Opacity(
                  opacity: navOpacity,
                  child: Container(
                    decoration: BoxDecoration(
                      color: navBgColor,
                      boxShadow: expansionState.progress < 0.5
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, -2),
                              ),
                            ]
                          : null,
                    ),
                    child: BottomNavigationBar(
                      currentIndex: navigationProvider.selectedIndex,
                      onTap: (index) {
                        if (GlobalPlayerOverlay.isPlayerExpanded) {
                          GlobalPlayerOverlay.collapsePlayer();
                        }
                        navigationProvider.navigatorKey.currentState?.popUntil((route) => route.isFirst);
                        // Clear adaptive colors when switching tabs (detail screen colors shouldn't persist)
                        themeProvider.clearAdaptiveColors();
                        if (index == 3) {
                          GlobalPlayerOverlay.hidePlayer();
                        } else if (navigationProvider.selectedIndex == 3) {
                          GlobalPlayerOverlay.showPlayer();
                        }
                        navigationProvider.setSelectedIndex(index);
                      },
                      backgroundColor: Colors.transparent,
                      selectedItemColor: navSelectedColor,
                      unselectedItemColor: colorScheme.onSurface.withOpacity(0.54),
                      elevation: 0,
                      type: BottomNavigationBarType.fixed,
                      selectedFontSize: 12,
                      unselectedFontSize: 12,
                      items: [
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.home_outlined),
                          activeIcon: const Icon(Icons.home_rounded),
                          label: S.of(context)!.home,
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Symbols.book_2, fill: 0),
                          activeIcon: const Icon(Symbols.book_2, fill: 1),
                          label: S.of(context)!.library,
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.search_rounded),
                          activeIcon: const Icon(Icons.search_rounded),
                          label: S.of(context)!.search,
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.settings_outlined),
                          activeIcon: const Icon(Icons.settings_rounded),
                          label: S.of(context)!.settings,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Cached color with contrast adjustment for nav bar icon colors.
/// Avoids expensive HSL conversions during scroll/animation.
class _CachedNavColor {
  Color? _sourceColor;
  bool? _isDark;
  Color? _adjustedColor;

  Color getAdjustedColor(Color sourceColor, bool isDark) {
    if (_sourceColor == sourceColor && _isDark == isDark && _adjustedColor != null) {
      return _adjustedColor!;
    }

    var navSelectedColor = sourceColor;
    if (isDark && navSelectedColor.computeLuminance() < 0.2) {
      final hsl = HSLColor.fromColor(navSelectedColor);
      navSelectedColor = hsl.withLightness((hsl.lightness + 0.3).clamp(0.0, 0.8)).toColor();
    } else if (!isDark && navSelectedColor.computeLuminance() > 0.8) {
      final hsl = HSLColor.fromColor(navSelectedColor);
      navSelectedColor = hsl.withLightness((hsl.lightness - 0.3).clamp(0.2, 1.0)).toColor();
    }

    _sourceColor = sourceColor;
    _isDark = isDark;
    _adjustedColor = navSelectedColor;
    return navSelectedColor;
  }
}
