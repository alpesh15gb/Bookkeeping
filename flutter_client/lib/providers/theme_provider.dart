import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('dark_mode') ?? false;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _isDarkMode);
    notifyListeners();
  }

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  // Dark color tokens
  static const Color _bgDark = Color(0xFF0F1117);
  static const Color _surfaceDark = Color(0xFF1A1D26);
  static const Color _sidebarDark = Color(0xFF0B1B3D);
  static const Color _borderDark = Color(0xFF2D3139);

  static const Color _goldAccent = Color(0xFFDCA035);
  static const Color _brandNavy = Color(0xFF0B1B3D);
  static const Color _bgLight = Color(0xFFF8F9FC);
  static const Color _surfaceLight = Colors.white;
  static const Color _errorLight = Color(0xFFD32F2F);
  static const Color _borderLight = Color(0xFFD1D5DC);

  ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: _bgLight,
    colorScheme: const ColorScheme.light(
      primary: _brandNavy,
      secondary: _goldAccent,
      surface: _surfaceLight,
      error: _errorLight,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _bgLight,
      foregroundColor: _brandNavy,
      iconTheme: IconThemeData(color: _brandNavy),
      actionsIconTheme: IconThemeData(color: _brandNavy),
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: _surfaceLight,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _brandNavy, width: 1.5),
      ),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(_surfaceLight),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _surfaceLight,
      modalBarrierColor: Colors.black54,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _bgDark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFDCA035),
      secondary: Color(0xFFDCA035),
      surface: _surfaceDark,
      error: Color(0xFFEF5350),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _sidebarDark,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: _surfaceDark,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _borderDark),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _surfaceDark,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: _sidebarDark,
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(_surfaceDark),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _surfaceDark,
      modalBarrierColor: Colors.black87,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
