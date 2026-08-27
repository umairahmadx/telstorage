/*
 * File: transfer_concurrency_coordinator_test.dart
 * Description: Unit tests verifying bounded global concurrency limits across transfer subsystems.
 */

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/transfer_concurrency_coordinator.dart';

void main() {
  setUp(() {
    TransferConcurrencyCoordinator.instance.reset();
  });

  tearDown(() {
    TransferConcurrencyCoordinator.instance.reset();
  });

  group('TransferConcurrencyCoordinator Tests', () {
    test(
        'TC-01: Limits active tasks to maxConcurrent (3) and queues 4th task until slot freed',
        () async {
      final coordinator = TransferConcurrencyCoordinator.instance;
      coordinator.setMaxConcurrentForTesting(3);

      final task1 = Completer<void>();
      final task2 = Completer<void>();
      final task3 = Completer<void>();
      final task4 = Completer<void>();

      bool task4Started = false;

      unawaited(coordinator.runGuarded(() => task1.future));
      unawaited(coordinator.runGuarded(() => task2.future));
      unawaited(coordinator.runGuarded(() => task3.future));
      unawaited(coordinator.runGuarded(() async {
        task4Started = true;
        await task4.future;
      }));

      // Allow microtasks to execute
      await Future.delayed(const Duration(milliseconds: 20));

      expect(coordinator.activeCount, equals(3));
      expect(task4Started, isFalse);

      // Complete task1 -> task4 should immediately start
      task1.complete();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(task4Started, isTrue);
      expect(coordinator.activeCount, equals(3));

      // Clean up
      task2.complete();
      task3.complete();
      task4.complete();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(coordinator.activeCount, equals(0));
    });

    test('TC-02: runGuarded releases slot on error without leaking permits',
        () async {
      final coordinator = TransferConcurrencyCoordinator.instance;
      coordinator.setMaxConcurrentForTesting(1);

      expect(
        () => coordinator.runGuarded(() async {
          throw Exception('Simulated network failure');
        }),
        throwsA(isA<Exception>()),
      );

      await Future.delayed(const Duration(milliseconds: 20));
      expect(coordinator.activeCount, equals(0));

      // Should be able to acquire again immediately
      var executed = false;
      await coordinator.runGuarded(() async {
        executed = true;
      });
      expect(executed, isTrue);
      expect(coordinator.activeCount, equals(0));
    });

    test(
        'TC-03: Unified global cap is respected when upload, download, and zip tasks run concurrently',
        () async {
      final coordinator = TransferConcurrencyCoordinator.instance;
      coordinator.setMaxConcurrentForTesting(2);

      int peakConcurrency = 0;
      int currentConcurrent = 0;

      Future<void> simulateTransfer(String name, int delayMs) async {
        await coordinator.runGuarded(() async {
          currentConcurrent++;
          if (currentConcurrent > peakConcurrency) {
            peakConcurrency = currentConcurrent;
          }
          await Future.delayed(Duration(milliseconds: delayMs));
          currentConcurrent--;
        });
      }

      await Future.wait([
        simulateTransfer('Upload-1', 40),
        simulateTransfer('Download-1', 40),
        simulateTransfer('Zip-1', 40),
        simulateTransfer('Download-2', 40),
      ]);

      expect(peakConcurrency, equals(2));
      expect(coordinator.activeCount, equals(0));
    });
  });
}
