/*
 * File: browser_dialogs_edge_cases_test.dart
 * Description: Widget tests for AppDialogs.showInfo, empty folder guards, and offline alerts in BrowserDialogs.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/widgets/browser_dialogs.dart';
import 'package:telstorage/features/storage/data/repositories/storage_repository.dart';
import 'package:telstorage/shared/widgets/dialogs/app_dialogs.dart';

class _MockEmptyStorageRepository implements StorageRepository {
  @override
  List<FolderRecord> get currentFolders => [];

  @override
  List<FileRecord> get currentFiles => [];

  @override
  List<FolderRecord> getFolders(String? parentId) => [];

  @override
  List<FileRecord> getFiles(String? folderId) => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    Connectivity.mockConnectionStatus = true;
    ServiceLocator.instance
        .setStorageRepositoryForTesting(_MockEmptyStorageRepository());
  });

  tearDown(() {
    Connectivity.mockConnectionStatus = null;
  });

  testWidgets(
      'AppDialogs.showInfo renders title, message, and dismisses cleanly',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(builder: (context) {
        return Scaffold(
          body: ElevatedButton(
            onPressed: () {
              AppDialogs.showInfo(
                context,
                title: 'Notice Title',
                message: 'This is a test notification message.',
              );
            },
            child: const Text('Open'),
          ),
        );
      }),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Notice Title'), findsOneWidget);
    expect(find.text('This is a test notification message.'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Notice Title'), findsNothing);
  });

  testWidgets(
      'BrowserDialogs.downloadFolder shows Empty alert for 0 files when online',
      (tester) async {
    final emptyFolder = FolderRecord(
      id: 'f_empty',
      name: 'Empty Folder',
      parentId: null,
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(builder: (context) {
        return Scaffold(
          body: ElevatedButton(
            onPressed: () {
              BrowserDialogs.downloadFolder(context, emptyFolder);
            },
            child: const Text('Download Empty'),
          ),
        );
      }),
    ));

    await tester.tap(find.text('Download Empty'));
    await tester.pumpAndSettle();

    expect(find.text('Folder is Empty'), findsOneWidget);
    expect(find.text('"Empty Folder" contains no files to download.'),
        findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Folder is Empty'), findsNothing);
  });

  testWidgets(
      'BrowserDialogs.exportFolderAsZip shows Empty alert for 0 files when online',
      (tester) async {
    final emptyFolder = FolderRecord(
      id: 'f_empty_zip',
      name: 'Archive Empty',
      parentId: null,
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(builder: (context) {
        return Scaffold(
          body: ElevatedButton(
            onPressed: () {
              BrowserDialogs.exportFolderAsZip(context, emptyFolder);
            },
            child: const Text('Export Empty'),
          ),
        );
      }),
    ));

    await tester.tap(find.text('Export Empty'));
    await tester.pumpAndSettle();

    expect(find.text('Folder is Empty'), findsOneWidget);
    expect(find.text('"Archive Empty" contains no files to export.'),
        findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Folder is Empty'), findsNothing);
  });

  testWidgets(
      'EC-18: BrowserDialogs.downloadFolder shows Offline alert when device is offline',
      (tester) async {
    Connectivity.mockConnectionStatus = false;
    final folder = FolderRecord(
      id: 'f_offline',
      name: 'Offline Folder',
      parentId: null,
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(builder: (context) {
        return Scaffold(
          body: ElevatedButton(
            onPressed: () {
              BrowserDialogs.downloadFolder(context, folder);
            },
            child: const Text('Download Offline'),
          ),
        );
      }),
    ));

    await tester.tap(find.text('Download Offline'));
    await tester.pumpAndSettle();

    expect(find.text('Offline'), findsOneWidget);
    expect(
        find.text(
            'You are currently offline. Please check your internet connection to download folders.'),
        findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Offline'), findsNothing);
  });
}
