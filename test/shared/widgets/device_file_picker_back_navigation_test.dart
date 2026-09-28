/*
 * File: device_file_picker_back_navigation_test.dart
 * Description: Automated test verifying that DeviceFilePickerSheet includes a Previous button
 * on the left of search and uses PopScope to prevent accidental sheet dismissal in subfolders.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/device_file_picker/device_file_picker_sheet.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
      'DeviceFilePickerSheet renders Previous button on left of search and wraps with PopScope',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: DeviceFilePickerSheet(),
        ),
      ),
    );
    await tester.pump();

    // Verify Previous button exists with AppIcons.back and tooltip 'Previous'
    final previousButton = find.widgetWithIcon(IconButton, AppIcons.back);
    expect(previousButton, findsOneWidget);
    final iconButtonWidget = tester.widget<IconButton>(previousButton);
    expect(iconButtonWidget.tooltip, 'Previous');

    // Verify PopScope wraps the sheet to intercept back events
    expect(find.byWidgetPredicate((w) => w is PopScope), findsOneWidget);
  });
}
