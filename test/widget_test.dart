/*
 * File: widget_test.dart
 * Description: Widget tests for centralized UI components (AppFolderTile, AppFileTile).
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/tiles/app_file_tile.dart';
import 'package:telstorage/shared/widgets/tiles/app_folder_grid_tile.dart';
import 'package:telstorage/shared/widgets/tiles/app_folder_tile.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('AppFolderTile renders its name and item count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: AppFolderTile(
            folder: FolderRecord(
              id: 'folder-1',
              name: 'Documents',
              createdAt: DateTime(2026),
            ),
            itemCount: 3,
            onTap: () {},
            onLongPress: () {},
            onActionTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('3 items'), findsOneWidget);
  });

  testWidgets('AppFolderTile renders singular item label for count of 1',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: AppFolderTile(
            folder: FolderRecord(
              id: 'folder-2',
              name: 'Photos',
              createdAt: DateTime(2026),
            ),
            itemCount: 1,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
  });

  testWidgets('AppFolderGridTile renders name and item count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: AppFolderGridTile(
            folder: FolderRecord(
              id: 'folder-grid-1',
              name: 'Music',
              createdAt: DateTime(2026),
            ),
            itemCount: 5,
            onTap: () {},
            onLongPress: () {},
            onActionTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Music'), findsOneWidget);
    expect(find.text('5 items'), findsOneWidget);
  });

  testWidgets('AppFileTile renders file name and formatted size',
      (tester) async {
    final file = FileRecord(
      fileId: 'file-101',
      metadataMessageId: 1,
      metadataFileId: 'meta-1',
      name: 'quarterly_report.pdf',
      sizeMb: 2.5,
      mimeType: 'application/pdf',
      uploadedAt: DateTime(2026, 3, 15),
      chunkCount: 1,
      sha256Hash: 'dummy-hash',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: AppFileTile(
            file: file,
            onTap: () {},
            onActionTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('quarterly_report.pdf'), findsOneWidget);
    expect(find.textContaining('2.50 MB'), findsOneWidget);
  });
}
