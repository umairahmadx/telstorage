/*
 * File: audio_player_view_model_test.dart
 * Description: Unit tests for AudioPlayerViewModel verifying playlist navigation, volume, seeking, speed multipliers, and repeat modes.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/features/viewer/presentation/screens/audio_player/viewmodel/audio_player_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AudioPlayerViewModel viewModel;

  setUp(() {
    viewModel = AudioPlayerViewModel();
  });

  tearDown(() {
    viewModel.dispose();
  });

  final track1 = FileRecord(
    fileId: 'track_1',
    name: 'first_song.mp3',
    metadataMessageId: 101,
    sizeMb: 5.0,
    mimeType: 'audio/mpeg',
    uploadedAt: DateTime.now(),
    chunkCount: 1,
    sha256Hash: 'hash1',
  );

  final track2 = FileRecord(
    fileId: 'track_2',
    name: 'second_song.flac',
    metadataMessageId: 102,
    sizeMb: 25.0,
    mimeType: 'audio/flac',
    uploadedAt: DateTime.now(),
    chunkCount: 2,
    sha256Hash: 'hash2',
  );

  group('AudioPlayerViewModel Unit Tests', () {
    test('TC-AVM-01: initial state has expected defaults', () {
      expect(viewModel.currentTrack, isNull);
      expect(viewModel.playlist, isEmpty);
      expect(viewModel.currentIndex, equals(0));
      expect(viewModel.isInitialized, isFalse);
      expect(viewModel.isPlaying, isFalse);
      expect(viewModel.position, equals(Duration.zero));
      expect(viewModel.duration, equals(Duration.zero));
      expect(viewModel.volume, equals(1.0));
      expect(viewModel.playbackSpeed, equals(1.0));
      expect(viewModel.repeatMode, equals(AudioRepeatMode.off));
      expect(viewModel.errorMessage, isNull);
    });

    test('TC-AVM-02: volume clamping between 0.0 and 1.0', () {
      viewModel.setVolume(0.7);
      expect(viewModel.volume, equals(0.7));

      viewModel.setVolume(1.8);
      expect(viewModel.volume, equals(1.0));

      viewModel.setVolume(-0.4);
      expect(viewModel.volume, equals(0.0));
    });

    test('TC-AVM-03: repeat mode toggles cycle off -> all -> one -> off', () {
      expect(viewModel.repeatMode, equals(AudioRepeatMode.off));

      viewModel.toggleRepeat();
      expect(viewModel.repeatMode, equals(AudioRepeatMode.all));

      viewModel.toggleRepeat();
      expect(viewModel.repeatMode, equals(AudioRepeatMode.one));

      viewModel.toggleRepeat();
      expect(viewModel.repeatMode, equals(AudioRepeatMode.off));
    });

    test('TC-AVM-04: skipForward and skipBackward compute bounded timestamps', () {
      viewModel.setMockDurationForTesting(const Duration(seconds: 120));
      viewModel.setMockPositionForTesting(const Duration(seconds: 40));

      // Skip forward 10 seconds -> 50 seconds
      viewModel.skipForward(const Duration(seconds: 10));
      expect(viewModel.position, equals(const Duration(seconds: 50)));

      // Skip backward 20 seconds -> 30 seconds
      viewModel.skipBackward(const Duration(seconds: 20));
      expect(viewModel.position, equals(const Duration(seconds: 30)));

      // Skip backward past zero -> clamped to 0
      viewModel.skipBackward(const Duration(seconds: 100));
      expect(viewModel.position, equals(Duration.zero));

      // Skip forward past duration -> clamped to duration
      viewModel.skipForward(const Duration(seconds: 200));
      expect(viewModel.position, equals(const Duration(seconds: 120)));
    });

    test('TC-AVM-05: mock playlist initializes correctly', () {
      viewModel.setMockPlaylistForTesting([track1, track2], 1);
      expect(viewModel.playlist.length, equals(2));
      expect(viewModel.currentIndex, equals(1));
      expect(viewModel.currentTrack?.name, equals('second_song.flac'));
    });
  });
}
