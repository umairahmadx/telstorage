import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Kinetic Glass design system — inspired by Stitch MCP generated system.
/// Primary: #6C63FF  Dark bg: #0F0F1A  Light bg: #F8F9FF
class AppTheme {
  // ── Brand colours ───────────────────────────────────────────────────────────
  static const primary    = Color(0xFF6C63FF);
  static const secondary  = Color(0xFF0088CC);
  static const success    = Color(0xFF10B981);
  static const warning    = Color(0xFFF59E0B);
  static const error      = Color(0xFFEF4444);

  // Dark palette
  static const darkBg         = Color(0xFF0F0F1A);
  static const darkSurface    = Color(0xFF1A1A2E);
  static const darkCard       = Color(0xFF1E1E35);
  static const darkCardBorder = Color(0x336C63FF); // 20 % primary

  // Light palette
  static const lightBg         = Color(0xFFF8F9FF);
  static const lightSurface    = Color(0xFFFFFFFF);
  static const lightCard       = Color(0xFFF0F0FF);
  static const lightCardBorder = Color(0x226C63FF);

  // ── Text styles ─────────────────────────────────────────────────────────────
  static TextTheme _textTheme(Brightness b) {
    final base = b == Brightness.dark ? Colors.white : const Color(0xFF0D0D1A);
    final sub  = b == Brightness.dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    return GoogleFonts.interTextTheme().copyWith(
      displayLarge:   GoogleFonts.inter(fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -1.2, color: base),
      headlineLarge:  GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: base),
      headlineMedium: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, color: base),
      headlineSmall:  GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: base),
      titleLarge:     GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: base),
      titleMedium:    GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: base),
      titleSmall:     GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: base),
      bodyLarge:      GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: base),
      bodyMedium:     GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: sub),
      bodySmall:      GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: sub),
      labelLarge:     GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: base),
      labelMedium:    GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: sub),
    );
  }

  // ── Light theme ─────────────────────────────────────────────────────────────
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: lightSurface,
      primary: primary,
      secondary: secondary,
    ),
    textTheme: _textTheme(Brightness.light),
    appBarTheme: AppBarTheme(
      backgroundColor: lightBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: Color(0xFF0D0D1A)),
      titleTextStyle: GoogleFonts.inter(
        fontSize: 22, fontWeight: FontWeight.w700,
        color: const Color(0xFF0D0D1A),
      ),
    ),
    cardTheme: CardThemeData(
      color: lightCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: lightCardBorder),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightCardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightCardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x229CA3AF),
      thickness: 1,
      space: 0,
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
    ),
  );

  // ── Dark theme ──────────────────────────────────────────────────────────────
  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: darkSurface,
      primary: primary,
      secondary: secondary,
    ),
    textTheme: _textTheme(Brightness.dark),
    appBarTheme: AppBarTheme(
      backgroundColor: darkBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: GoogleFonts.inter(
        fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: darkCardBorder),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkCardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkCardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: Color(0xFF6B7280)),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x229CA3AF),
      thickness: 1,
      space: 0,
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
    ),
  );
}
