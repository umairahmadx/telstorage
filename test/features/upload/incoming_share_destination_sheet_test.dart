import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/incoming_share_destination_sheet.dart';

void main() {
  testWidgets('lets the user select a nested destination before uploading',
      (tester) async {
    IncomingShareDestination? result;
    final now = DateTime(2026, 1, 1);
    final folders = [
      FolderRecord(id: 'docs', name: 'Documents', createdAt: now),
      FolderRecord(
        id: 'taxes',
        name: 'Taxes',
        parentId: 'docs',
        createdAt: now,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await IncomingShareDestinationSheet.show(
                context,
                fileNames: const ['receipt.pdf'],
                folders: folders,
              );
            },
            child: const Text('Choose destination'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(find.text('receipt.pdf'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    expect(find.text('Taxes'), findsOneWidget);

    await tester.tap(find.text('Upload here'));
    await tester.pumpAndSettle();
    expect(result?.folderId, 'docs');
  });

  testWidgets('creates a new folder and uploads into it', (tester) async {
    IncomingShareDestination? result;
    final now = DateTime(2026, 1, 1);
    String? createdName;
    String? createdParentId;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await IncomingShareDestinationSheet.show(
                context,
                fileNames: const ['receipt.pdf'],
                folders: [
                  FolderRecord(id: 'docs', name: 'Documents', createdAt: now),
                ],
                onCreateFolder: (name, parentId) async {
                  createdName = name;
                  createdParentId = parentId;
                  return FolderRecord(
                    id: 'new-folder',
                    name: name,
                    parentId: parentId,
                    createdAt: now,
                  );
                },
              );
            },
            child: const Text('Choose destination'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Receipts');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(createdName, 'Receipts');
    expect(createdParentId, 'docs');
    expect(find.text('Destination: Receipts'), findsOneWidget);

    await tester.tap(find.text('Upload here'));
    await tester.pumpAndSettle();
    expect(result?.folderId, 'new-folder');
  });

  testWidgets('hides folder creation when no callback is provided',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => IncomingShareDestinationSheet.show(
              context,
              fileNames: const ['receipt.pdf'],
              folders: const [],
            ),
            child: const Text('Choose destination'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('New folder'), findsNothing);
  });
}
