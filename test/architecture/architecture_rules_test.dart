/*
 * File: architecture_rules_test.dart
 * Description: Automated architecture and code standard verification tests.
 * Validates file line count limits, top-level header comments, and centralized color rules.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TelStorage Architecture & Code Quality Rules', () {
    final libDir = Directory('lib');

    test('lib directory must exist', () {
      expect(libDir.existsSync(), isTrue);
    });

    test('Rule 1: No Dart file in lib/ exceeds 500 lines of code', () {
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          .toList();

      final oversizedFiles = <String, int>{};

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync().length;
        if (lines > 500) {
          oversizedFiles[file.path] = lines;
        }
      }

      if (oversizedFiles.isNotEmpty) {
        final summary = oversizedFiles.entries
            .map((e) => '${e.key}: ${e.value} lines')
            .join('\n');
        fail('The following files exceed the 500 line limit:\n$summary');
      }

      expect(oversizedFiles, isEmpty);
    });

    test(
        'Rule 2: Every .dart file in lib/ must have a top-level multiline header comment',
        () {
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          .toList();

      final missingHeaderFiles = <String>[];

      for (final file in dartFiles) {
        final content = file.readAsStringSync().trimLeft();
        final hasHeader = content.startsWith('/*') || content.startsWith('///');
        if (!hasHeader) {
          missingHeaderFiles.add(file.path);
        }
      }

      if (missingHeaderFiles.isNotEmpty) {
        fail(
            'The following files are missing a top-level doc header comment:\n${missingHeaderFiles.join('\n')}');
      }

      expect(missingHeaderFiles, isEmpty);
    });

    test(
        'Rule 3: No hardcoded raw Color(0x...) in UI widget files (centralized colors rule)',
        () {
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') &&
              !f.path.contains('app_colors.dart') &&
              !f.path.contains('app_theme.dart') &&
              !f.path.endsWith('.g.dart'))
          .toList();

      final rawColorRegex = RegExp(r'Color\(0x[0-9a-fA-F]+\)');
      final violations = <String>[];

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trim().startsWith('//') || line.trim().startsWith('*')) {
            continue;
          }
          if (rawColorRegex.hasMatch(line)) {
            violations.add('${file.path}:${i + 1} -> ${line.trim()}');
          }
        }
      }

      if (violations.isNotEmpty) {
        fail(
            'Hardcoded color violations found (use AppColors instead):\n${violations.join('\n')}');
      }

      expect(violations, isEmpty);
    });

    test(
        'Rule 4: Every feature screen has its own dedicated directory under presentation/screens/',
        () {
      final featuresDir = Directory('lib/features');
      expect(featuresDir.existsSync(), isTrue);

      final featureDirs =
          featuresDir.listSync().whereType<Directory>().toList();
      for (final feature in featureDirs) {
        final screensDir = Directory('${feature.path}/presentation/screens');
        if (screensDir.existsSync()) {
          final screenDirs =
              screensDir.listSync().whereType<Directory>().toList();
          expect(screenDirs, isNotEmpty,
              reason:
                  'Feature ${feature.path} should contain subfolders for each screen');
        }
      }
    });
  });
}
