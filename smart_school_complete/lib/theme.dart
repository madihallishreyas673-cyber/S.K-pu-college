import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const ink = Color(0xFF101936);       // page background
  static const surface = Color(0xFF1A2447);   // cards
  static const surfaceHi = Color(0xFF243063); // raised / selected
  static const line = Color(0xFF2E3A70);
  static const brass = Color(0xFFE3B25C);     // single accent
  static const mint = Color(0xFF5FD3A9);      // present / good
  static const coral = Color(0xFFF07A6E);     // absent / low
  static const amber = Color(0xFFF2C14E);     // near threshold
  static const text = Color(0xFFEDEFF7);
  static const muted = Color(0xFFA3ABCF);
}

TextStyle display(double size, {FontWeight w = FontWeight.w600, Color c = AppColors.text}) =>
    GoogleFonts.fraunces(fontSize: size, fontWeight: w, color: c, height: 1.15);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final text = GoogleFonts.figtreeTextTheme(base.textTheme)
      .apply(bodyColor: AppColors.text, displayColor: AppColors.text);
  OutlineInputBorder border(Color c) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c));
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.ink,
    textTheme: text,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.brass, onPrimary: AppColors.ink, surface: AppColors.surface,
      onSurface: AppColors.text, error: AppColors.coral,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.ink, elevation: 0, scrolledUnderElevation: 0,
      titleTextStyle: display(20),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface, elevation: 0, margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: AppColors.surface,
      border: border(AppColors.line), enabledBorder: border(AppColors.line),
      focusedBorder: border(AppColors.brass), errorBorder: border(AppColors.coral),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
