import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppTheme light and dark themes contain non-null AppColorsExtension', () {
    final lightTheme = AppTheme.light();
    final darkTheme = AppTheme.dark();

    final lightColors = lightTheme.extension<AppColorsExtension>();
    final darkColors = darkTheme.extension<AppColorsExtension>();

    expect(lightColors, isNotNull, reason: 'Light theme must have AppColorsExtension');
    expect(darkColors, isNotNull, reason: 'Dark theme must have AppColorsExtension');

    final colorLists = [lightColors!, darkColors!];
    for (final ext in colorLists) {
      expect(ext.bgPrimary, isNotNull);
      expect(ext.bgSurface, isNotNull);
      expect(ext.bgSurfaceInset, isNotNull);
      expect(ext.borderSubtle, isNotNull);
      expect(ext.textPrimary, isNotNull);
      expect(ext.textSecondary, isNotNull);
      expect(ext.textTertiary, isNotNull);
      expect(ext.accentPrimary, isNotNull);
      expect(ext.filePdf, isNotNull);
      expect(ext.fileVideo, isNotNull);
      expect(ext.fileZip, isNotNull);
      expect(ext.fileFolder, isNotNull);
      expect(ext.fileFolderBg, isNotNull);
      expect(ext.filePalette, isNotNull);
      expect(ext.fileVideoBg, isNotNull);
      expect(ext.fileTextBg, isNotNull);
      expect(ext.fileGenericBg, isNotNull);
      expect(ext.filePdfBg, isNotNull);
      expect(ext.glowColor, isNotNull);
      expect(ext.selectionColor, isNotNull);
      expect(ext.selectionColorAlt, isNotNull);
      expect(ext.success, isNotNull);
      expect(ext.error, isNotNull);
      expect(ext.warning, isNotNull);
    }
  });
}
