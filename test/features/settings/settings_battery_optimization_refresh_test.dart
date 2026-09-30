/*
 * File: settings_battery_optimization_refresh_test.dart
 * Description: Widget tests validating that the Settings battery tile re-checks
 *   the optimization status when the Settings tab becomes the visible tab again
 *   (regression test for the stale "Restricted" state that persisted after the
 *   exemption was granted from the upload prompt).
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/core/utils/battery_optimization_helper.dart';
import 'package:telstorage/features/settings/presentation/screens/settings/widgets/settings_tools_card.dart';
import 'package:telstorage/shared/widgets/tab_visibility_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const batteryTileTitle = 'Background Upload & Battery';
  const unrestrictedSubtitle = 'Unrestricted (optimized for background)';
  const restrictedSubtitle = 'Restricted — tap to enable for large transfers';

  // How many status checks the card asked the helper to perform. Counted by the
  // injected check below, so the tests observe refreshes without depending on a
  // real permission_handler platform channel.
  late int statusCheckCount;

  // State reported by the injected check. False means battery optimization is
  // still active, i.e. the exemption has not been granted yet.
  late bool isExempt;

  setUp(() {
    statusCheckCount = 0;
    isExempt = false;
    BatteryOptimizationHelper.statusCheckOverride = () async {
      statusCheckCount++;
      return isExempt;
    };
  });

  tearDown(() {
    BatteryOptimizationHelper.statusCheckOverride = null;
  });

  /// Mirrors how MobileShell hosts tabs: the card stays mounted inside an
  /// IndexedStack while the scope reports which tab is presented, so switching
  /// tabs never recreates the card state.
  Widget createTestHost({required bool settingsTabVisible}) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: TabVisibilityScope(
        visibleTab: settingsTabVisible ? ShellTab.settings : ShellTab.home,
        child: Scaffold(
          body: IndexedStack(
            index: settingsTabVisible ? 1 : 0,
            children: const [
              SizedBox.shrink(), // Stands in for another tab, e.g. Home.
              SettingsToolsCard(),
            ],
          ),
        ),
      ),
    );
  }

  group('SettingsToolsCard battery optimization status', () {
    testWidgets('reports the restricted state while the exemption is missing',
        (tester) async {
      await tester.pumpWidget(createTestHost(settingsTabVisible: true));
      await tester.pumpAndSettle();

      expect(find.text(batteryTileTitle), findsOneWidget);
      expect(find.text(restrictedSubtitle), findsOneWidget);
      expect(statusCheckCount, 1);
    });

    testWidgets('re-checks and clears the stale state on tab re-entry',
        (tester) async {
      // The Settings tab is built but hidden, as on app start with Home shown.
      await tester.pumpWidget(createTestHost(settingsTabVisible: false));
      await tester.pumpAndSettle();

      expect(statusCheckCount, 1,
          reason: 'The card checks the status once when first built');

      // The user grants the exemption elsewhere, e.g. from the upload prompt.
      isExempt = true;

      // Returning to Settings must re-read the status the platform reports.
      await tester.pumpWidget(createTestHost(settingsTabVisible: true));
      await tester.pumpAndSettle();

      expect(statusCheckCount, 2,
          reason: 'Re-showing the Settings tab must trigger a fresh check');
      expect(find.text(unrestrictedSubtitle), findsOneWidget,
          reason: 'Stale restricted state must not survive tab re-entry');
      expect(find.text(restrictedSubtitle), findsNothing);
    });

    testWidgets('does not re-check while the Settings tab stays hidden',
        (tester) async {
      await tester.pumpWidget(createTestHost(settingsTabVisible: false));
      await tester.pumpAndSettle();
      expect(statusCheckCount, 1);

      isExempt = true;

      // The visible tab is still not Settings, so nothing has to refresh yet.
      await tester.pumpWidget(createTestHost(settingsTabVisible: false));
      await tester.pumpAndSettle();

      expect(statusCheckCount, 1,
          reason: 'No fresh check while the tab is not presented');
    });

    testWidgets('checks once when hosted outside the shell', (tester) async {
      // Screens pushed on their own have no TabVisibilityScope, and the card
      // must still render and query the status exactly once.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(child: SettingsToolsCard()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(statusCheckCount, 1);
      expect(find.text(restrictedSubtitle), findsOneWidget);
    });
  });
}
