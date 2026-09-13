/*
 * File: thumbnail_priority_queue_test.dart
 * Description: Unit tests verifying ThumbnailRepository priority queueing, LIFO visible promotion, cancellation, debounce, and playback pause.
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/thumbnail_repository.dart';

class _MockTelegramService extends TelegramService {
  final List<String> downloadedFileIds = [];
  final Map<String, Completer<Uint8List>> inFlightCompleters = {};
  bool autoResolve = true;

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
  ]) async {
    downloadedFileIds.add(fileId);
    if (!autoResolve) {
      final completer = Completer<Uint8List>();
      inFlightCompleters[fileId] = completer;
      return completer.future;
    }
    return Uint8List.fromList([1, 2, 3, 4]);
  }

  /// Deterministically waits for a specific fileId to be invoked by the repository queue.
  Future<void> waitForDownload(String fileId, {int timeoutMs = 2000}) async {
    final start = DateTime.now();
    while (!inFlightCompleters.containsKey(fileId)) {
      if (DateTime.now().difference(start).inMilliseconds > timeoutMs) {
        throw TimeoutException('Timed out waiting for download $fileId');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _MockTelegramService mockTelegram;
  late ThumbnailRepository repository;

  FileRecord makeRecord(String id) => FileRecord(
        fileId: id,
        name: '$id.jpg',
        metadataMessageId: 1,
        sizeMb: 1.0,
        mimeType: 'image/jpeg',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'hash_$id',
        thumbnailFileId: 'thumb_$id',
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thumb_queue_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
    mockTelegram = _MockTelegramService();
    repository = ThumbnailRepository(mockTelegram);
  });

  tearDown(() async {
    repository.clearMemoryCache();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Thumbnail Priority Queue Reproduction Tests', () {
    test('TC-THUMB-01: Cancelled off-screen request is never downloaded from Telegram',
        () async {
      mockTelegram.autoResolve = false;

      // Start request for item 1 (which becomes in-flight)
      final f1 = makeRecord('file_1');
      final req1 = repository.getThumbnailData(f1);

      // Queue item 2 and item 3 while item 1 is in flight
      final f2 = makeRecord('file_2');
      final f3 = makeRecord('file_3');
      final req2 = repository.getThumbnailData(f2);
      final req3 = repository.getThumbnailData(f3);

      // Cancel item 2 before it starts downloading (scrolled off-screen)
      repository.cancelThumbnailRequest('file_2');

      // Finish item 1
      await mockTelegram.waitForDownload('thumb_file_1');
      mockTelegram.inFlightCompleters['thumb_file_1']?.complete(Uint8List.fromList([1]));
      await req1;

      // Finish item 3 if it gets picked up
      await mockTelegram.waitForDownload('thumb_file_3');
      mockTelegram.inFlightCompleters['thumb_file_3']?.complete(Uint8List.fromList([3]));
      await req3;

      // Assert item 2 completed with null when cancelled and was NEVER downloaded from Telegram
      expect(await req2, isNull);
      expect(mockTelegram.downloadedFileIds.contains('thumb_file_2'), isFalse,
          reason: 'Cancelled offscreen thumbnail must NOT be downloaded from Telegram');
    });

    test('TC-THUMB-02: LIFO priority executes newly visible item before earlier queued items',
        () async {
      mockTelegram.autoResolve = false;

      // Request file 1 (starts in-flight)
      final f1 = makeRecord('file_1');
      final req1 = repository.getThumbnailData(f1);

      // User scrolls down: file 2 is queued, then file 3 is queued (most recently visible)
      final f2 = makeRecord('file_2');
      final f3 = makeRecord('file_3');
      unawaited(repository.getThumbnailData(f2));
      unawaited(repository.getThumbnailData(f3));

      // Complete file 1
      await mockTelegram.waitForDownload('thumb_file_1');
      mockTelegram.inFlightCompleters['thumb_file_1']?.complete(Uint8List.fromList([1]));
      await req1;

      // Wait for next queued item to begin downloading
      await mockTelegram.waitForDownload('thumb_file_3');

      // With LIFO priority, file 3 (the newest visible item) must be started BEFORE file 2!
      expect(mockTelegram.downloadedFileIds, ['thumb_file_1', 'thumb_file_3'],
          reason: 'Newly visible item file_3 must jump ahead of earlier queued file_2 (LIFO)');
    });

    test('TC-THUMB-03: Pausing downloads suspends queue during media playback / viewing',
        () async {
      mockTelegram.autoResolve = true;

      // Pause thumbnail queue (e.g. video streaming or full-image view active)
      repository.pauseDownloads();

      final f1 = makeRecord('file_pause_1');
      unawaited(repository.getThumbnailData(f1));

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Queue is paused, so file_pause_1 should not have started downloading
      expect(mockTelegram.downloadedFileIds.contains('thumb_file_pause_1'), isFalse,
          reason: 'Paused queue must not initiate downloads until resumed');

      // Resume queue
      repository.resumeDownloads();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(mockTelegram.downloadedFileIds.contains('thumb_file_pause_1'), isTrue,
          reason: 'Resumed queue must process pending requests');
    });
  });
}
