/*
 * File: app_sort_filter_sheet_test.dart
 * Description: Widget tests verifying AppSortFilterSheet background styling, theming, and interaction callbacks.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_event.dart';
import 'package:telstorage/shared/widgets/dialogs/app_sort_filter_sheet.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('AppSortFilterSheet renders background container with bgSurface color and rounded top corners',
      (tester) async {
    final theme = AppTheme.dark();
    final colors = theme.extension<AppColorsExtension>()!;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AppSortFilterSheet(
            currentSort: BrowserSortOption.name,
            isAscending: true,
            currentGroup: BrowserGroupOption.foldersFirst,
            onSortChanged: (_) {},
            onGroupChanged: (_) {},
          ),
        ),
      ),
    );

    // Find Container with BoxDecoration
    final containerFinder = find.byWidgetPredicate((widget) {
      if (widget is Container && widget.decoration is BoxDecoration) {
        final dec = widget.decoration as BoxDecoration;
        return dec.color == colors.bgSurface &&
            dec.borderRadius == const BorderRadius.vertical(top: Radius.circular(24));
      }
      return false;
    });

    expect(containerFinder, findsOneWidget,
        reason: 'AppSortFilterSheet must have a Container decorated with bgSurface and top rounded corners');
  });

  testWidgets('AppSortFilterSheet triggers sort callback and dismisses modal bottom sheet',
      (tester) async {
    BrowserSortOption? selectedSort;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AppSortFilterSheet(
                    currentSort: BrowserSortOption.name,
                    isAscending: true,
                    currentGroup: BrowserGroupOption.foldersFirst,
                    onSortChanged: (sort) => selectedSort = sort,
                    onGroupChanged: (_) {},
                  ),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Sort & Group'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);

    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();

    expect(selectedSort, BrowserSortOption.date);
    expect(find.text('Sort & Group'), findsNothing);
  });

  testWidgets('AppSortFilterSheet triggers group callback and dismisses modal bottom sheet',
      (tester) async {
    BrowserGroupOption? selectedGroup;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AppSortFilterSheet(
                    currentSort: BrowserSortOption.name,
                    isAscending: true,
                    currentGroup: BrowserGroupOption.foldersFirst,
                    onSortChanged: (_) {},
                    onGroupChanged: (grp) => selectedGroup = grp,
                  ),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Mixed'), findsOneWidget);

    await tester.tap(find.text('Mixed'));
    await tester.pumpAndSettle();

    expect(selectedGroup, BrowserGroupOption.mixed);
    expect(find.text('Sort & Group'), findsNothing);
  });
}
