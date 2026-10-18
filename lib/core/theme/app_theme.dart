import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();
  static const navy = Color(0xFF030817);
  static const panel = Color(0xFF0A1830);
  static const blue = Color(0xFF1677FF);
  static const cyan = Color(0xFF00D9FF);
  static const mint = Color(0xFF00E5C3);

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: navy,
        colorScheme: const ColorScheme.dark(
          primary: blue,
          secondary: cyan,
          surface: panel,
          error: Color(0xFFFF647C),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF203653)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF203653)),
          ),
        ),
        cardTheme: CardThemeData(
          color: panel,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFF1C3150)),
          ),
        ),
      );
}
