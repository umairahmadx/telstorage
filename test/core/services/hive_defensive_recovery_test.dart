/*
 * File: hive_defensive_recovery_test.dart
 * Description: Unit tests validating defensive Hive startup recovery, corrupt box recreation, and pending_actions quarantine preservation.
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/events/domain_event_bus.dart';
import 'package:telstorage/core/services/hive_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_defensive_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Hive Defensive Startup & Quarantine Recovery Tests', () {
    test(
        'TC-01: Standard unshielded Hive.openBox on corrupted file with crashRecovery=false throws uncaught HiveError',
        () async {
      const boxName = 'corrupted_unshielded';
      final boxFile = File('${tempDir.path}/$boxName.hive');
      await boxFile.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22]);

      dynamic capturedError;
      await runZonedGuarded(() async {
        try {
          await Hive.openBox<dynamic>(boxName, crashRecovery: false);
        } catch (e) {
          capturedError = e;
        }
      }, (error, stack) {
        capturedError = error;
      });

      expect(capturedError, isA<HiveError>());
    });

    test(
        'TC-02: openBoxDefensively with preserveQuarantine=true preserves corrupted file and opens clean box',
        () async {
      const boxName = 'pending_actions_corrupt';
      final boxFile = File('${tempDir.path}/$boxName.hive');
      await boxFile.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF, 0x99, 0x88, 0x77]);

      CriticalBoxCorruptedEvent? capturedEvent;
      final sub =
          DomainEventBus.instance.on<CriticalBoxCorruptedEvent>().listen((e) {
        capturedEvent = e;
      });

      final box = await HiveService.openBoxDefensively<dynamic>(
        boxName,
        preserveQuarantine: true,
        directory: tempDir.path,
      );

      expect(box, isNotNull);
      expect(box.isOpen, isTrue);
      expect(box.isEmpty, isTrue);

      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(capturedEvent, isNotNull);
      expect(capturedEvent?.boxName, equals(boxName));

      // Verify that a quarantined backup file exists on disk
      final quarantinedFiles = tempDir
          .listSync()
          .where((f) => f.path.contains('$boxName.hive.corrupted_'))
          .toList();
      expect(quarantinedFiles, isNotEmpty,
          reason: 'Corrupt pending_actions must be quarantined to disk');
    });

    test(
        'TC-03: openBoxDefensively with preserveQuarantine=false resets corrupt cache and opens clean box',
        () async {
      const boxName = 'files_cache_corrupt';
      final boxFile = File('${tempDir.path}/$boxName.hive');
      await boxFile.writeAsBytes([0xCA, 0xFE, 0xBA, 0xBE, 0x12, 0x34, 0x56]);

      PartitionCacheCorruptedEvent? capturedEvent;
      final sub = DomainEventBus.instance
          .on<PartitionCacheCorruptedEvent>()
          .listen((e) {
        capturedEvent = e;
      });

      final box = await HiveService.openBoxDefensively<dynamic>(
        boxName,
        preserveQuarantine: false,
        directory: tempDir.path,
      );

      expect(box, isNotNull);
      expect(box.isOpen, isTrue);
      expect(box.isEmpty, isTrue);

      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(capturedEvent, isNotNull);
      expect(capturedEvent?.boxName, equals(boxName));
    });
  });
}
