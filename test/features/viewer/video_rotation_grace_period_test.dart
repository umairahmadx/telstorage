/*
 * File: video_rotation_grace_period_test.dart
 * Description: Rule 10 Automated Reproduction Test for video player rotation timed sensor revert and grace period.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/video_player_screen.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/viewmodel/video_player_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testFile = FileRecord(
    fileId: 'vid_rotation_test',
    name: 'rotation_test.mp4',
    metadataMessageId: 400,
    sizeMb: 20.0,
    mimeType: 'video/mp4',
    uploadedAt: DateTime(2026, 8, 10),
    chunkCount: 2,
    sha256Hash: 'hash_rot',
  );

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: child,
    );
  }

  group('Video Player Rotation Grace Period Tests', () {
    testWidgets(
        'Tapping Rotate button keeps Landscape locked for 3.5s grace period before dynamic sensor revert',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final orientationCalls = <List<String>>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          final list = (call.arguments as List).cast<String>();
          orientationCalls.add(list);
        }
        return null;
      });

      final viewModel = VideoPlayerViewModel();

      await tester.pumpWidget(
        wrapWithTheme(
          VideoPlayerScreen(
            videos: [testFile],
            initialIndex: 0,
            heroPrefix: 'browser',
            viewModel: viewModel,
          ),
        ),
      );
      await tester.pump();

      // Clear calls from initState
      orientationCalls.clear();

      // Tap rotate button in portrait
      final rotateFinder = find.byTooltip('Rotate orientation');
      expect(rotateFinder, findsOneWidget);
      await tester.tap(rotateFinder);
      await tester.pump();

      // Immediately after tap, orientations must be locked to landscape
      expect(orientationCalls.isNotEmpty, isTrue);
      expect(
        orientationCalls.last,
        containsAll([
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]),
      );
      expect(orientationCalls.last, isNot(contains('DeviceOrientation.portraitUp')));

      // Advance by 1 second (t = 1000ms)
      await tester.pump(const Duration(milliseconds: 1000));

      // In buggy code with 600ms timer: already reverted to all 4 orientations at t=600ms!
      // This assertion fails RED against buggy code because last call has portraitUp
      expect(
        orientationCalls.last,
        isNot(contains('DeviceOrientation.portraitUp')),
        reason: 'At t = 1000ms, player should STILL be locked to landscape (not reverted at 600ms)',
      );

      // Advance by another 1 second (t = 2000ms)
      await tester.pump(const Duration(milliseconds: 1000));
      expect(
        orientationCalls.last,
        isNot(contains('DeviceOrientation.portraitUp')),
        reason: 'At t = 2000ms, player should STILL be locked to landscape',
      );

      // Advance past the 3.5s grace period (t = 3600ms)
      await tester.pump(const Duration(milliseconds: 1600));

      // After 3.5s, sensor orientations are re-enabled
      expect(
        orientationCalls.last,
        contains('DeviceOrientation.portraitUp'),
        reason: 'After 3.5s grace period, dynamic sensor orientations should be restored',
      );
    });
  });
}
