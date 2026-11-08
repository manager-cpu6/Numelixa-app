import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();
  static const navy = Color(0xFF030817);
  static const panel = Color(0xFF0A1830);
  static const panelRaised = Color(0xFF102344);
  static const blue = Color(0xFF792BFF);
  static const cyan = Color(0xFFC45BFF);
  static const violet = Color(0xFF5B18D6);
  static const magenta = Color(0xFFE83AA8);
  static const mint = Color(0xFF00E5C3);
  static const muted = Color(0xFF9DB1CE);

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: navy,
    colorScheme: const ColorScheme.dark(
      primary: blue,
      secondary: cyan,
      tertiary: violet,
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
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.35),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: panelRaised,
      contentTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF07152B),
      contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
      hintStyle: const TextStyle(color: muted),
      labelStyle: const TextStyle(color: Color(0xFFCDDAEC), fontWeight: FontWeight.w600),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFF263F62))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFF263F62))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: cyan, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFFFF647C))),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFFFF647C), width: 1.5)),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(23),
        side: const BorderSide(color: Color(0xFF263F62)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: blue,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: blue,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: cyan, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
    ),
    dividerColor: const Color(0xFF263F62),
  );
}
