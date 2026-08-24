/// File: widget_redundancy_rules_test.dart
/// Description: Architecture test enforcing shared widget reuse and absence of duplicate widget definitions.
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Widget Redundancy & Reuse Architecture Rules', () {
    final sharedWidgetsDir = Directory('lib/shared/widgets');

    test('lib/shared/widgets directory must exist and contain core shared components', () {
      expect(sharedWidgetsDir.existsSync(), isTrue);
      final sharedFiles = sharedWidgetsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path)
          .toList();

      expect(sharedFiles, isNotEmpty);
      expect(
        sharedFiles.any((f) => f.contains('app_surface_card.dart')),
        isTrue,
        reason: 'AppSurfaceCard must exist in lib/shared/widgets/',
      );
      expect(
        sharedFiles.any((f) => f.contains('app_search_field.dart')),
        isTrue,
        reason: 'AppSearchField must exist in lib/shared/widgets/',
      );
      expect(
        sharedFiles.any((f) => f.contains('app_segmented_control.dart')),
        isTrue,
        reason: 'AppSegmentedControl must exist in lib/shared/widgets/',
      );
    });

    test('All shared widgets must follow top-level doc header convention', () {
      final sharedFiles = sharedWidgetsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          .toList();

      for (final file in sharedFiles) {
        final content = file.readAsStringSync().trimLeft();
        final hasValidHeader = content.startsWith('///') || content.startsWith('/**');
        expect(
          hasValidHeader,
          isTrue,
          reason: 'Shared widget ${file.path} is missing a doc header comment',
        );
      }
    });
  });
}
