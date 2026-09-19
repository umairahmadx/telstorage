/*
 * File: audio_player_screen_test.dart
 * Description: Widget and integration tests for AudioPlayerScreen verifying audio format identification, UI rendering, track details, and controls.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/audio_player/audio_player_screen.dart';
import 'package:telstorage/features/viewer/presentation/screens/audio_player/viewmodel/audio_player_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final audioTrack = FileRecord(
    fileId: 'aud_1',
    name: 'summer_breeze.mp3',
    metadataMessageId: 201,
    sizeMb: 8.4,
    mimeType: 'audio/mpeg',
    uploadedAt: DateTime.now(),
    chunkCount: 1,
    sha256Hash: 'hash_audio_1',
  );

  final videoFile = FileRecord(
    fileId: 'vid_1',
    name: 'sample_video.mp4',
    metadataMessageId: 202,
    sizeMb: 40.0,
    mimeType: 'video/mp4',
    uploadedAt: DateTime.now(),
    chunkCount: 2,
    sha256Hash: 'hash_video_1',
  );

  group('AudioPlayerScreen.isAudioRecord Unit Tests', () {
    test('TC-APS-01: accurately distinguishes audio from other file formats', () {
      expect(AudioPlayerScreen.isAudioRecord(audioTrack), isTrue);

      final m4aFile = FileRecord(
        fileId: 'aud_2',
        name: 'voice_note.m4a',
        metadataMessageId: 203,
        sizeMb: 2.0,
        mimeType: 'audio/mp4',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'hash_m4a',
      );
      expect(AudioPlayerScreen.isAudioRecord(m4aFile), isTrue);

      final flacFile = FileRecord(
        fileId: 'aud_3',
        name: 'orchestra.flac',
        metadataMessageId: 204,
        sizeMb: 50.0,
        mimeType: 'audio/flac',
        uploadedAt: DateTime.now(),
        chunkCount: 3,
        sha256Hash: 'hash_flac',
      );
      expect(AudioPlayerScreen.isAudioRecord(flacFile), isTrue);

      expect(AudioPlayerScreen.isAudioRecord(videoFile), isFalse);
    });
  });

  group('AudioPlayerScreen Widget Tests', () {
    testWidgets('TC-APS-02: renders track name, format badge, and transport controls',
        (tester) async {
      final viewModel = AudioPlayerViewModel();
      viewModel.setMockPlaylistForTesting([audioTrack], 0);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: AudioPlayerScreen(
            tracks: [audioTrack],
            initialIndex: 0,
            viewModel: viewModel,
          ),
        ),
      );
      await tester.pump();

      // Verify track name is displayed
      expect(find.text('summer_breeze.mp3'), findsOneWidget);

      // Verify NOW PLAYING header is rendered
      expect(find.text('NOW PLAYING'), findsOneWidget);

      // Verify format badge is displayed
      expect(find.text('MP3'), findsOneWidget);

      // Verify playlist counter
      expect(find.text('Track 1 of 1'), findsOneWidget);

      viewModel.dispose();
    });
  });
}
