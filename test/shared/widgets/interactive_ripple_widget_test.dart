/*
 * File: interactive_ripple_widget_test.dart
 * Description: Widget tests verifying foreground curved ink ripples and Clip.antiAlias on interactive components.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';
import 'package:telstorage/shared/widgets/cards/app_action_card.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Interactive Ripple & Curved Surface Tests', () {
    testWidgets(
        'AppSurfaceCard with onTap renders Material with Clip.antiAlias and InkWell',
        (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AppSurfaceCard(
              radius: 20,
              onTap: () => tapped = true,
              child: const Text('Interactive Card'),
            ),
          ),
        ),
      );

      final materialFinder = find.byWidgetPredicate(
        (w) =>
            w is Material &&
            w.clipBehavior == Clip.antiAlias &&
            w.borderRadius == BorderRadius.circular(20),
      );
      expect(materialFinder, findsOneWidget,
          reason:
              'AppSurfaceCard must use Material with Clip.antiAlias and matching borderRadius');

      final inkWellFinder = find.byType(InkWell);
      expect(inkWellFinder, findsOneWidget,
          reason:
              'AppSurfaceCard with onTap must render an InkWell for ripple feedback');

      await tester.tap(find.text('Interactive Card'));
      expect(tapped, isTrue);
    });

    testWidgets('AppActionCard delegates to curved interactive surface',
        (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AppActionCard(
              icon: Icons.settings,
              title: 'Settings Action',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsOneWidget);
      await tester.tap(find.text('Settings Action'));
      expect(tapped, isTrue);
    });

    testWidgets('AppSurfaceCard supports top-only directional border radius',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AppSurfaceCard(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              onTap: () {},
              child: const Text('Top Only Curved Item'),
            ),
          ),
        ),
      );

      final materialFinder = find.byWidgetPredicate(
        (w) =>
            w is Material &&
            w.borderRadius ==
                const BorderRadius.vertical(top: Radius.circular(16)),
      );
      expect(materialFinder, findsOneWidget);
    });

    testWidgets(
        'AppSurfaceCard supports zero border radius for flat middle items',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AppSurfaceCard(
              borderRadius: BorderRadius.zero,
              onTap: () {},
              child: const Text('Flat Middle Item'),
            ),
          ),
        ),
      );

      final materialFinder = find.byWidgetPredicate(
        (w) => w is Material && w.borderRadius == BorderRadius.zero,
      );
      expect(materialFinder, findsOneWidget);
    });
  });
}
