/*
 * File: video_player_redesign_widgets_test.dart
 * Description: Widget tests for the redesigned VideoPlayer bottom bar, speed dialog, chunk inspector, and gesture overlay.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/models/video_aspect_ratio_mode.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/viewmodel/video_player_view_model.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_audio_subtitle_sheet.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_bottom_action_bar.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_chunk_inspector_sheet.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_gesture_overlay.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_speed_dialog.dart';

void main() {
  final testFile = FileRecord(
    fileId: 'test_vid_redesign',
    name: 'sample_movie.mp4',
    metadataMessageId: 101,
    sizeMb: 95.0,
    mimeType: 'video/mp4',
    uploadedAt: DateTime(2026, 7, 1),
    chunkCount: 5,
    sha256Hash: 'hash_redesign',
  );

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(child: child),
      ),
    );
  }

  group('VideoPlayer Redesign UI Widgets', () {
    testWidgets('TC-BAR-01: VideoBottomActionBar renders icon-only buttons and fires callbacks', (tester) async {
      var audioSubtitlesTapped = false;
      var speedTapped = false;
      var aspectToggled = false;
      var cacheInspectorTapped = false;

      await tester.pumpWidget(
        wrapWithTheme(
          VideoBottomActionBar(
            playbackSpeed: 1.5,
            aspectRatioMode: VideoAspectRatioMode.ratio16_9,
            onSpeed: () => speedTapped = true,
            onAspectRatioToggle: () => aspectToggled = true,
            onAudioSubtitles: () => audioSubtitlesTapped = true,
            cachedChunks: 3,
            totalChunks: 5,
            cachedMb: 57.0,
            totalMb: 95.0,
            onCacheInspector: () => cacheInspectorTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check speed text is displayed in compact pill
      expect(find.text('1.5x'), findsOneWidget);
      // Check cache compact badge is displayed
      expect(find.text('3/5 (57/95 MB)'), findsOneWidget);

      // Tap Audio & Subtitles button
      await tester.tap(find.byIcon(AppIcons.subtitles));
      expect(audioSubtitlesTapped, isTrue);

      // Tap Speed badge
      await tester.tap(find.text('1.5x'));
      expect(speedTapped, isTrue);

      // Tap Aspect Ratio direct toggle
      await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
      expect(aspectToggled, isTrue);

      // Tap Cache Badge
      await tester.tap(find.text('3/5 (57/95 MB)'));
      expect(cacheInspectorTapped, isTrue);
    });

    testWidgets('TC-SPD-01: VideoSpeedDialog renders readout, steppers, and preset chips', (tester) async {
      double selectedSpeed = 1.0;

      await tester.pumpWidget(
        wrapWithTheme(
          VideoSpeedDialog(
            currentSpeed: 1.0,
            onSpeedSelected: (s) => selectedSpeed = s,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Playback speed'), findsOneWidget);
      expect(find.text('1.00'), findsOneWidget);
      expect(find.text('0.8x'), findsOneWidget);
      expect(find.text('1.25x'), findsOneWidget);
      expect(find.text('2.0x'), findsOneWidget);

      // Tap preset 1.5x
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();

      expect(selectedSpeed, equals(1.5));
      expect(find.text('1.50'), findsOneWidget);

      // Tap step up > button
      await tester.tap(find.byTooltip('Increase speed'));
      await tester.pumpAndSettle();
      expect(selectedSpeed, equals(1.55));
    });

    testWidgets('TC-CHK-01: VideoChunkInspectorSheet renders cached, queued, and metric summary', (tester) async {
      final vm = VideoPlayerViewModel();
      vm.setMockDurationForTesting(const Duration(minutes: 10));
      vm.setMockCachedChunksForTesting({0, 1, 2});

      await tester.pumpWidget(
        wrapWithTheme(
          VideoChunkInspectorSheet(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Streaming & Cache Inspector'), findsOneWidget);
      expect(find.text('Cached Chunks'), findsOneWidget);
      expect(find.text('Downloaded Data'), findsOneWidget);

      vm.dispose();
    });

    testWidgets('TC-GST-01: VideoGestureOverlay supports horizontal scrub and vertical drag with opposite-side HUDs', (tester) async {
      final vm = VideoPlayerViewModel();
      vm.setMockDurationForTesting(const Duration(minutes: 10));
      vm.setMockPositionForTesting(const Duration(minutes: 2));

      await tester.pumpWidget(
        wrapWithTheme(
          VideoGestureOverlay(
            viewModel: vm,
            onTap: () {},
            child: const SizedBox(width: 400, height: 400),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final overlayRect = tester.getRect(find.byType(VideoGestureOverlay));
      final screenMidX = overlayRect.center.dx;

      // 1. Drag vertically on left half (brightness gesture)
      final leftCenter = overlayRect.center - const Offset(150, 0);
      await tester.dragFrom(leftCenter, const Offset(0, -80));
      await tester.pump();

      // Brightness HUD MUST appear on the opposite (RIGHT) side of the screen
      final brightnessIconFinder = find.byWidgetPredicate(
        (w) => w is Icon && (w.icon == Icons.brightness_high_rounded ||
            w.icon == Icons.brightness_medium_rounded ||
            w.icon == Icons.brightness_low_rounded),
      );
      expect(brightnessIconFinder, findsOneWidget);
      final brightnessCenter = tester.getCenter(brightnessIconFinder);
      expect(brightnessCenter.dx, greaterThan(screenMidX),
          reason: 'Brightness HUD should appear on the RIGHT side when swiping on the left');

      await tester.pump(const Duration(seconds: 2)); // wait for fade out

      // 2. Drag vertically on right half (volume gesture)
      final rightCenter = overlayRect.center + const Offset(150, 0);
      await tester.dragFrom(rightCenter, const Offset(0, -80));
      await tester.pump();

      // Volume HUD MUST appear on the opposite (LEFT) side of the screen
      final volumeIconFinder = find.byWidgetPredicate(
        (w) => w is Icon && (w.icon == Icons.volume_up_rounded ||
            w.icon == Icons.volume_down_rounded ||
            w.icon == Icons.volume_mute_rounded),
      );
      expect(volumeIconFinder, findsOneWidget);
      final volumeCenter = tester.getCenter(volumeIconFinder);
      expect(volumeCenter.dx, lessThan(screenMidX),
          reason: 'Volume HUD should appear on the LEFT side when swiping on the right');

      await tester.pump(const Duration(seconds: 2));

      vm.dispose();
    });

    testWidgets('TC-SUB-01: VideoAudioSubtitleSheet renders audio and subtitle sections', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          VideoAudioSubtitleSheet(
            videoTitle: testFile.name,
            audioTracks: const [],
            selectedAudioTrack: null,
            onAudioTrackSelected: (_) {},
            subtitleTracks: const [],
            selectedSubtitleTrack: null,
            subtitleDelay: Duration.zero,
            onSubtitleTrackSelected: (_) {},
            onExternalSubtitleLoaded: (_) {},
            onDelayAdjusted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Subtitles'), findsOneWidget);
      expect(find.text('Disable track'), findsOneWidget);
      expect(find.text('No track'), findsOneWidget);
      expect(find.text('Search subtitles online'), findsOneWidget);
      expect(find.text('Load from storage'), findsOneWidget);
    });
  });
}
