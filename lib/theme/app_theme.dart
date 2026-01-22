import 'package:flutter/material.dart';

// Brand colors for Ensemble
const Color brandPrimaryColor = Color(0xFF1a1a1a);
const Color brandAccentColor = Color(0xFF604CEC);

// Predefined accent colors for custom theme selection
const List<Color> accentColorOptions = [
  Color(0xFF604CEC), // Purple (default)
  Color(0xFF2196F3), // Blue
  Color(0xFF009688), // Teal
  Color(0xFFFF5722), // Deep Orange
  Color(0xFFE91E63), // Pink
  Color(0xFF4CAF50), // Green
];

// Brand color schemes (default)
final ColorScheme brandLightColorScheme = ColorScheme.fromSeed(
  seedColor: brandAccentColor,
  brightness: Brightness.light,
  background: const Color(0xFFFAFAFA),
  onBackground: const Color(0xFF1a1a1a), // Ensure dark text
  surface: const Color(0xFFFFFFFF),
  onSurface: const Color(0xFF1a1a1a), // Ensure dark text
);

final ColorScheme brandDarkColorScheme = ColorScheme.fromSeed(
  seedColor: brandAccentColor,
  brightness: Brightness.dark,
  surface: const Color(0xFF2a2a2a),
  background: const Color(0xFF1a1a1a),
);

// Generate color schemes from a custom seed color
ColorScheme generateLightColorScheme(Color seedColor) {
  return ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
    background: const Color(0xFFFAFAFA),
    onBackground: const Color(0xFF1a1a1a),
    surface: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF1a1a1a),
  );
}

ColorScheme generateDarkColorScheme(Color seedColor) {
  return ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.dark,
    surface: const Color(0xFF2a2a2a),
    background: const Color(0xFF1a1a1a),
  );
}

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
      cardTheme: CardThemeData(
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
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 2,
      ),
      fontFamily: 'Roboto',
    );
  }
}
