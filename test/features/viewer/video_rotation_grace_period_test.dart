/*
 * File: video_rotation_grace_period_test.dart
 * Description: Unit tests verifying strictly manual button-driven orientation lock without gyroscope auto-reversion.
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

  group('Video Player Manual Rotation Tests', () {
    testWidgets(
        'Tapping Rotate button locks to Landscape and does not auto-revert to sensor rotation',
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

      // Advance by 5 seconds: must STAY locked to landscape without gyro reversion
      await tester.pump(const Duration(seconds: 5));
      expect(
        orientationCalls.last,
        isNot(contains('DeviceOrientation.portraitUp')),
        reason: 'Player must remain locked to landscape without gyro auto-revert',
      );

      // Tap rotate button again to return to portrait
      await tester.tap(rotateFinder);
      await tester.pump();

      expect(
        orientationCalls.last,
        contains('DeviceOrientation.portraitUp'),
      );
    });
  });
}
