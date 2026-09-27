/*
 * File: in_flight_chunk_registry_test.dart
 * Description: Unit tests verifying in-flight download deduplication, broadcast streaming, and task completion lifecycles.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/in_flight_chunk_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InFlightChunkRegistry registry;

  setUp(() {
    registry = InFlightChunkRegistry.instance;
    registry.clearForTesting();
  });

  tearDown(() {
    registry.cancelAll();
    registry.clearForTesting();
  });

  group('InFlightChunkRegistry Unit Tests', () {
    test('TC-IFR-01: register returns same task for concurrent requests of identical chunk', () {
      final task1 = registry.register('video_123', 0);
      final task2 = registry.register('video_123', 0);

      expect(identical(task1, task2), isTrue);
      expect(task1.fileId, equals('video_123'));
      expect(task1.chunkIndex, equals(0));
      expect(task1.isFinished, isFalse);
    });

    test('TC-IFR-02: distinct chunks receive separate in-flight tasks', () {
      final taskChunk0 = registry.register('video_123', 0);
      final taskChunk1 = registry.register('video_123', 1);

      expect(identical(taskChunk0, taskChunk1), isFalse);
      expect(registry.get('video_123', 0), equals(taskChunk0));
      expect(registry.get('video_123', 1), equals(taskChunk1));
    });

    test('TC-IFR-03: packetStream broadcasts packets to multiple subscribers simultaneously', () async {
      final task = registry.register('video_stream', 0);

      final subscriber1Packets = <List<int>>[];
      final subscriber2Packets = <List<int>>[];

      final sub1 = task.packetStream.listen(subscriber1Packets.add);
      final sub2 = task.packetStream.listen(subscriber2Packets.add);

      task.addPacket([1, 2, 3]);
      task.addPacket([4, 5]);

      await Future.delayed(Duration.zero);

      expect(subscriber1Packets, equals([[1, 2, 3], [4, 5]]));
      expect(subscriber2Packets, equals([[1, 2, 3], [4, 5]]));
      expect(task.bytesReceived, equals(5));

      await sub1.cancel();
      await sub2.cancel();
    });

    test('TC-IFR-04: completion resolves completionFuture and unregisters task', () async {
      final task = registry.register('video_done', 2);
      final mockFile = File('mock_chunk_2.part');

      expect(registry.get('video_done', 2), isNotNull);

      task.complete(mockFile);

      final result = await task.completionFuture;
      expect(result, equals(mockFile));
      expect(task.isFinished, isTrue);

      // Once finished, get() drops it from registry
      expect(registry.get('video_done', 2), isNull);
    });

    test('TC-IFR-05: cancelForFile aborts in-flight tasks matching fileId', () async {
      final task1 = registry.register('file_a', 0);
      final task2 = registry.register('file_a', 1);
      final taskB = registry.register('file_b', 0);

      registry.cancelForFile('file_a');

      expect(task1.cancelToken.isCancelled, isTrue);
      expect(task2.cancelToken.isCancelled, isTrue);
      expect(taskB.cancelToken.isCancelled, isFalse);

      expect(registry.get('file_a', 0), isNull);
      expect(registry.get('file_b', 0), equals(taskB));
    });

    test('TC-IFR-06: cancelAll aborts all registered in-flight tasks across files', () {
      final task1 = registry.register('file_1', 0);
      final task2 = registry.register('file_2', 0);

      registry.cancelAll();

      expect(task1.cancelToken.isCancelled, isTrue);
      expect(task2.cancelToken.isCancelled, isTrue);
      expect(registry.get('file_1', 0), isNull);
      expect(registry.get('file_2', 0), isNull);
    });
  });
}
