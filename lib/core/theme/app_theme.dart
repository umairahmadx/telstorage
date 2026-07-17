import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TelStorage Design System — Pure Dark, High-Contrast UI.
class AppTheme {
  // ── Neutrals ──────────────────────────────────────────────────────────────
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
  static const surface = Color(0xFF151515);
  static const surfaceInset = Color(0xFF0D0D1D);
  static const borderSubtle = Color(0xFF2A2A2A);
  
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9A9A9A);
  static const textTertiary = Color(0xFF6E6E6E);

  // ── Legacy / Compatibility Aliases ────────────────────────────────────────
  static const primary = white;
  static const primaryLight = Color(0xFFE0E0E0);
  static const secondary = textSecondary;
  static const success = white;
  static const warning = Color(0xFFF2C94C);
  static const error = Color(0xFFFF3B30);
  static const darkBg = black;
  static const lightBg = white;
  static const darkSurface = surface;
  static const lightSurface = Color(0xFFF2F2F2);
  static const darkCard = surface;
  static const lightCard = Color(0xFFF2F2F2);
  static const darkCardBorder = borderSubtle;
  static const lightCardBorder = Color(0xFFD9D9D9);

  // ── File Type Colors ──────────────────────────────────────────────────────
  static const filePdf = Color(0xFFFF3B30);
  static const fileVideo = Color(0xFF5B7FFF);
  static const fileZip = Color(0xFFFFC542);
  static const fileText = Color(0xFF4A6CF7);
  static const filePptx = Color(0xFFFF6A3D);
  static const fileFolder = Color(0xFFF2C94C);
  static const danger = Color(0xFFFF3B30);

  // Category Gradients Compatibility
  static const catImages = [fileText, fileVideo];
  static const catVideos = [fileVideo, Color(0xFF8B5CF6)];
  static const catDocs = [filePdf, filePptx];
  static const catOthers = [fileZip, Color(0xFF0088CC)];

  // ── Text styles ─────────────────────────────────────────────────────────────
  static TextTheme _textTheme(Brightness b) {
    final isDark = b == Brightness.dark;
    final primaryColor = isDark ? textPrimary : black;
    final secondaryColor = isDark ? textSecondary : const Color(0xFF6B6B6B);
    
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
          surface: surface,
          primary: white,
          onPrimary: black,
          secondary: textSecondary,
          error: danger,
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
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: borderSubtle,
          thickness: 1,
          space: 0,
        ),
        extensions: const [
          AppColorsExtension(
            bgPrimary: black,
            bgSurface: surface,
            bgSurfaceInset: surfaceInset,
            borderSubtle: borderSubtle,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textTertiary: textTertiary,
            accentPrimary: white,
            filePdf: filePdf,
            fileVideo: fileVideo,
            fileZip: fileZip,
            fileFolder: fileFolder,
            glowColor: Color(0x33FFFFFF), // white with 20% alpha
            heroGradient: [black, surface],
            primaryGradient: [white, white],
            selectionColor: borderSubtle,
            selectionColorAlt: borderSubtle,
          ),
        ],
      );

  // ── Light theme (Inverted) ──────────────────────────────────────────────────
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: white,
        colorScheme: const ColorScheme.light(
          surface: Color(0xFFF2F2F2),
          primary: black,
          onPrimary: white,
          secondary: Color(0xFF6B6B6B),
          error: danger,
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
          color: const Color(0xFFF2F2F2),
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
        extensions: const [
          AppColorsExtension(
            bgPrimary: white,
            bgSurface: Color(0xFFF2F2F2),
            bgSurfaceInset: Color(0xFFE4E4E4),
            borderSubtle: Color(0xFFD9D9D9),
            textPrimary: black,
            textSecondary: Color(0xFF6B6B6B),
            textTertiary: Color(0xFF9E9E9E),
            accentPrimary: black,
            filePdf: filePdf,
            fileVideo: fileVideo,
            fileZip: fileZip,
            fileFolder: fileFolder,
            glowColor: Color(0x1A000000), // black with 10% alpha
            heroGradient: [white, Color(0xFFF2F2F2)],
            primaryGradient: [black, black],
            selectionColor: Color(0xFFD9D9D9),
            selectionColorAlt: Color(0xFFD9D9D9),
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
  final Color glowColor;
  final List<Color> heroGradient;
  final List<Color> primaryGradient;
  final Color selectionColor;
  final Color selectionColorAlt;

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
    required this.glowColor,
    required this.heroGradient,
    required this.primaryGradient,
    required this.selectionColor,
    required this.selectionColorAlt,
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
    Color? glowColor,
    List<Color>? heroGradient,
    List<Color>? primaryGradient,
    Color? selectionColor,
    Color? selectionColorAlt,
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
      glowColor: glowColor ?? this.glowColor,
      heroGradient: heroGradient ?? this.heroGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      selectionColor: selectionColor ?? this.selectionColor,
      selectionColorAlt: selectionColorAlt ?? this.selectionColorAlt,
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
      glowColor: Color.lerp(glowColor, other.glowColor, t)!,
      heroGradient: other.heroGradient,
      primaryGradient: other.primaryGradient,
      selectionColor: Color.lerp(selectionColor, other.selectionColor, t)!,
      selectionColorAlt: Color.lerp(selectionColorAlt, other.selectionColorAlt, t)!,
    );
  }
}
