import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF0B1F33);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const steel = Color(0xFFF1F4F8);
  static const border = Color(0xFFE3E8EF);
  static const amber = Color(0xFFD97706);
  static const amberSoft = Color(0xFFFEF3C7);
  static const orange = Color(0xFFE67E22);
  static const green = Color(0xFF0F766E);
  static const red = Color(0xFFB91C1C);
  static const background = Color(0xFFF6F8FB);

  static const lineColors = [
    navy,
    Color(0xFF0F766E),
    Color(0xFF7C3AED),
    Color(0xFFBE123C),
    Color(0xFF2563EB),
  ];

  static Color status(String status) {
    switch (status) {
      case 'en_cours':
        return amber;
      case 'cloturee':
        return green;
      case 'a_venir':
        return muted;
      case 'published':
        return green;
      case 'no_data':
        return red;
      case 'not_published_yet':
        return amber;
      default:
        return muted;
    }
  }
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.navy,
    primary: AppColors.navy,
    secondary: AppColors.amber,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      indicatorColor: AppColors.amberSoft,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
    ),
  );
}
