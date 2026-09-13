/*
 * File: video_player_features_test.dart
 * Description: Automated test verifying VideoPlayerTopBar buttons (Rotate, Share, More/Details) and orientation management.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/widgets/video_player_top_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testFile = FileRecord(
    fileId: 'vid_feat_1',
    name: 'movie_clip.mp4',
    metadataMessageId: 200,
    sizeMb: 85.0,
    mimeType: 'video/mp4',
    uploadedAt: DateTime(2026, 7, 20),
    chunkCount: 5,
    sha256Hash: 'hash_movie',
  );

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Stack(children: [child]),
      ),
    );
  }

  group('Video Player Features & Options Reproduction Tests', () {
    testWidgets('TC-VPF-01: VideoPlayerTopBar renders Rotate, Share, and More Options buttons', (tester) async {
      var rotateTapped = false;
      var shareTapped = false;
      var moreTapped = false;
      var saveTapped = false;

      await tester.pumpWidget(
        wrapWithTheme(
          VideoPlayerTopBar(
            file: testFile,
            currentIndex: 0,
            totalCount: 1,
            isVisible: true,
            onBack: () {},
            onSave: () => saveTapped = true,
            onRotate: () => rotateTapped = true,
            onShare: () => shareTapped = true,
            onMore: () => moreTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all buttons exist
      expect(find.byTooltip('Rotate orientation'), findsOneWidget);
      expect(find.byTooltip('Share video'), findsOneWidget);
      expect(find.byTooltip('More options'), findsOneWidget);
      expect(find.byTooltip('Save to Downloads'), findsOneWidget);

      // Tap Rotate
      await tester.tap(find.byTooltip('Rotate orientation'));
      expect(rotateTapped, isTrue);

      // Tap Share
      await tester.tap(find.byTooltip('Share video'));
      expect(shareTapped, isTrue);

      // Tap More
      await tester.tap(find.byTooltip('More options'));
      expect(moreTapped, isTrue);

      // Tap Save
      await tester.tap(find.byTooltip('Save to Downloads'));
      expect(saveTapped, isTrue);
    });
  });
}
