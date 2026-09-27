/*
 * File: video_player_software_fallback_test.dart
 * Description: Unit tests verifying hardware decoding error detection, software fallback trigger, and drag scrubbing math.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/viewmodel/video_buffer_sync_controller.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/viewmodel/video_drag_scrubber.dart';
import 'package:telstorage/features/viewer/presentation/screens/video_player/viewmodel/video_player_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoPlayer Software Fallback & Resilience Tests', () {
    test('TC-VFB-01: isHardwareDecodeError correctly identifies hardware acceleration errors', () {
      expect(VideoPlayerViewModel.isHardwareDecodeError('mediacodec: init failed'), isTrue);
      expect(VideoPlayerViewModel.isHardwareDecodeError('Both surface and native_window are NULL'), isTrue);
      expect(VideoPlayerViewModel.isHardwareDecodeError('ExtendedACodec decoder configure error'), isTrue);
      expect(VideoPlayerViewModel.isHardwareDecodeError('Hardware acceleration error -38'), isTrue);
      expect(VideoPlayerViewModel.isHardwareDecodeError('OMX.qcom.video.decoder error'), isTrue);
      expect(VideoPlayerViewModel.isHardwareDecodeError('codec init failed'), isTrue);
      expect(VideoPlayerViewModel.isHardwareDecodeError('hwdec configuration failed'), isTrue);

      // Non-hardware errors should not trigger hardware fallback
      expect(VideoPlayerViewModel.isHardwareDecodeError('Connection refused'), isFalse);
      expect(VideoPlayerViewModel.isHardwareDecodeError('HTTP 404 Not Found'), isFalse);
      expect(VideoPlayerViewModel.isHardwareDecodeError('SocketException: Host unreachable'), isFalse);
    });

    test('TC-VFB-02: VideoDragScrubber calculates proportional drag deltas and boundaries', () {
      final scrubber = VideoDragScrubber();
      expect(scrubber.isDragging, isFalse);

      scrubber.start(const Duration(seconds: 30));
      expect(scrubber.isDragging, isTrue);
      expect(scrubber.dragTarget, equals(const Duration(seconds: 30)));
      expect(scrubber.dragDelta, equals(Duration.zero));

      // Drag right 25% of 1000px screen with 60s total duration
      // (250 / 1000) * 60s = 15s forward -> 30s + 15s = 45s
      final updated = scrubber.update(250.0, 1000.0, const Duration(seconds: 60));
      expect(updated, isTrue);
      expect(scrubber.dragDelta.inSeconds, equals(15));
      expect(scrubber.dragTarget.inSeconds, equals(45));

      // Conclude drag
      final finalTarget = scrubber.end();
      expect(finalTarget.inSeconds, equals(45));
      expect(scrubber.isDragging, isFalse);
      expect(scrubber.dragDelta, equals(Duration.zero));
    });

    test('TC-VFB-03: VideoDragScrubber clamps negative and overflow durations', () {
      final scrubber = VideoDragScrubber();
      scrubber.start(const Duration(seconds: 5));

      // Drag backward past 0
      scrubber.update(-500.0, 1000.0, const Duration(seconds: 60));
      expect(scrubber.dragTarget, equals(Duration.zero));

      // Drag forward past duration
      scrubber.update(2000.0, 1000.0, const Duration(seconds: 60));
      expect(scrubber.dragTarget, equals(const Duration(seconds: 60)));
    });

    test('TC-VFB-04: VideoBufferSyncController tracks mock in-flight bytes and megabytes', () {
      final controller = VideoBufferSyncController();
      controller.setMockInFlightProgress(fractions: {0: 0.5, 1: 0.25}, bytes: 15 * 1024 * 1024);
      controller.setMockCachedChunks({0});

      // 1 cached chunk (19MB) + 15MB in flight = 34MB
      final cachedMb = controller.computeCachedMb(100.0);
      expect(cachedMb, closeTo(34.0, 0.5));

      controller.reset();
      expect(controller.cachedChunks, isEmpty);
      expect(controller.mergedBuffered, isEmpty);
    });

    test('TC-VFB-05: VideoPlayerViewModel exposes isSoftwareDecoding property', () {
      final vm = VideoPlayerViewModel();
      expect(vm.isSoftwareDecoding, isFalse);
      vm.dispose();
    });

    test('TC-VFB-06: VideoPlayerViewModel computes naturalAspectRatio from width and height', () {
      final vm = VideoPlayerViewModel();
      expect(vm.naturalAspectRatio, isNull);

      vm.setMockDimensionsForTesting(1920, 1080);
      expect(vm.naturalAspectRatio, closeTo(16 / 9, 0.01));

      vm.setMockDimensionsForTesting(1080, 1920);
      expect(vm.naturalAspectRatio, closeTo(9 / 16, 0.01));

      vm.dispose();
    });
  });
}
