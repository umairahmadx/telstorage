/*
 * File: rename_file_dialog_test.dart
 * Description: Widget tests for the rename file dialog covering the locked extension chip, confirm validation, and small-screen layout.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/dialogs/app_dialogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Opens [AppDialogs.showRenameFile] from a themed scaffold and reports the
  /// eventual dialog result through [onResult].
  Future<void> openRenameDialog(
    WidgetTester tester,
    String fileName,
    void Function(String?) onResult, {
    Size? surfaceSize,
  }) async {
    if (surfaceSize != null) {
      tester.view.physicalSize = surfaceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  onResult(await AppDialogs.showRenameFile(
                    context,
                    fileName: fileName,
                  ));
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('Rename File Dialog', () {
    testWidgets('pre-fills base name and renders extension as a locked chip',
        (tester) async {
      await openRenameDialog(tester, 'report.jpg', (_) {});

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'report');
      // The extension exists only as static text, never inside the field.
      expect(find.text('.jpg'), findsOneWidget);
      expect(find.text('report.jpg'), findsNothing);
      expect(find.text('The .jpg extension stays fixed.'), findsOneWidget);
    });

    testWidgets('keeps only the last extension locked for multi-dot names',
        (tester) async {
      await openRenameDialog(tester, 'archive.tar.gz', (_) {});

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'archive.tar');
      expect(find.text('.gz'), findsOneWidget);
    });

    testWidgets('confirm returns trimmed base name plus locked extension',
        (tester) async {
      String? result;
      await openRenameDialog(tester, 'report.jpg', (v) => result = v);

      await tester.enterText(find.byType(TextField), '  quarterly report ');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(result, 'quarterly report.jpg');
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('confirm stays disabled while the base name is empty',
        (tester) async {
      String? result;
      await openRenameDialog(tester, 'report.jpg', (v) => result = v);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirm.onPressed, isNull);

      // Tapping a disabled confirm must not close the dialog or return.
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(result, isNull);

      await tester.enterText(find.byType(TextField), 'notes');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('file without an extension stays fully editable with no chip',
        (tester) async {
      String? result;
      await openRenameDialog(tester, 'README', (v) => result = v);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'README');
      expect(find.text('Enter a name for this file.'), findsOneWidget);

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(result, 'README');
    });

    testWidgets('fits a 320x568 small screen without overflow', (tester) async {
      await openRenameDialog(
        tester,
        'a-reasonably-long-file-name-for-testing-here.jpg',
        (_) {},
        surfaceSize: const Size(320, 568),
      );

      // No RenderFlex overflow on a small screen.
      expect(tester.takeException(), isNull);

      final dialogSize = tester.getSize(find.byType(AlertDialog));
      expect(dialogSize.width, lessThanOrEqualTo(320));
      expect(dialogSize.height, lessThanOrEqualTo(568));

      // The visible card still respects the 24dp inset on both sides.
      final titleRect = tester.getRect(find.text('Rename File'));
      expect(titleRect.left, greaterThanOrEqualTo(24));
      expect(titleRect.right, lessThanOrEqualTo(320 - 24));
    });
  });
}