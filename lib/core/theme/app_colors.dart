/*
 * File: app_colors.dart
 * Description: Centralized color palette and design tokens for the TelStorage application.
 * Defines base hues, semantic tokens, and file category indicators.
 */

import 'package:flutter/material.dart';

/// Centralized color system for TelStorage.
/// All UI components must consume colors from this class or through AppColorsExtension.
abstract final class AppColors {
  // ── Base Grayscale & Monochromes ──────────────────────────────────────────

  /// Pure solid black.
  static const Color black = Color(0xFF000000);

  /// Pure solid white.
  static const Color white = Color(0xFFFFFFFF);

  /// Deep surface dark tone.
  static const Color grey900 = Color(0xFF151515);

  /// Elevated card / border dark tone.
  static const Color grey800 = Color(0xFF2A2A2A);

  /// Muted tertiary text tone in dark mode.
  static const Color grey700 = Color(0xFF6E6E6E);

  /// Secondary text tone in dark mode.
  static const Color grey600 = Color(0xFF9A9A9A);

  /// Border subtle tone in light mode.
  static const Color grey300 = Color(0xFFD9D9D9);

  /// Secondary surface background in light mode.
  static const Color grey200 = Color(0xFFE4E4E4);

  /// Primary card surface in light mode.
  static const Color grey100 = Color(0xFFF2F2F2);

  /// Off-white light generic container background.
  static const Color grey50 = Color(0xFFF5F5F5);

  /// Muted text tone for light mode.
  static const Color textSecondaryLight = Color(0xFF6B6B6B);

  /// Tertiary text tone for light mode.
  static const Color textTertiaryLight = Color(0xFF9E9E9E);

  // ── Navy Inset Tones (Dark Theme Insets) ──────────────────────────────────

  /// Dark navy deep container background.
  static const Color navy900 = Color(0xFF0D0D1D);

  /// Medium navy card surface.
  static const Color navy800 = Color(0xFF1A1A1E);

  /// Soft navy container background.
  static const Color navy700 = Color(0xFF10142D);

  /// Subtle navy text container background.
  static const Color navy600 = Color(0xFF0D172D);

  // ── Brand & Semantic Accents ─────────────────────────────────────────────

  /// Primary interactive brand color.
  static const Color primary = Color(0xFF4A6CF7);

  /// Lighter variant of primary brand color.
  static const Color primaryLight = Color(0xFF5B7FFF);

  /// Golden accent highlight color.
  static const Color accent = Color(0xFFF2C94C);

  /// Success state indicator color.
  static const Color success = Color(0xFF27AE60);

  /// Error state indicator color.
  static const Color error = Color(0xFFFF3B30);

  /// Warning / pending state indicator color.
  static const Color warning = Color(0xFFF2994A);

  // ── File Category Indicators ─────────────────────────────────────────────

  /// Badge indicator for PDF documents.
  static const Color filePdf = Color(0xFFFF3B30);

  /// Badge indicator for Video media files.
  static const Color fileVideo = Color(0xFF5B7FFF);

  /// Badge indicator for Compressed Archives.
  static const Color fileZip = Color(0xFFFFC542);

  /// Badge indicator for Code & Plain Text files.
  static const Color fileText = Color(0xFF4A6CF7);

  /// Badge indicator for Presentations & Slides.
  static const Color filePptx = Color(0xFFFF6A3D);

  /// Badge indicator for Folders and Directories.
  static const Color fileFolder = Color(0xFFF5A623);

  /// Badge indicator for Images & Graphic files.
  static const Color filePalette = Color(0xFF9C27B0);

  // ── File Badge Background Tints ──────────────────────────────────────────

  /// Folder icon container background tint (Dark Mode).
  static const Color fileFolderBgDark = Color(0xFF2B2012);

  /// Folder icon container background tint (Light Mode).
  static const Color fileFolderBgLight = Color(0xFFFFF4E5);

  /// PDF icon container background tint (Dark Mode).
  static const Color filePdfBgDark = Color(0xFF2C0E0E);

  /// PDF icon container background tint (Light Mode).
  static const Color filePdfBgLight = Color(0xFFFFEBEB);

  /// Video icon container background tint (Light Mode).
  static const Color fileVideoBgLight = Color(0xFFE8EFFF);

  /// Text icon container background tint (Light Mode).
  static const Color fileTextBgLight = Color(0xFFE5EBFF);

  // ── Glow & Shadow Overlays ───────────────────────────────────────────────

  /// Subtle glow overlay for dark theme surfaces.
  static const Color glowDark = Color(0x33FFFFFF);

  /// Subtle shadow overlay for light theme surfaces.
  static const Color glowLight = Color(0x1A000000);

  // ── Code Snippet Canvas Theme ─────────────────────────────────────────────

  /// Dark background for code preview cards.
  static const Color codeCanvasBg = Color(0xFF14171C);

  /// Header background for code preview cards.
  static const Color codeCanvasHeader = Color(0xFF1E222A);

  /// Red traffic dot for code preview cards.
  static const Color codeCanvasDotRed = Color(0xFFFF5F56);

  /// Yellow traffic dot for code preview cards.
  static const Color codeCanvasDotYellow = Color(0xFFFFBD2E);

  /// Green traffic dot for code preview cards.
  static const Color codeCanvasDotGreen = Color(0xFF27C93F);

  /// Header text color for code preview cards.
  static const Color codeCanvasTextSecondary = Color(0xFF9AA0A6);

  /// Line number color for code preview cards.
  static const Color codeCanvasLineNumber = Color(0xFF5F6368);

  /// Code text color for code preview cards.
  static const Color codeCanvasTextPrimary = Color(0xFFE8EAED);
}
