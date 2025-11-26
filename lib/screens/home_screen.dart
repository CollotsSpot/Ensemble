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
        if (didPop) {
          // When returning from a pushed screen, unfocus search if not on search tab
          if (_selectedIndex != 2) {
            _searchScreenKey.currentState?.removeFocus();
          }
          return;
        }

        // Unfocus search when using back button to go to home
        if (_selectedIndex == 2) {
          _searchScreenKey.currentState?.removeFocus();
        }

        setState(() {
          _selectedIndex = 0;
        });
      },
      child: Scaffold(
        backgroundColor: colorScheme.background,
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            const NewHomeScreen(),
            const NewLibraryScreen(),
            SearchScreen(key: _searchScreenKey),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini player
            const MiniPlayer(),

            // Bottom navigation bar
            Container(
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
                  // Unfocus search field when leaving search tab
                  if (_selectedIndex == 2 && index != 2) {
                    _searchScreenKey.currentState?.removeFocus();
                  }

                  setState(() {
                    _selectedIndex = index;
                  });

                  // Auto-focus search field when switching to search tab
                  if (index == 2) {
                    _searchScreenKey.currentState?.requestFocus();
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
          ],
        ),
      ),
    );
  }
}
