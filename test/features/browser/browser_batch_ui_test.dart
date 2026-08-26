/*
 * File: browser_batch_ui_test.dart
 * Description: Widget tests verifying AppBatchActionBar Select All toggle and download buttons.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/bars/app_batch_action_bar.dart';

void main() {
  testWidgets('TC-01: AppBatchActionBar renders Select All and Download buttons correctly', (tester) async {
    bool downloadTriggered = false;
    bool selectAllTriggered = false;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        bottomNavigationBar: AppBatchActionBar(
          selectedCount: 3,
          isAllSelected: false,
          onClearSelection: () {},
          onToggleSelectAll: () => selectAllTriggered = true,
          onDownload: () => downloadTriggered = true,
        ),
      ),
    ));

    expect(find.text('3 selected'), findsOneWidget);
    expect(find.byIcon(Icons.select_all_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.download_rounded));
    expect(downloadTriggered, isTrue);

    await tester.tap(find.byIcon(Icons.select_all_rounded));
    expect(selectAllTriggered, isTrue);
  });

  testWidgets('TC-02: AppBatchActionBar renders Deselect icon when isAllSelected is true', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        bottomNavigationBar: AppBatchActionBar(
          selectedCount: 5,
          isAllSelected: true,
          onClearSelection: () {},
          onToggleSelectAll: () {},
        ),
      ),
    ));

    expect(find.byIcon(Icons.deselect_rounded), findsOneWidget);
  });
}
