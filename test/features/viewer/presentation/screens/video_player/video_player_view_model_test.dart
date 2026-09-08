/*
 * File: video_player_view_model_test.dart
 * Description: Unit tests for VideoPlayerViewModel verifying playback controls, position scrubbing, timer auto-hide, and volume changes.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/viewmodel/video_player_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoPlayerViewModel viewModel;

  setUp(() {
    viewModel = VideoPlayerViewModel();
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('VideoPlayerViewModel Unit Tests', () {
    test('TC-VVM-01: initial state has expected defaults', () {
      expect(viewModel.currentFile, isNull);
      expect(viewModel.isInitialized, isFalse);
      expect(viewModel.isPlaying, isFalse);
      expect(viewModel.position, equals(Duration.zero));
      expect(viewModel.duration, equals(Duration.zero));
      expect(viewModel.areControlsVisible, isTrue);
      expect(viewModel.volume, equals(1.0));
      expect(viewModel.errorMessage, isNull);
    });

    test('TC-VVM-02: toggleControls and showControlsTemporarily manage visibility', () {
      expect(viewModel.areControlsVisible, isTrue);

      viewModel.toggleControls();
      expect(viewModel.areControlsVisible, isFalse);

      viewModel.toggleControls();
      expect(viewModel.areControlsVisible, isTrue);

      viewModel.hideControls();
      expect(viewModel.areControlsVisible, isFalse);

      viewModel.showControlsTemporarily();
      expect(viewModel.areControlsVisible, isTrue);
    });

    test('TC-VVM-03: volume clamping between 0.0 and 1.0', () {
      viewModel.setVolume(0.5);
      expect(viewModel.volume, equals(0.5));

      viewModel.setVolume(1.5);
      expect(viewModel.volume, equals(1.0));

      viewModel.setVolume(-0.5);
      expect(viewModel.volume, equals(0.0));
    });

    test('TC-VVM-04: skipForward and skipBackward compute bounded target duration', () {
      viewModel.setMockDurationForTesting(const Duration(seconds: 60));
      viewModel.setMockPositionForTesting(const Duration(seconds: 30));

      // Skip forward 10 seconds -> 40 seconds
      viewModel.skipForward(const Duration(seconds: 10));
      expect(viewModel.position, equals(const Duration(seconds: 40)));

      // Skip forward past end -> clamped to duration 60s
      viewModel.skipForward(const Duration(seconds: 50));
      expect(viewModel.position, equals(const Duration(seconds: 60)));

      // Skip backward 25s -> 35s
      viewModel.skipBackward(const Duration(seconds: 25));
      expect(viewModel.position, equals(const Duration(seconds: 35)));

      // Skip backward past 0 -> clamped to Duration.zero
      viewModel.skipBackward(const Duration(seconds: 100));
      expect(viewModel.position, equals(Duration.zero));
    });
  });
}
