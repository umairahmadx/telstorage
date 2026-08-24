/// File: app_theme.dart
/// Description: Main theme configuration for TelStorage.
/// Configures Material 3 Light and Dark ThemeData, Typography, and AppColorsExtension.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

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
        extensions: const [
          AppColorsExtension(
            bgPrimary: black,
            bgSurface: grey900,
            bgSurfaceInset: navy900,
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
            fileVideoBg: navy700,
            fileTextBg: navy600,
            fileGenericBg: navy800,
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

/// ThemeExtension that supplies design tokens dynamically per theme mode.
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  /// Primary background color.
  final Color bgPrimary;

  /// Surface card background color.
  final Color bgSurface;

  /// Inset background container color.
  final Color bgSurfaceInset;

  /// Subtle border divider color.
  final Color borderSubtle;

  /// Primary high-contrast text color.
  final Color textPrimary;

  /// Secondary subdued text color.
  final Color textSecondary;

  /// Tertiary placeholder text color.
  final Color textTertiary;

  /// Primary accent color.
  final Color accentPrimary;

  /// PDF badge color.
  final Color filePdf;

  /// Video badge color.
  final Color fileVideo;

  /// Zip archive badge color.
  final Color fileZip;

  /// Folder badge color.
  final Color fileFolder;

  /// Folder icon container background tint.
  final Color fileFolderBg;

  /// Palette image badge color.
  final Color filePalette;

  /// Video icon container background tint.
  final Color fileVideoBg;

  /// Text icon container background tint.
  final Color fileTextBg;

  /// Generic file container background tint.
  final Color fileGenericBg;

  /// PDF icon container background tint.
  final Color filePdfBg;

  /// Glow / Shadow color overlay.
  final Color glowColor;

  /// Hero background gradient colors.
  final List<Color> heroGradient;

  /// Primary button gradient colors.
  final List<Color> primaryGradient;

  /// Active selection background color.
  final Color selectionColor;

  /// Alternate selection background color.
  final Color selectionColorAlt;

  /// Success state color.
  final Color success;

  /// Error state color.
  final Color error;

  /// Warning state color.
  final Color warning;

  /// Constructs an immutable AppColorsExtension token instance.
  const AppColorsExtension({
    required this.bgPrimary,
    required this.bgSurface,
    required this.bgSurfaceInset,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accentPrimary,
    required this.filePdf,
    required this.fileVideo,
    required this.fileZip,
    required this.fileFolder,
    required this.fileFolderBg,
    required this.filePalette,
    required this.fileVideoBg,
    required this.fileTextBg,
    required this.fileGenericBg,
    required this.filePdfBg,
    required this.glowColor,
    required this.heroGradient,
    required this.primaryGradient,
    required this.selectionColor,
    required this.selectionColorAlt,
    required this.success,
    required this.error,
    required this.warning,
  });

  @override
  ThemeExtension<AppColorsExtension> copyWith({
    Color? bgPrimary,
    Color? bgSurface,
    Color? bgSurfaceInset,
    Color? borderSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accentPrimary,
    Color? filePdf,
    Color? fileVideo,
    Color? fileZip,
    Color? fileFolder,
    Color? fileFolderBg,
    Color? filePalette,
    Color? fileVideoBg,
    Color? fileTextBg,
    Color? fileGenericBg,
    Color? filePdfBg,
    Color? glowColor,
    List<Color>? heroGradient,
    List<Color>? primaryGradient,
    Color? selectionColor,
    Color? selectionColorAlt,
    Color? success,
    Color? error,
    Color? warning,
  }) {
    return AppColorsExtension(
      bgPrimary: bgPrimary ?? this.bgPrimary,
      bgSurface: bgSurface ?? this.bgSurface,
      bgSurfaceInset: bgSurfaceInset ?? this.bgSurfaceInset,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      filePdf: filePdf ?? this.filePdf,
      fileVideo: fileVideo ?? this.fileVideo,
      fileZip: fileZip ?? this.fileZip,
      fileFolder: fileFolder ?? this.fileFolder,
      fileFolderBg: fileFolderBg ?? this.fileFolderBg,
      filePalette: filePalette ?? this.filePalette,
      fileVideoBg: fileVideoBg ?? this.fileVideoBg,
      fileTextBg: fileTextBg ?? this.fileTextBg,
      fileGenericBg: fileGenericBg ?? this.fileGenericBg,
      filePdfBg: filePdfBg ?? this.filePdfBg,
      glowColor: glowColor ?? this.glowColor,
      heroGradient: heroGradient ?? this.heroGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      selectionColor: selectionColor ?? this.selectionColor,
      selectionColorAlt: selectionColorAlt ?? this.selectionColorAlt,
      success: success ?? this.success,
      error: error ?? this.error,
      warning: warning ?? this.warning,
    );
  }

  @override
  ThemeExtension<AppColorsExtension> lerp(
      ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    return AppColorsExtension(
      bgPrimary: Color.lerp(bgPrimary, other.bgPrimary, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgSurfaceInset: Color.lerp(bgSurfaceInset, other.bgSurfaceInset, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      filePdf: Color.lerp(filePdf, other.filePdf, t)!,
      fileVideo: Color.lerp(fileVideo, other.fileVideo, t)!,
      fileZip: Color.lerp(fileZip, other.fileZip, t)!,
      fileFolder: Color.lerp(fileFolder, other.fileFolder, t)!,
      fileFolderBg: Color.lerp(fileFolderBg, other.fileFolderBg, t)!,
      filePalette: Color.lerp(filePalette, other.filePalette, t)!,
      fileVideoBg: Color.lerp(fileVideoBg, other.fileVideoBg, t)!,
      fileTextBg: Color.lerp(fileTextBg, other.fileTextBg, t)!,
      fileGenericBg: Color.lerp(fileGenericBg, other.fileGenericBg, t)!,
      filePdfBg: Color.lerp(filePdfBg, other.filePdfBg, t)!,
      glowColor: Color.lerp(glowColor, other.glowColor, t)!,
      heroGradient: other.heroGradient,
      primaryGradient: other.primaryGradient,
      selectionColor: Color.lerp(selectionColor, other.selectionColor, t)!,
      selectionColorAlt: Color.lerp(selectionColorAlt, other.selectionColorAlt, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}
