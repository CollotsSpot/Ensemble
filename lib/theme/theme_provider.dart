import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import 'palette_helper.dart';

/// Global function to update adaptive colors from an image URL
/// This can be called from anywhere in the app (e.g., when tapping an album/artist)
Future<void> updateAdaptiveColorsFromImage(BuildContext context, String? imageUrl) async {
  if (imageUrl == null || imageUrl.isEmpty) return;

  try {
    final colorSchemes = await PaletteHelper.extractColorSchemes(NetworkImage(imageUrl));
    if (colorSchemes != null && context.mounted) {
      final themeProvider = context.read<ThemeProvider>();
      themeProvider.updateAdaptiveColors(colorSchemes.$1, colorSchemes.$2);
    }
  } catch (e) {
    // Silently fail - colors will update when track plays
    print('Failed to extract colors on tap: $e');
  }
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _useMaterialTheme = false;
  bool _adaptiveTheme = true;
  Color _customColor = const Color(0xFF604CEC);

  // Adaptive colors extracted from current album art
  AdaptiveColors? _adaptiveColors;
  ColorScheme? _adaptiveLightScheme;
  ColorScheme? _adaptiveDarkScheme;

  ThemeProvider() {
    _loadSettings();
  }

  ThemeMode get themeMode => _themeMode;
  bool get useMaterialTheme => _useMaterialTheme;
  bool get adaptiveTheme => _adaptiveTheme;
  Color get customColor => _customColor;

  // Adaptive color getters
  AdaptiveColors? get adaptiveColors => _adaptiveColors;
  ColorScheme? get adaptiveLightScheme => _adaptiveLightScheme;
  ColorScheme? get adaptiveDarkScheme => _adaptiveDarkScheme;

  /// Get the current adaptive primary color (for bottom nav, etc.)
  Color get adaptivePrimaryColor => _adaptiveColors?.primary ?? _customColor;

  Future<void> _loadSettings() async {
    final themeModeString = await SettingsService.getThemeMode();
    _themeMode = _parseThemeMode(themeModeString);

    _useMaterialTheme = await SettingsService.getUseMaterialTheme();
    _adaptiveTheme = await SettingsService.getAdaptiveTheme();

    final colorString = await SettingsService.getCustomColor();
    if (colorString != null) {
      _customColor = _parseColor(colorString);
    }

    notifyListeners();
  }

  ThemeMode _parseThemeMode(String? mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  Color _parseColor(String colorString) {
    try {
      // Remove # if present
      final hex = colorString.replaceAll('#', '');
      // Add FF for alpha if not present
      final hexWithAlpha = hex.length == 6 ? 'FF$hex' : hex;
      return Color(int.parse(hexWithAlpha, radix: 16));
    } catch (e) {
      return const Color(0xFF604CEC); // Default color
    }
  }

  String _colorToString(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await SettingsService.saveThemeMode(_themeModeToString(mode));
    notifyListeners();
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setUseMaterialTheme(bool enabled) async {
    _useMaterialTheme = enabled;
    await SettingsService.saveUseMaterialTheme(enabled);
    notifyListeners();
  }

  Future<void> setAdaptiveTheme(bool enabled) async {
    _adaptiveTheme = enabled;
    await SettingsService.saveAdaptiveTheme(enabled);
    notifyListeners();
  }

  Future<void> setCustomColor(Color color) async {
    _customColor = color;
    await SettingsService.saveCustomColor(_colorToString(color));
    notifyListeners();
  }

  /// Update adaptive colors from album art
  void updateAdaptiveColors(ColorScheme? lightScheme, ColorScheme? darkScheme) {
    _adaptiveLightScheme = lightScheme;
    _adaptiveDarkScheme = darkScheme;

    // Extract AdaptiveColors from the schemes
    if (darkScheme != null) {
      _adaptiveColors = AdaptiveColors(
        primary: darkScheme.primary,
        surface: darkScheme.surface,
        onSurface: darkScheme.onSurface,
        miniPlayer: darkScheme.primaryContainer,
      );
    } else {
      _adaptiveColors = null;
    }

    notifyListeners();
  }

  /// Clear adaptive colors (when no track is playing)
  void clearAdaptiveColors() {
    _adaptiveColors = null;
    _adaptiveLightScheme = null;
    _adaptiveDarkScheme = null;
    notifyListeners();
  }
}
