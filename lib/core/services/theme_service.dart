import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages app theme preference (light, dark, system default) and persists it using SharedPreferences.
class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const String _themeKey = 'user_theme_mode';
  late SharedPreferences _prefs;
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
    ThemeMode.system,
  );

  /// Initialize preference loading.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final savedMode = _prefs.getString(_themeKey);
    if (savedMode != null) {
      themeModeNotifier.value = ThemeMode.values.firstWhere(
        (e) => e.name == savedMode,
        orElse: () => ThemeMode.system,
      );
    }
  }

  /// Get current theme mode.
  ThemeMode get themeMode => themeModeNotifier.value;

  /// Check if dark mode is active (either explicitly or via system default).
  bool isDarkMode(BuildContext context) {
    if (themeMode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return themeMode == ThemeMode.dark;
  }

  /// Toggle between light and dark theme mode.
  Future<void> toggleTheme(BuildContext context) async {
    final activeDark = isDarkMode(context);
    final newMode = activeDark ? ThemeMode.light : ThemeMode.dark;
    themeModeNotifier.value = newMode;
    await _prefs.setString(_themeKey, newMode.name);
  }

  /// Set a specific theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    await _prefs.setString(_themeKey, mode.name);
  }
}
