/// Theme-mode (light/dark/system) controller persisted across launches.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/session_storage.dart';

/// The persisted theme mode preference.
enum ApexThemeMode { system, light, dark }

extension ApexThemeModeX on ApexThemeMode {
  ThemeMode toMaterial() {
    switch (this) {
      case ApexThemeMode.system:
        return ThemeMode.system;
      case ApexThemeMode.light:
        return ThemeMode.light;
      case ApexThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  String get label {
    switch (this) {
      case ApexThemeMode.system:
        return 'System';
      case ApexThemeMode.light:
        return 'Light';
      case ApexThemeMode.dark:
        return 'Dark';
    }
  }
}

const _kThemeMode = 'apex_theme_mode';

class ThemeController extends Notifier<ApexThemeMode> {
  @override
  ApexThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final raw = prefs.getString(_kThemeMode);
    return switch (raw) {
      'light' => ApexThemeMode.light,
      'dark' => ApexThemeMode.dark,
      _ => ApexThemeMode.system,
    };
  }

  Future<void> set(ApexThemeMode mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kThemeMode, mode.name);
  }
}

/// Provider for the theme-mode controller.
final themeControllerProvider =
    NotifierProvider<ThemeController, ApexThemeMode>(ThemeController.new);

/// Convenience: derives the effective [ApexThemeMode] taking system into
/// account when the preference is `system`.
ApexThemeMode resolvedThemeMode(BuildContext context, ApexThemeMode pref) {
  if (pref != ApexThemeMode.system) return pref;
  final platform = MediaQuery.platformBrightnessOf(context);
  return platform == Brightness.dark ? ApexThemeMode.dark : ApexThemeMode.light;
}
