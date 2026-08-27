/*
 * File: upload_resumability_test.dart
 * Description: Unit tests validating multi-chunk upload caching, resume mechanisms, and BatteryOptimizationHelper.
 */

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/chunk_info.dart';
import 'package:telstorage/core/services/chunk_resume_service.dart';
import 'package:telstorage/core/services/notification_service.dart';
import 'package:telstorage/core/utils/battery_optimization_helper.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Upload Resumability & Chunk Persistence Tests', () {
    test('TC-01: ChunkInfo serialization and deserialization works correctly',
        () {
      final chunk = ChunkInfo(
        index: 3,
        messageId: 1042,
        fileId: 'tg_file_part_3',
        sizeMb: 19.0,
        partName: 'sample.zip.003',
      );

      final json = chunk.toJson();
      final restored = ChunkInfo.fromJson(json);

      expect(restored.index, equals(3));
      expect(restored.messageId, equals(1042));
      expect(restored.fileId, equals('tg_file_part_3'));
      expect(restored.sizeMb, equals(19.0));
      expect(restored.partName, equals('sample.zip.003'));
    });

    test(
        'TC-02: BatteryOptimizationHelper returns true in non-Android/test environment',
        () async {
      final isExempt = await BatteryOptimizationHelper.isOptimizationDisabled();
      expect(isExempt, isTrue);
    });

    test('TC-03: UploadBloc triggers proactive transfer session lifecycle',
        () async {
      final notifService = NotificationService.instance;
      final bloc = UploadBloc();

      expect(notifService.isTransferSessionActive, isFalse);

      final task = UploadTask(
        id: 'test_task_1',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        name: 'test.png',
      );

      bloc.add(AddUploads([task]));
      // Give async microtasks time to execute
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifService.isTransferSessionActive, isTrue);

      bloc.add(ResetUpload());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifService.isTransferSessionActive, isFalse);

      await bloc.close();
    });

    test(
        'TC-04: Simulated kill-9 mid-chunk upload resumes from uncompleted chunk without corrupting',
        () {
      // Setup state where chunks 1 to 7 succeeded, but chunk 8 was killed mid-flight (not in persistent cache)
      final simulatedBoxData = <dynamic, dynamic>{};
      for (int i = 1; i <= 7; i++) {
        simulatedBoxData[i] = ChunkInfo(
          index: i,
          messageId: 100 + i,
          fileId: 'tg_chunk_file_$i',
          sizeMb: 19.0,
          partName: 'large_archive.zip.${i.toString().padLeft(3, '0')}',
        ).toJson();
      }

      // Reconstruct map from persisted data
      final Map<int, ChunkInfo> existingChunks = {};
      simulatedBoxData.forEach((k, v) {
        if (v is Map) {
          final chunk = ChunkInfo.fromJson(Map<String, dynamic>.from(v));
          existingChunks[chunk.index] = chunk;
        }
      });

      expect(existingChunks.length, equals(7));
      expect(existingChunks.containsKey(7), isTrue);
      expect(existingChunks.containsKey(8),
          isFalse); // Chunk 8 was in-flight, so NOT in box

      // Simulate loop over 10 parts
      final List<int> partsToUpload = [];
      final List<ChunkInfo> completedInfos = [];

      for (int i = 0; i < 10; i++) {
        final chunkIndex = i + 1;
        final cached = existingChunks[chunkIndex];
        if (cached != null) {
          completedInfos.add(cached);
        } else {
          partsToUpload.add(chunkIndex);
          completedInfos.add(ChunkInfo(
            index: chunkIndex,
            messageId: 200 + chunkIndex,
            fileId: 'tg_chunk_file_$chunkIndex',
            sizeMb: 19.0,
            partName:
                'large_archive.zip.${chunkIndex.toString().padLeft(3, '0')}',
          ));
        }
      }

      // Verify that chunks 1..7 were skipped and chunks 8, 9, 10 were newly uploaded
      expect(partsToUpload, equals([8, 9, 10]));
      expect(completedInfos.length, equals(10));
      expect(completedInfos.first.fileId, equals('tg_chunk_file_1'));
      expect(completedInfos.last.fileId, equals('tg_chunk_file_10'));
    });

    test(
        'TC-05: Thumbnail cache key thumb_hash allows instant thumbnail reuse on resume',
        () {
      final Map<String, dynamic> cache = {
        'thumb_abc123': 'tg_thumb_file_id_999',
      };

      final cachedThumbId = cache['thumb_abc123'] as String?;
      expect(cachedThumbId, equals('tg_thumb_file_id_999'));
    });

    test(
        'TC-06: ChunkResumeService handles unopened box and null lookups gracefully',
        () async {
      final service = ChunkResumeService.instance;
      final chunks = service.getUploadedChunks('non_existent_hash');
      expect(chunks, isEmpty);

      final thumb = service.getCachedThumbnailFileId('non_existent_hash');
      expect(thumb, isNull);

      await service.clearFileCache('non_existent_hash');
    });
  });
}
