/*
 * File: audio_lyrics_test.dart
 * Description: Widget and integration tests for audio player synced lyrics view, active line highlighting, tap-to-seek, and timing adjustments.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/lyric_line.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/audio_player/audio_player_screen.dart';
import 'package:telstorage/features/viewer/presentation/screens/audio_player/viewmodel/audio_player_view_model.dart';
import 'package:telstorage/features/viewer/presentation/screens/audio_player/widgets/audio_lyrics_view.dart';

void main() {
  final testTrack = FileRecord(
    fileId: 'audio_test_1',
    name: 'Sample Artist - Test Song.mp3',
    metadataMessageId: 10,
    sizeMb: 5.0,
    mimeType: 'audio/mpeg',
    uploadedAt: DateTime(2026, 1, 1),
    chunkCount: 1,
    sha256Hash: 'dummy',
  );

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('AudioLyricsView Widget Tests', () {
    testWidgets('renders empty state when no lyrics are available', (tester) async {
      final vm = AudioPlayerViewModel();
      vm.setMockPlaylistForTesting([testTrack], 0);

      await tester.pumpWidget(
        wrapWithTheme(AudioLyricsView(viewModel: vm)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Synced Lyrics Found'), findsOneWidget);
      expect(find.text('Import .lrc'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      vm.dispose();
    });

    testWidgets('renders lyrics list and highlights active line', (tester) async {
      final vm = AudioPlayerViewModel();
      vm.setMockPlaylistForTesting([testTrack], 0);
      vm.setMockDurationForTesting(const Duration(minutes: 3));

      final lines = [
        const LyricLine(timestamp: Duration(seconds: 0), text: 'First line'),
        const LyricLine(timestamp: Duration(seconds: 10), text: 'Second line'),
        const LyricLine(timestamp: Duration(seconds: 20), text: 'Third line'),
      ];
      vm.setLyrics(lines);
      vm.setMockPositionForTesting(const Duration(seconds: 12));

      await tester.pumpWidget(
        wrapWithTheme(AudioLyricsView(viewModel: vm)),
      );
      await tester.pumpAndSettle();

      expect(find.text('First line'), findsOneWidget);
      expect(find.text('Second line'), findsOneWidget);
      expect(find.text('Third line'), findsOneWidget);
      expect(vm.currentLyricIndex, equals(1));

      vm.dispose();
    });

    testWidgets('adjusts offset via sync bar buttons', (tester) async {
      final vm = AudioPlayerViewModel();
      vm.setMockPlaylistForTesting([testTrack], 0);

      await tester.pumpWidget(
        wrapWithTheme(AudioLyricsView(viewModel: vm)),
      );
      await tester.pumpAndSettle();

      expect(find.text('In Sync'), findsOneWidget);

      // Tap +250 ms
      await tester.tap(find.byTooltip('+250 ms'));
      await tester.pumpAndSettle();

      expect(vm.lyricsOffset, equals(const Duration(milliseconds: 250)));
      expect(find.text('+250 ms'), findsOneWidget);

      // Tap -250 ms twice
      await tester.tap(find.byTooltip('-250 ms'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('-250 ms'));
      await tester.pumpAndSettle();

      expect(vm.lyricsOffset, equals(const Duration(milliseconds: -250)));
      expect(find.text('-250 ms'), findsOneWidget);

      // Tap offset text to reset
      await tester.tap(find.text('-250 ms'));
      await tester.pumpAndSettle();

      expect(vm.lyricsOffset, equals(Duration.zero));
      expect(find.text('In Sync'), findsOneWidget);

      vm.dispose();
    });

    testWidgets('tapping a lyric seeks playback to that timestamp', (tester) async {
      final vm = AudioPlayerViewModel();
      vm.setMockPlaylistForTesting([testTrack], 0);
      vm.setMockDurationForTesting(const Duration(minutes: 3));

      final lines = [
        const LyricLine(timestamp: Duration(seconds: 5), text: 'Intro verse'),
        const LyricLine(timestamp: Duration(seconds: 35), text: 'Chorus melody'),
      ];
      vm.setLyrics(lines);

      await tester.pumpWidget(
        wrapWithTheme(AudioLyricsView(viewModel: vm)),
      );
      await tester.pumpAndSettle();

      // Tap Chorus melody
      await tester.tap(find.text('Chorus melody'));
      await tester.pump();

      expect(vm.position, equals(const Duration(seconds: 35)));

      vm.dispose();
    });
  });

  group('AudioPlayerScreen Lyrics Integration Tests', () {
    testWidgets('toggles lyrics view when lyrics icon button is pressed', (tester) async {
      final vm = AudioPlayerViewModel();
      vm.setMockPlaylistForTesting([testTrack], 0);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: AudioPlayerScreen(
            tracks: [testTrack],
            initialIndex: 0,
            viewModel: vm,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Lyrics icon button should be present in secondary controls
      final lyricsToggle = find.byTooltip('Lyrics');
      expect(lyricsToggle, findsOneWidget);
      expect(vm.isLyricsViewActive, isFalse);

      // Tap to activate lyrics
      await tester.tap(lyricsToggle);
      await tester.pumpAndSettle();

      expect(vm.isLyricsViewActive, isTrue);
      expect(find.byType(AudioLyricsView), findsOneWidget);

      // Tap again to return to artwork visualizer
      await tester.tap(lyricsToggle);
      await tester.pumpAndSettle();

      expect(vm.isLyricsViewActive, isFalse);
      expect(find.byType(AudioLyricsView), findsNothing);

      vm.dispose();
    });
  });
}
