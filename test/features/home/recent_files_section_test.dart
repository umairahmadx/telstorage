/*
 * File: recent_files_section_test.dart
 * Description: Widget tests for RecentFilesSection asserting ValueKey element identity preservation during additions and deletions.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/home/presentation/screens/home/widgets/recent_files_section.dart';
import 'package:telstorage/shared/widgets/tiles/app_file_tile.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fileA = FileRecord(
    fileId: 'file_a',
    name: 'document_a.pdf',
    metadataMessageId: 101,
    sizeMb: 1.0,
    mimeType: 'application/pdf',
    uploadedAt: DateTime(2026, 1, 1),
    chunkCount: 1,
    sha256Hash: 'hash_a',
  );

  final fileB = FileRecord(
    fileId: 'file_b',
    name: 'document_b.pdf',
    metadataMessageId: 102,
    sizeMb: 2.0,
    mimeType: 'application/pdf',
    uploadedAt: DateTime(2026, 1, 2),
    chunkCount: 1,
    sha256Hash: 'hash_b',
  );

  final fileNew = FileRecord(
    fileId: 'file_new',
    name: 'document_new.pdf',
    metadataMessageId: 103,
    sizeMb: 3.0,
    mimeType: 'application/pdf',
    uploadedAt: DateTime(2026, 1, 3),
    chunkCount: 1,
    sha256Hash: 'hash_new',
  );

  group('RecentFilesSection Key & Identity Preservation Tests', () {
    testWidgets(
        'TC-01: AppFileTile widgets have explicit ValueKey(file.fileId)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecentFilesSection(
            files: [fileB, fileA],
            onMore: (_) {},
          ),
        ),
      );

      final tileA = find.byKey(const ValueKey('file_a'));
      final tileB = find.byKey(const ValueKey('file_b'));

      expect(tileA, findsOneWidget);
      expect(tileB, findsOneWidget);

      final tiles = tester.widgetList<AppFileTile>(find.byType(AppFileTile)).toList();
      expect(tiles[0].key, equals(const ValueKey('file_b')));
      expect(tiles[1].key, equals(const ValueKey('file_a')));
    });

    testWidgets(
        'TC-02: Prepending a new file shifts existing keyed tiles without identity disruption',
        (tester) async {
      // 1. Render initial list: [fileB, fileA]
      await tester.pumpWidget(
        _wrap(
          RecentFilesSection(
            files: [fileB, fileA],
            onMore: (_) {},
          ),
        ),
      );

      expect(find.byKey(const ValueKey('file_b')), findsOneWidget);
      expect(find.byKey(const ValueKey('file_a')), findsOneWidget);

      // 2. Prepend fileNew: [fileNew, fileB, fileA]
      await tester.pumpWidget(
        _wrap(
          RecentFilesSection(
            files: [fileNew, fileB, fileA],
            onMore: (_) {},
          ),
        ),
      );

      final tiles = tester.widgetList<AppFileTile>(find.byType(AppFileTile)).toList();
      expect(tiles.length, equals(3));
      expect(tiles[0].key, equals(const ValueKey('file_new')));
      expect(tiles[1].key, equals(const ValueKey('file_b')));
      expect(tiles[2].key, equals(const ValueKey('file_a')));
    });

    testWidgets(
        'TC-03: Deleting an item removes the specific keyed tile in-place',
        (tester) async {
      // 1. Render [fileNew, fileB, fileA]
      await tester.pumpWidget(
        _wrap(
          RecentFilesSection(
            files: [fileNew, fileB, fileA],
            onMore: (_) {},
          ),
        ),
      );

      // 2. Delete fileB: [fileNew, fileA]
      await tester.pumpWidget(
        _wrap(
          RecentFilesSection(
            files: [fileNew, fileA],
            onMore: (_) {},
          ),
        ),
      );

      final tiles = tester.widgetList<AppFileTile>(find.byType(AppFileTile)).toList();
      expect(tiles.length, equals(2));
      expect(tiles[0].key, equals(const ValueKey('file_new')));
      expect(tiles[1].key, equals(const ValueKey('file_a')));
      expect(find.byKey(const ValueKey('file_b')), findsNothing);
    });
  });
}
