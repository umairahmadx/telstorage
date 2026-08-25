/*
 * File: widget_redundancy_rules_test.dart
 * Description: Architecture test enforcing shared widget reuse and absence of duplicate widget definitions.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Widget Redundancy & Reuse Architecture Rules', () {
    final sharedWidgetsDir = Directory('lib/shared/widgets');

    test('lib/shared/widgets directory must contain all master shared components', () {
      expect(sharedWidgetsDir.existsSync(), isTrue);
      final sharedFiles = sharedWidgetsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path.replaceAll('\\', '/'))
          .toList();

      final requiredSharedComponents = [
        'app_file_tile.dart',
        'app_file_grid_tile.dart',
        'app_folder_tile.dart',
        'app_transfer_tile.dart',
        'app_action_card.dart',
        'app_surface_card.dart',
        'app_user_avatar.dart',
        'app_status_badge.dart',
        'app_batch_action_bar.dart',
        'app_empty_state.dart',
        'app_section_label.dart',
        'app_dialogs.dart',
        'app_sort_filter_sheet.dart',
        'file_detail_sheet.dart',
        'shared_widgets.dart',
      ];

      for (final comp in requiredSharedComponents) {
        expect(
          sharedFiles.any((f) => f.endsWith(comp)),
          isTrue,
          reason: 'Expected master shared component "$comp" to exist in lib/shared/widgets/',
        );
      }
    });

    test('Zero duplicate file/folder tiles or local empty states in lib/features/', () {
      final featureFiles = Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path.replaceAll('\\', '/'))
          .toList();

      final forbiddenDuplicatePatterns = [
        'browser_file_tile.dart',
        'browser_file_grid_tile.dart',
        'browser_folder_tile.dart',
        'completed_download_tile.dart',
        'active_download_tile.dart',
        'downloads_empty_state.dart',
      ];

      for (final forbidden in forbiddenDuplicatePatterns) {
        expect(
          featureFiles.any((f) => f.endsWith(forbidden)),
          isFalse,
          reason: 'Duplicate widget file "$forbidden" should not exist in features; use lib/shared/widgets/ instead.',
        );
      }
    });

    test('All shared widgets must follow top-level multiline header convention', () {
      final sharedFiles = sharedWidgetsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          .toList();

      for (final file in sharedFiles) {
        final content = file.readAsStringSync().trimLeft();
        final hasValidHeader = content.startsWith('/*') || content.startsWith('///');
        expect(
          hasValidHeader,
          isTrue,
          reason: 'Shared widget ${file.path} is missing a doc header comment',
        );
      }
    });
  });
}
