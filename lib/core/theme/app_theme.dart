/*
 * File: app_theme.dart
 * Description: Main theme configuration for TelStorage.
 * Configures Material 3 Light and Dark ThemeData, Typography, and AppColorsExtension.
 */

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_colors_extension.dart';

export 'app_colors.dart';
export 'app_colors_extension.dart';

/// TelStorage Design System — Pure Dark & Clean Light UI.
class AppTheme {
  // ── Text Styles Generator ────────────────────────────────────────────────

  /// Builds a responsive text theme based on brightness.
  static TextTheme _textTheme(Brightness b) {
    final isDark = b == Brightness.dark;
    final primaryColor = isDark ? AppColors.white : AppColors.black;
    final secondaryColor =
        isDark ? AppColors.grey600 : AppColors.textSecondaryLight;

    return GoogleFonts.interTextTheme().copyWith(
      displayLarge: GoogleFonts.inter(
          fontSize: 28, fontWeight: FontWeight.w700, color: primaryColor),
      headlineLarge: GoogleFonts.inter(
          fontSize: 24, fontWeight: FontWeight.w700, color: primaryColor),
      headlineMedium: GoogleFonts.inter(
          fontSize: 20, fontWeight: FontWeight.w700, color: primaryColor),
      headlineSmall: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w700, color: primaryColor),
      titleLarge: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w600, color: primaryColor),
      titleMedium: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.w600, color: primaryColor),
      titleSmall: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w600, color: primaryColor),
      bodyLarge: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.w400, color: primaryColor),
      bodyMedium: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.w400, color: secondaryColor),
      bodySmall: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w400, color: secondaryColor),
      labelLarge: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w600, color: primaryColor),
    );
  }

  // ── Dark Theme Configuration ────────────────────────────────────────────

  /// Generates the dark Material 3 theme configuration.
  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.black,
        colorScheme: const ColorScheme.dark(
          surface: AppColors.grey900,
          primary: AppColors.white,
          onPrimary: AppColors.black,
          secondary: AppColors.grey600,
          error: AppColors.error,
        ),
        textTheme: _textTheme(Brightness.dark),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.black,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: AppColors.white),
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.white,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.grey900,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.grey800,
          thickness: 1,
          space: 0,
        ),
        iconButtonTheme: const IconButtonThemeData(
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
        ),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        extensions: const [
          AppColorsExtension(
            bgPrimary: AppColors.black,
            bgSurface: AppColors.grey900,
            bgSurfaceInset: AppColors.grey800,
            borderSubtle: AppColors.grey800,
            textPrimary: AppColors.white,
            textSecondary: AppColors.grey600,
            textTertiary: AppColors.grey700,
            accentPrimary: AppColors.white,
            filePdf: AppColors.filePdf,
            fileVideo: AppColors.fileVideo,
            fileZip: AppColors.fileZip,
            fileFolder: AppColors.fileFolder,
            fileFolderBg: AppColors.fileFolderBgDark,
            filePalette: AppColors.filePalette,
            fileVideoBg: AppColors.grey800,
            fileTextBg: AppColors.grey800,
            fileGenericBg: AppColors.grey800,
            filePdfBg: AppColors.filePdfBgDark,
            glowColor: AppColors.glowDark,
            heroGradient: [AppColors.black, AppColors.grey900],
            primaryGradient: [AppColors.white, AppColors.white],
            selectionColor: AppColors.grey800,
            selectionColorAlt: AppColors.grey800,
            success: AppColors.success,
            error: AppColors.error,
            warning: AppColors.warning,
          ),
        ],
      );

  // ── Light Theme Configuration ───────────────────────────────────────────

  /// Generates the light Material 3 theme configuration.
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.white,
        colorScheme: const ColorScheme.light(
          surface: AppColors.grey100,
          primary: AppColors.black,
          onPrimary: AppColors.white,
          secondary: AppColors.textSecondaryLight,
          error: AppColors.error,
        ),
        textTheme: _textTheme(Brightness.light),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: AppColors.black),
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.grey100,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.grey300,
          thickness: 1,
          space: 0,
        ),
        iconButtonTheme: const IconButtonThemeData(
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
        ),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        extensions: const [
          AppColorsExtension(
            bgPrimary: AppColors.white,
            bgSurface: AppColors.grey100,
            bgSurfaceInset: AppColors.grey200,
            borderSubtle: AppColors.grey300,
            textPrimary: AppColors.black,
            textSecondary: AppColors.textSecondaryLight,
            textTertiary: AppColors.textTertiaryLight,
            accentPrimary: AppColors.black,
            filePdf: AppColors.filePdf,
            fileVideo: AppColors.fileVideo,
            fileZip: AppColors.fileZip,
            fileFolder: AppColors.fileFolder,
            fileFolderBg: AppColors.fileFolderBgLight,
            filePalette: AppColors.filePalette,
            fileVideoBg: AppColors.fileVideoBgLight,
            fileTextBg: AppColors.fileTextBgLight,
            fileGenericBg: AppColors.grey50,
            filePdfBg: AppColors.filePdfBgLight,
            glowColor: AppColors.glowLight,
            heroGradient: [AppColors.white, AppColors.grey100],
            primaryGradient: [AppColors.black, AppColors.black],
            selectionColor: AppColors.grey300,
            selectionColorAlt: AppColors.grey300,
            success: AppColors.success,
            error: AppColors.error,
            warning: AppColors.warning,
          ),
        ],
      );
}
