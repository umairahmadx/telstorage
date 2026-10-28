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
}
