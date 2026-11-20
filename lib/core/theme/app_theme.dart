import 'package:flutter/material.dart';

/// Shared Numelixa mobile design tokens. Keep every screen on this palette.
class AppTheme {
  AppTheme._();

  static const navy = Color(0xFF050B18);
  static const backgroundElevated = Color(0xFF081329);
  static const panel = Color(0xFF0D1930);
  static const panelRaised = Color(0xFF12213B);
  static const blue = Color(0xFF4388FF);
  static const electricBlue = Color(0xFF35D6E3);
  static const cyan = Color(0xFF35D6E3);
  static const violet = Color(0xFFA64DFF);
  static const mint = Color(0xFF35C98A);
  static const warning = Color(0xFFFFB547);
  static const error = Color(0xFFFF647C);
  static const muted = Color(0xFF98A9C2);
  static const glassBorder = Color(0xFF263957);
  static const textPrimary = Color(0xFFF4F7FC);
  static const textSecondary = Color(0xFF98A9C2);

  static const radiusSmall = 12.0;
  static const radiusMedium = 16.0;
  static const radiusLarge = 22.0;
  static const radiusXLarge = 28.0;

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: navy,
    colorScheme: const ColorScheme.dark(
      primary: blue,
      secondary: cyan,
      tertiary: violet,
      surface: panel,
      error: error,
    ),
    useMaterial3: true,
    fontFamily: 'Roboto',
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(
      backgroundColor: navy,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -.35,
      ),
      iconTheme: IconThemeData(color: textPrimary),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: backgroundElevated,
      elevation: 0,
      height: 68,
      indicatorColor: blue.withValues(alpha: .18),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? cyan : muted,
        size: 22,
      )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        color: states.contains(WidgetState.selected) ? textPrimary : muted,
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
      )),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: panelRaised,
      contentTextStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: backgroundElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: muted),
      labelStyle: const TextStyle(color: Color(0xFFCDDAEC), fontWeight: FontWeight.w600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: cyan, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: error, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
        side: const BorderSide(color: glassBorder),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: blue,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: blue,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: cyan, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
    ),
    dividerColor: glassBorder,
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: cyan),
    chipTheme: ChipThemeData(
      backgroundColor: backgroundElevated,
      selectedColor: blue.withValues(alpha: .22),
      side: const BorderSide(color: glassBorder),
      labelStyle: const TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
    ),
  );
}
