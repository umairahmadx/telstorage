/*
 * File: reading_theme_sheet.dart
 * Description: Bottom modal sheet allowing users to toggle between Original, Dark OLED, and Warm Sepia reading modes.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/core/theme/app_colors_extension.dart';
import '../viewmodel/document_viewer_viewmodel.dart';

/// Modal bottom sheet for PDF reading theme selection.
class ReadingThemeSheet extends StatelessWidget {
  /// Current reading theme.
  final DocumentReadingTheme currentTheme;

  /// Callback when user selects a theme.
  final ValueChanged<DocumentReadingTheme> onThemeChanged;

  /// Constructs ReadingThemeSheet.
  const ReadingThemeSheet({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reading Theme',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colors?.textPrimary ?? AppColors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildThemeOption(
                  context,
                  title: 'Original',
                  theme: DocumentReadingTheme.original,
                  bgColor: AppColors.white,
                  textColor: AppColors.black,
                ),
                _buildThemeOption(
                  context,
                  title: 'Dark',
                  theme: DocumentReadingTheme.dark,
                  bgColor: AppColors.black,
                  textColor: AppColors.white,
                ),
                _buildThemeOption(
                  context,
                  title: 'Sepia',
                  theme: DocumentReadingTheme.sepia,
                  bgColor: AppColors.sepiaPaper,
                  textColor: AppColors.sepiaText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required String title,
    required DocumentReadingTheme theme,
    required Color bgColor,
    required Color textColor,
  }) {
    final isSelected = currentTheme == theme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        onThemeChanged(theme);
        Navigator.of(context).pop();
      },
      child: Container(
        width: 90,
        height: 80,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.grey700,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
