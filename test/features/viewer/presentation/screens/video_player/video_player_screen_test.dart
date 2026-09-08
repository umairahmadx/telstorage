/*
 * File: video_player_screen_test.dart
 * Description: Widget tests for VideoPlayerScreen UI components verifying top bar, control overlay, and progress bar layout.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_player_top_bar.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_player_controls_overlay.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_progress_bar.dart';

void main() {
  final testFile = FileRecord(
    fileId: 'vid_ui_1',
    name: 'vacation_video.mp4',
    metadataMessageId: 10,
    sizeMb: 52.4,
    mimeType: 'video/mp4',
    uploadedAt: DateTime(2026, 6, 15),
    chunkCount: 3,
    sha256Hash: 'hash_vacation',
  );

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Stack(children: [child]),
      ),
    );
  }

  group('Video Player UI Widget Tests', () {
    testWidgets('TC-VUI-01: VideoPlayerTopBar displays title, counter and handles callbacks', (tester) async {
      var backPressed = false;
      var savePressed = false;

      await tester.pumpWidget(
        wrapWithTheme(
          VideoPlayerTopBar(
            file: testFile,
            currentIndex: 0,
            totalCount: 3,
            isVisible: true,
            onBack: () => backPressed = true,
            onSave: () => savePressed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('vacation_video.mp4'), findsOneWidget);
      expect(find.text('1 of 3 • ${testFile.formattedSize}'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      expect(backPressed, isTrue);

      await tester.tap(find.byTooltip('Save to Downloads'));
      expect(savePressed, isTrue);
    });

    testWidgets('TC-VUI-02: VideoPlayerControlsOverlay renders play, skip buttons and dispatches events', (tester) async {
      var playToggle = false;
      var skipFwd = false;
      var skipBwd = false;

      await tester.pumpWidget(
        wrapWithTheme(
          VideoPlayerControlsOverlay(
            isPlaying: false,
            isBuffering: false,
            isVisible: true,
            onPlayPause: () => playToggle = true,
            onSkipForward: () => skipFwd = true,
            onSkipBackward: () => skipBwd = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      expect(playToggle, isTrue);

      await tester.tap(find.byIcon(Icons.replay_10_rounded));
      expect(skipBwd, isTrue);

      await tester.tap(find.byIcon(Icons.forward_10_rounded));
      expect(skipFwd, isTrue);
    });

    testWidgets('TC-VUI-03: VideoProgressBar formats timestamps and triggers seek', (tester) async {
      Duration? seekTarget;

      await tester.pumpWidget(
        wrapWithTheme(
          VideoProgressBar(
            position: const Duration(minutes: 1, seconds: 30),
            duration: const Duration(minutes: 5),
            buffered: const [],
            onSeek: (target) => seekTarget = target,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('01:30'), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);

      await tester.tap(find.byType(Slider));
      expect(seekTarget, isNotNull);
    });
  });
}
