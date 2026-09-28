/*
 * File: mobile_shell_add_action_sheet_test.dart
 * Description: Automated test reproducing and verifying resolution of subtitle overflow in MobileAddActionSheet.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/mobile_shell/mobile_add_action_sheet.dart';

void main() {
  testWidgets('MobileAddActionSheet renders all tiles without layout overflow',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: MobileAddActionSheet(
            onMedia: () {},
            onFiles: () {},
            onFolder: () {},
            onNewFolder: () {},
          ),
        ),
      ),
    );

    expect(find.text('Photos & Videos'), findsOneWidget);
    expect(find.text('Select from gallery'), findsOneWidget);
    expect(find.text('Upload Files'), findsOneWidget);
    expect(find.text('Upload Folder'), findsOneWidget);
    expect(find.text('New Folder'), findsOneWidget);

    // Any overflow during layout will be caught as a FlutterError
    expect(tester.takeException(), isNull);
  });
}
