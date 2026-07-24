import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TelStorage Design System — Pure Dark & Clean Light UI.
class AppTheme {
  // ── Colors ──────────────────────────────────────────────────────────────
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
  static const grey900 = Color(0xFF151515);
  static const grey800 = Color(0xFF2A2A2A);
  static const grey700 = Color(0xFF6E6E6E);
  static const grey600 = Color(0xFF9A9A9A);
  static const grey200 = Color(0xFFE4E4E4);
  static const grey100 = Color(0xFFF2F2F2);
  
  static const navy900 = Color(0xFF0D0D1D);
  static const navy800 = Color(0xFF1A1A1E);
  static const navy700 = Color(0xFF10142D);
  static const navy600 = Color(0xFF0D172D);

  static const primary = Color(0xFF4A6CF7);
  static const primaryLight = Color(0xFF5B7FFF);
  static const accent = Color(0xFFF2C94C);
  static const success = Color(0xFF27AE60);
  static const error = Color(0xFFFF3B30);
  static const warning = Color(0xFFF2994A);

  // ── File Type Colors ──────────────────────────────────────────────────────
  static const filePdf = Color(0xFFFF3B30);
  static const fileVideo = Color(0xFF5B7FFF);
  static const fileZip = Color(0xFFFFC542);
  static const fileText = Color(0xFF4A6CF7);
  static const filePptx = Color(0xFFFF6A3D);
  static const fileFolder = Color(0xFFF5A623);
  static const filePalette = Colors.purple;

  // ── Legacy Compatibility ──────────────────────────────────────────────────
  static const danger = error;
  static const surface = grey900;
  static const borderSubtle = grey800;

  // ── Text styles ─────────────────────────────────────────────────────────────
  static TextTheme _textTheme(Brightness b) {
    final isDark = b == Brightness.dark;
    final primaryColor = isDark ? white : black;
    final secondaryColor = isDark ? grey600 : const Color(0xFF6B6B6B);
    
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

  // ── Dark theme ──────────────────────────────────────────────────────────────
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
            fileFolderBg: Color(0xFFFDE9C9),
            filePalette: filePalette,
            fileVideoBg: navy700,
            fileTextBg: navy600,
            fileGenericBg: navy800,
            filePdfBg: Color(0xFF2C0E0E),
            glowColor: Color(0x33FFFFFF),
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

  // ── Light theme ────────────────────────────────────────────────────────────
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: white,
        colorScheme: const ColorScheme.light(
          surface: grey100,
          primary: black,
          onPrimary: white,
          secondary: Color(0xFF6B6B6B),
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
          color: Color(0xFFD9D9D9),
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
            borderSubtle: Color(0xFFD9D9D9),
            textPrimary: black,
            textSecondary: Color(0xFF6B6B6B),
            textTertiary: Color(0xFF9E9E9E),
            accentPrimary: black,
            filePdf: filePdf,
            fileVideo: fileVideo,
            fileZip: fileZip,
            fileFolder: fileFolder,
            fileFolderBg: Color(0xFFFFF4E5),
            filePalette: Colors.purple,
            fileVideoBg: Color(0xFFE8EFFF),
            fileTextBg: Color(0xFFE5EBFF),
            fileGenericBg: Color(0xFFF5F5F5),
            filePdfBg: Color(0xFFFFEBEB),
            glowColor: Color(0x1A000000),
            heroGradient: [white, grey100],
            primaryGradient: [black, black],
            selectionColor: Color(0xFFD9D9D9),
            selectionColorAlt: Color(0xFFD9D9D9),
            success: success,
            error: error,
            warning: warning,
          ),
        ],
      );
}

class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color bgPrimary;
  final Color bgSurface;
  final Color bgSurfaceInset;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accentPrimary;
  final Color filePdf;
  final Color fileVideo;
  final Color fileZip;
  final Color fileFolder;
  final Color fileFolderBg;
  final Color filePalette;
  final Color fileVideoBg;
  final Color fileTextBg;
  final Color fileGenericBg;
  final Color filePdfBg;
  final Color glowColor;
  final List<Color> heroGradient;
  final List<Color> primaryGradient;
  final Color selectionColor;
  final Color selectionColorAlt;
  final Color success;
  final Color error;
  final Color warning;

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
