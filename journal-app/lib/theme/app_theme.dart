import 'package:flutter/material.dart';

class AppColors {
  static const pageBackground = Color(0xFF211C18);
  static const panelBackground = Color(0xFF2A241F);
  static const cardBackground = Color(0xFF332C25);
  static const textPrimary = Color(0xFFEFE7DA);
  static const textSecondary = Color(0xFF8A8074);
  static const accent = Color(0xFFC9915B);
  static const tagBackground = Color(0xFF3D3229);
  static const tagText = Color(0xFFD9A25C);
  static const dateGroupLabelToday = Color(0xFFB08A4E);
  static const dateGroupLabelOlder = Color(0xFF8A8074);
}

final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.pageBackground,
  colorScheme: const ColorScheme.dark(
    surface: AppColors.pageBackground,
    primary: AppColors.accent,
    onPrimary: AppColors.pageBackground,
    secondary: AppColors.accent,
    onSurface: AppColors.textPrimary,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.panelBackground,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
  ),
  cardColor: AppColors.cardBackground,
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: AppColors.textPrimary),
    bodySmall: TextStyle(color: AppColors.textSecondary),
    titleLarge: TextStyle(color: AppColors.textPrimary),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.accent,
    foregroundColor: AppColors.pageBackground,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.pageBackground,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.accent,
      side: const BorderSide(color: AppColors.accent),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
  ),
  chipTheme: const ChipThemeData(
    backgroundColor: AppColors.tagBackground,
    labelStyle: TextStyle(color: AppColors.tagText, fontSize: 12),
    side: BorderSide.none,
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    hintStyle: TextStyle(color: AppColors.textSecondary),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
  ),
  iconTheme: const IconThemeData(color: AppColors.textPrimary),
);

const journalTextStyle = TextStyle(
  fontFamily: 'Lora',
  color: AppColors.textPrimary,
  fontSize: 15,
  height: 1.5,
);
