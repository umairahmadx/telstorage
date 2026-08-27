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
  // ── Color Aliases (Mapped to centralized AppColors) ───────────────────────

  /// Pure black.
  static const Color black = AppColors.black;

  /// Pure white.
  static const Color white = AppColors.white;

  /// Surface dark tone.
  static const Color grey900 = AppColors.grey900;

  /// Elevated card border tone.
  static const Color grey800 = AppColors.grey800;

  /// Muted text tone.
  static const Color grey700 = AppColors.grey700;

  /// Secondary text tone.
  static const Color grey600 = AppColors.grey600;

  /// Surface inset tone.
  static const Color grey200 = AppColors.grey200;

  /// Surface container light tone.
  static const Color grey100 = AppColors.grey100;

  /// Navy container dark tone.
  static const Color navy900 = AppColors.navy900;

  /// Navy card surface tone.
  static const Color navy800 = AppColors.navy800;

  /// Navy soft tone.
  static const Color navy700 = AppColors.navy700;

  /// Navy subtle tone.
  static const Color navy600 = AppColors.navy600;

  /// Primary brand color.
  static const Color primary = AppColors.primary;

  /// Primary light brand color.
  static const Color primaryLight = AppColors.primaryLight;

  /// Accent golden color.
  static const Color accent = AppColors.accent;

  /// Success state color.
  static const Color success = AppColors.success;

  /// Error state color.
  static const Color error = AppColors.error;

  /// Warning state color.
  static const Color warning = AppColors.warning;

  // ── File Type Indicator Colors ──────────────────────────────────────────

  /// PDF badge color.
  static const Color filePdf = AppColors.filePdf;

  /// Video badge color.
  static const Color fileVideo = AppColors.fileVideo;

  /// Zip archive badge color.
  static const Color fileZip = AppColors.fileZip;

  /// Text badge color.
  static const Color fileText = AppColors.fileText;

  /// Presentation badge color.
  static const Color filePptx = AppColors.filePptx;

  /// Folder badge color.
  static const Color fileFolder = AppColors.fileFolder;

  /// Image palette badge color.
  static const Color filePalette = AppColors.filePalette;

  // ── Legacy Compatibility Aliases ─────────────────────────────────────────

  /// Danger alias for error.
  static const Color danger = error;

  /// Surface default dark tone.
  static const Color surface = grey900;

  /// Subtle border color.
  static const Color borderSubtle = grey800;

  // ── Text Styles Generator ────────────────────────────────────────────────

  /// Builds a responsive text theme based on brightness.
  static TextTheme _textTheme(Brightness b) {
    final isDark = b == Brightness.dark;
    final primaryColor = isDark ? white : black;
    final secondaryColor = isDark ? grey600 : AppColors.textSecondaryLight;

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
        scaffoldBackgroundColor: black,
        colorScheme: const ColorScheme.dark(
          surface: grey900,
          primary: white,
          onPrimary: black,
          secondary: grey600,
          error: error,
        ),
        textTheme: _textTheme(Brightness.dark),
        appBarTheme: const AppBarTheme(
          backgroundColor: black,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: white),
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: white,
          ),
        ),
        cardTheme: CardThemeData(
          color: grey900,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: grey800,
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
            bgPrimary: black,
            bgSurface: grey900,
            bgSurfaceInset: grey800,
            borderSubtle: grey800,
            textPrimary: white,
            textSecondary: grey600,
            textTertiary: grey700,
            accentPrimary: white,
            filePdf: filePdf,
            fileVideo: fileVideo,
            fileZip: fileZip,
            fileFolder: fileFolder,
            fileFolderBg: AppColors.fileFolderBgDark,
            filePalette: filePalette,
            fileVideoBg: grey800,
            fileTextBg: grey800,
            fileGenericBg: grey800,
            filePdfBg: AppColors.filePdfBgDark,
            glowColor: AppColors.glowDark,
            heroGradient: [black, grey900],
            primaryGradient: [white, white],
            selectionColor: grey800,
            selectionColorAlt: grey800,
            success: success,
            error: error,
            warning: warning,
          ),
        ],
      );

  // ── Light Theme Configuration ───────────────────────────────────────────

  /// Generates the light Material 3 theme configuration.
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: white,
        colorScheme: const ColorScheme.light(
          surface: grey100,
          primary: black,
          onPrimary: white,
          secondary: AppColors.textSecondaryLight,
          error: error,
        ),
        textTheme: _textTheme(Brightness.light),
        appBarTheme: const AppBarTheme(
          backgroundColor: white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: black),
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: black,
          ),
        ),
        cardTheme: CardThemeData(
          color: grey100,
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
            bgPrimary: white,
            bgSurface: grey100,
            bgSurfaceInset: grey200,
            borderSubtle: AppColors.grey300,
            textPrimary: black,
            textSecondary: AppColors.textSecondaryLight,
            textTertiary: AppColors.textTertiaryLight,
            accentPrimary: black,
            filePdf: filePdf,
            fileVideo: fileVideo,
            fileZip: fileZip,
            fileFolder: fileFolder,
            fileFolderBg: AppColors.fileFolderBgLight,
            filePalette: filePalette,
            fileVideoBg: AppColors.fileVideoBgLight,
            fileTextBg: AppColors.fileTextBgLight,
            fileGenericBg: AppColors.grey50,
            filePdfBg: AppColors.filePdfBgLight,
            glowColor: AppColors.glowLight,
            heroGradient: [white, grey100],
            primaryGradient: [black, black],
            selectionColor: AppColors.grey300,
            selectionColorAlt: AppColors.grey300,
            success: success,
            error: error,
            warning: warning,
          ),
        ],
      );
}
