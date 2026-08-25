/*
 * File: app_colors_extension.dart
 * Description: ThemeExtension that supplies design tokens dynamically per theme mode.
 */

import 'package:flutter/material.dart';

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

  /// PDF type indicator.
  final Color filePdf;

  /// Video type indicator.
  final Color fileVideo;

  /// Zip archive indicator.
  final Color fileZip;

  /// Folder type indicator.
  final Color fileFolder;

  /// Folder background tint.
  final Color fileFolderBg;

  /// Image palette indicator.
  final Color filePalette;

  /// Video background container tint.
  final Color fileVideoBg;

  /// Text/code file container tint.
  final Color fileTextBg;

  /// Generic file container tint.
  final Color fileGenericBg;

  /// PDF background container tint.
  final Color filePdfBg;

  /// Ambient glow color for active indicators.
  final Color glowColor;

  /// Hero gradient colors.
  final List<Color> heroGradient;

  /// Primary brand gradient colors.
  final List<Color> primaryGradient;

  /// Selected item background highlight.
  final Color selectionColor;

  /// Alternate selection highlight color.
  final Color selectionColorAlt;

  /// Operation success color.
  final Color success;

  /// Operation error color.
  final Color error;

  /// Operation warning color.
  final Color warning;

  /// Constructs AppColorsExtension.
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
