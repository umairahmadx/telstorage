import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/browser/screens/widgets/browser_folder_tile.dart';
import 'package:telstorage/core/models/folder_record.dart';

void main() {
  testWidgets('folder tile renders its name and item count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: BrowserFolderTile(
            folder: FolderRecord(
              id: 'folder-1',
              name: 'Documents',
              createdAt: DateTime(2026),
            ),
            itemCount: 3,
            onTap: () {},
            onLongPress: () {},
            onMore: () {},
          ),
        ),
      ),
    );

    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('3 items'), findsOneWidget);
  });
}
