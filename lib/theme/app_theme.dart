import 'package:flutter/material.dart';

// Brand colors for Amass
const Color brandPrimaryColor = Color(0xFF1a1a1a);
const Color brandAccentColor = Color(0xFF604CEC);

// Brand color schemes
final ColorScheme brandLightColorScheme = ColorScheme.fromSeed(
  seedColor: brandAccentColor,
  brightness: Brightness.light,
);

final ColorScheme brandDarkColorScheme = ColorScheme.fromSeed(
  seedColor: brandAccentColor,
  brightness: Brightness.dark,
  surface: const Color(0xFF2a2a2a),
  background: const Color(0xFF1a1a1a),
);

class AppTheme {
  // Generate light theme
  static ThemeData lightTheme({ColorScheme? colorScheme}) {
    final scheme = colorScheme ?? brandLightColorScheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: scheme.onBackground,
        iconTheme: IconThemeData(color: scheme.onBackground),
      ),
      cardTheme: CardTheme(
        color: scheme.surface,
        elevation: 2,
      ),
      fontFamily: 'Roboto',
    );
  }

  // Generate dark theme
  static ThemeData darkTheme({ColorScheme? colorScheme}) {
    final scheme = colorScheme ?? brandDarkColorScheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: scheme.onBackground,
        iconTheme: IconThemeData(color: scheme.onBackground),
      ),
      cardTheme: CardTheme(
        color: scheme.surface,
        elevation: 2,
      ),
      fontFamily: 'Roboto',
    );
  }

  // Apply high contrast modifications to a color scheme
  static ColorScheme applyHighContrast(ColorScheme scheme, Brightness brightness) {
    return scheme.copyWith(
      surface: brightness == Brightness.light ? Colors.white : Colors.black,
      background: brightness == Brightness.light ? Colors.white : Colors.black,
    );
  }
}
