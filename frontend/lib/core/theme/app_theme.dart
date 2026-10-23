import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

class AppTheme {
  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -0.8),
    displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5),
    headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4),
    headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.1),
    titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.4),
    bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.4),
    bodySmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.3),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.2),
  );

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E3A8A),
      primary: const Color(0xFF1E3A8A),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDBEAFE),
      onPrimaryContainer: const Color(0xFF1E40AF),
      secondary: const Color(0xFF0D9488),
      surface: const Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    textTheme: _textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF0F172A),
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      primary: const Color(0xFF3B82F6),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF1E3A8A),
      onPrimaryContainer: const Color(0xFFBFDBFE),
      secondary: const Color(0xFF14B8A6),
      surface: const Color(0xFF1E293B),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF0F172A),
    textTheme: _textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E293B),
      foregroundColor: Color(0xFFF8FAFC),
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFF8FAFC)),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E293B),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF334155), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0F172A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF334155), width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
    ),
  );
}
