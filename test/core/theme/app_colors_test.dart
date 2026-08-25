/*
 * File: app_colors_test.dart
 * Description: Unit tests for AppColors palette and AppTheme extension token mapping.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AppColors Centralization Tests', () {
    test('Verify core color tokens are correctly defined in AppColors', () {
      expect(AppColors.primary, const Color(0xFF4A6CF7));
      expect(AppColors.black, const Color(0xFF000000));
      expect(AppColors.white, const Color(0xFFFFFFFF));
      expect(AppColors.filePdf, const Color(0xFFFF3B30));
      expect(AppColors.fileVideo, const Color(0xFF5B7FFF));
      expect(AppColors.fileZip, const Color(0xFFFFC542));
    });

    testWidgets('Verify AppTheme Dark theme extension uses centralized colors', (tester) async {
      final darkTheme = AppTheme.dark();
      final colors = darkTheme.extension<AppColorsExtension>();
      expect(colors, isNotNull);
      expect(colors!.bgPrimary, AppColors.black);
      expect(colors.bgSurface, AppColors.grey900);
      expect(colors.accentPrimary, AppColors.white);
      expect(colors.filePdf, AppColors.filePdf);
    });

    testWidgets('Verify AppTheme Light theme extension uses centralized colors', (tester) async {
      final lightTheme = AppTheme.light();
      final colors = lightTheme.extension<AppColorsExtension>();
      expect(colors, isNotNull);
      expect(colors!.bgPrimary, AppColors.white);
      expect(colors.bgSurface, AppColors.grey100);
      expect(colors.accentPrimary, AppColors.black);
      expect(colors.filePdf, AppColors.filePdf);
    });
  });
}
