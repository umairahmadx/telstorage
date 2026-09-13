/*
 * File: video_player_poster_test.dart
 * Description: Automated test verifying VideoPlayerScreen renders immediate poster ThumbnailWidget and pre-mounts timeline and controls while loading.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/video_player_screen.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/viewmodel/video_player_view_model.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_player_controls_overlay.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_progress_bar.dart';
import 'package:telstorage/shared/widgets/thumbnail_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testFile = FileRecord(
    fileId: 'vid_poster_1',
    name: 'sample_clip.mp4',
    metadataMessageId: 300,
    sizeMb: 45.0,
    mimeType: 'video/mp4',
    uploadedAt: DateTime(2026, 8, 1),
    chunkCount: 3,
    sha256Hash: 'hash_sample_clip',
    thumbnailFileId: 'thumb_vid_poster_1',
  );

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: child,
    );
  }

  group('Video Player Poster & Pre-Mount Tests', () {
    testWidgets('TC-VPP-01: VideoPlayerScreen displays ThumbnailWidget, timeline, and controls immediately on open', (tester) async {
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

      // Verify ThumbnailWidget is rendered as the immediate poster frame
      expect(find.byType(ThumbnailWidget), findsOneWidget);

      // Verify Hero widget wraps the thumbnail with matching heroPrefix
      final heroFinder = find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == 'browser_video_hero_vid_poster_1',
      );
      expect(heroFinder, findsOneWidget);

      // Verify VideoProgressBar (timeline) is pre-mounted and visible immediately
      expect(find.byType(VideoProgressBar), findsOneWidget);

      // Verify VideoPlayerControlsOverlay is pre-mounted and visible immediately
      expect(find.byType(VideoPlayerControlsOverlay), findsOneWidget);

      // Verify buffering indicator is active in the controls overlay
      expect(
        find.descendant(
          of: find.byType(VideoPlayerControlsOverlay),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      viewModel.dispose();
    });
  });
}
