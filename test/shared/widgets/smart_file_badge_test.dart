/*
 * File: smart_file_badge_test.dart
 * Description: Unit tests validating SmartBadgeInfo extension resolution, special filename detection, and zero-extension fallbacks.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/thumbnail_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('SmartBadgeInfo Resolution & Zero-Extension Tests', () {
    testWidgets('TC-10: Standard document extension resolves to uppercase tag',
        (tester) async {
      final darkColors = AppTheme.dark().extension<AppColorsExtension>()!;
      final badge = SmartBadgeInfo.resolve('quarterly_report.docx',
          'application/vnd.openxmlformats', darkColors);
      expect(badge.label, 'DOCX');
    });

    testWidgets('TC-11: Audio extensions resolve to audio tag', (tester) async {
      final darkColors = AppTheme.dark().extension<AppColorsExtension>()!;
      final flacBadge =
          SmartBadgeInfo.resolve('symphony.flac', 'audio/flac', darkColors);
      expect(flacBadge.label, 'FLAC');

      final mp3Badge =
          SmartBadgeInfo.resolve('podcast.mp3', 'audio/mpeg', darkColors);
      expect(mp3Badge.label, 'MP3');
    });

    testWidgets('TC-12: Multi-dot archive resolves to last extension',
        (tester) async {
      final darkColors = AppTheme.dark().extension<AppColorsExtension>()!;
      final tarGzBadge = SmartBadgeInfo.resolve(
          'backup_database.tar.gz', 'application/gzip', darkColors);
      expect(tarGzBadge.label, 'GZ');
    });

    testWidgets('TC-13: Dockerfile without extension resolves to DOCKER badge',
        (tester) async {
      final darkColors = AppTheme.dark().extension<AppColorsExtension>()!;
      final badge = SmartBadgeInfo.resolve(
          'Dockerfile', 'application/octet-stream', darkColors);
      expect(badge.label, 'DOCKER');
    });

    testWidgets('TC-14: Makefile without extension resolves to MAKE badge',
        (tester) async {
      final darkColors = AppTheme.dark().extension<AppColorsExtension>()!;
      final badge = SmartBadgeInfo.resolve(
          'Makefile', 'application/octet-stream', darkColors);
      expect(badge.label, 'MAKE');
    });

    testWidgets(
        'TC-15: LICENSE & README without extension resolve to DOC badge',
        (tester) async {
      final darkColors = AppTheme.dark().extension<AppColorsExtension>()!;
      final licenseBadge =
          SmartBadgeInfo.resolve('LICENSE', 'text/plain', darkColors);
      expect(licenseBadge.label, 'DOC');

      final readmeBadge =
          SmartBadgeInfo.resolve('README', 'text/plain', darkColors);
      expect(readmeBadge.label, 'DOC');
    });

    testWidgets(
        'TC-16: Extensionless text file with text/plain mime resolves to TXT badge',
        (tester) async {
      final darkColors = AppTheme.dark().extension<AppColorsExtension>()!;
      final badge =
          SmartBadgeInfo.resolve('notes_unnamed', 'text/plain', darkColors);
      expect(badge.label, 'TXT');
    });

    testWidgets(
        'TC-17: Extensionless unknown binary resolves to clean FILE fallback',
        (tester) async {
      final darkColors = AppTheme.dark().extension<AppColorsExtension>()!;
      final badge = SmartBadgeInfo.resolve(
          'unknown_binary_payload', 'application/octet-stream', darkColors);
      expect(badge.label, 'FILE');
      expect(badge.iconColor, darkColors.textSecondary);
    });

    testWidgets(
        'TC-18: Image extensions HEIC, PNG, JPG, and WEBP resolve to respective tags',
        (tester) async {
      final darkColors = AppTheme.dark().extension<AppColorsExtension>()!;

      final heicBadge =
          SmartBadgeInfo.resolve('photo.heic', 'image/heic', darkColors);
      expect(heicBadge.label, 'HEIC');
      expect(heicBadge.iconColor, darkColors.accentPrimary);

      final pngBadge =
          SmartBadgeInfo.resolve('screenshot.png', 'image/png', darkColors);
      expect(pngBadge.label, 'PNG');
      expect(pngBadge.iconColor, darkColors.accentPrimary);

      final jpgBadge =
          SmartBadgeInfo.resolve('vacation.jpg', 'image/jpeg', darkColors);
      expect(jpgBadge.label, 'JPG');
      expect(jpgBadge.iconColor, darkColors.accentPrimary);

      final webpBadge =
          SmartBadgeInfo.resolve('sticker.webp', 'image/webp', darkColors);
      expect(webpBadge.label, 'WEBP');
      expect(webpBadge.iconColor, darkColors.accentPrimary);
    });
  });
}
