import 'package:flutter/material.dart';
import '../widgets/mini_player.dart';
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
  int _selectedIndex = 0;
  final GlobalKey<SearchScreenState> _searchScreenKey = GlobalKey<SearchScreenState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvoked: (didPop) {
        if (didPop) return;
        setState(() {
          _selectedIndex = 0;
        });
      },
      child: Scaffold(
        backgroundColor: colorScheme.background,
        body: Stack(
          children: [
            // Home and Library use IndexedStack for state preservation
            Offstage(
              offstage: _selectedIndex > 1,
              child: IndexedStack(
                index: _selectedIndex.clamp(0, 1),
                children: const [
                  NewHomeScreen(),
                  NewLibraryScreen(),
                ],
              ),
            ),
            // Search and Settings are conditionally rendered (removed from tree when not visible)
            if (_selectedIndex == 2)
              SearchScreen(key: _searchScreenKey),
            if (_selectedIndex == 3)
              const SettingsScreen(),
            // Floating mini player - positioned above bottom nav, hidden on settings
            if (_selectedIndex != 3)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: const MiniPlayer(),
              ),
          ],
        ),
        bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });

                  // Auto-focus search field when switching to search tab
                  if (index == 2) {
                    // Use post-frame callback to ensure SearchScreen is built first
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _searchScreenKey.currentState?.requestFocus();
                    });
                  }
                },
                backgroundColor: Colors.transparent,
                selectedItemColor: colorScheme.primary,
                unselectedItemColor: colorScheme.onSurface.withOpacity(0.54),
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedFontSize: 12,
                unselectedFontSize: 12,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.library_music_outlined),
                    activeIcon: Icon(Icons.library_music_rounded),
                    label: 'Library',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.search_rounded),
                    activeIcon: Icon(Icons.search_rounded),
                    label: 'Search',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.settings_outlined),
                    activeIcon: Icon(Icons.settings_rounded),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
