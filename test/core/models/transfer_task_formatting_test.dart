/*
 * File: transfer_task_formatting_test.dart
 * Description: Unit and widget tests verifying adaptive storage/speed units and dedicated stage display in TransferTask and AppTransferTile.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/tiles/app_transfer_tile.dart';

void main() {
  group('TransferTask Storage Formatting Tests', () {
    test('TC-01: formatStorage formats bytes, KB, MB, and GB adaptively', () {
      // Zero / invalid
      expect(TransferTask.formatStorage(0), equals('0 B'));
      expect(TransferTask.formatStorage(-5), equals('0 B'));
      expect(TransferTask.formatStorage(double.nan), equals('0 B'));

      // Bytes (< 1 KB)
      const bytesMb = 500 / (1024 * 1024);
      expect(TransferTask.formatStorage(bytesMb), equals('500 B'));

      // Kilobytes (< 1 MB)
      const kbMb = 250 / 1024;
      expect(TransferTask.formatStorage(kbMb), equals('250.0 KB'));

      // Megabytes (< 1 GB)
      expect(TransferTask.formatStorage(45.5), equals('45.5 MB'));

      // Gigabytes (>= 1 GB)
      expect(TransferTask.formatStorage(1536), equals('1.50 GB'));
    });

    test('TC-02: formattedTransferredAndTotal adapts units based on total file size', () {
      // Small file: 250 KB total, 50% transferred
      final smallTask = TransferTask(
        id: 'small_1',
        name: 'sample.png',
        type: TransferType.upload,
        sizeMb: 250 / 1024,
        progress: 0.5,
        addedAt: DateTime.now(),
      );
      expect(smallTask.formattedTransferredAndTotal, equals('125.0 / 250.0 KB'));

      // Medium file: 60 MB total, 25% transferred
      final medTask = TransferTask(
        id: 'med_1',
        name: 'clip.mp4',
        type: TransferType.upload,
        sizeMb: 60.0,
        progress: 0.25,
        addedAt: DateTime.now(),
      );
      expect(medTask.formattedTransferredAndTotal, equals('15.0 / 60.0 MB'));

      // Large file: 2048 MB (2 GB) total, 50% transferred
      final largeTask = TransferTask(
        id: 'large_1',
        name: 'huge.iso',
        type: TransferType.upload,
        sizeMb: 2048.0,
        progress: 0.5,
        addedAt: DateTime.now(),
      );
      expect(largeTask.formattedTransferredAndTotal, equals('1.00 / 2.00 GB'));
    });
  });

  group('TransferTask Speed Formatting Tests', () {
    test('TC-03: formatSpeed formats B/s, KB/s, and MB/s adaptively', () {
      expect(TransferTask.formatSpeed(0), equals(''));
      expect(TransferTask.formatSpeed(-10), equals(''));
      expect(TransferTask.formatSpeed(double.nan), equals(''));

      // B/s (< 1 KB/s)
      expect(TransferTask.formatSpeed(0.5), equals('512 B/s'));

      // KB/s (< 1024 KB/s)
      expect(TransferTask.formatSpeed(350), equals('350 KB/s'));
      expect(TransferTask.formatSpeed(8.4), equals('8.4 KB/s'));

      // MB/s (>= 1024 KB/s)
      expect(TransferTask.formatSpeed(2048), equals('2.0 MB/s'));
      expect(TransferTask.formatSpeed(5120), equals('5.0 MB/s'));
    });
  });

  group('TransferTask Progress Formatting Tests', () {
    test('TC-03b: formattedProgress formats percentages with 1 decimal place', () {
      final task0 = TransferTask(
        id: 't0',
        name: 'test.bin',
        type: TransferType.upload,
        sizeMb: 10,
        progress: 0.0,
        addedAt: DateTime.now(),
      );
      expect(task0.formattedProgress, equals('0.0%'));

      final task452 = TransferTask(
        id: 't1',
        name: 'test.bin',
        type: TransferType.upload,
        sizeMb: 10,
        progress: 0.4523,
        addedAt: DateTime.now(),
      );
      expect(task452.formattedProgress, equals('45.2%'));

      final task100 = TransferTask(
        id: 't2',
        name: 'test.bin',
        type: TransferType.upload,
        sizeMb: 10,
        progress: 1.0,
        addedAt: DateTime.now(),
      );
      expect(task100.formattedProgress, equals('100.0%'));

      final taskClampLow = TransferTask(
        id: 't3',
        name: 'test.bin',
        type: TransferType.upload,
        sizeMb: 10,
        progress: -0.1,
        addedAt: DateTime.now(),
      );
      expect(taskClampLow.formattedProgress, equals('0.0%'));

      final taskClampHigh = TransferTask(
        id: 't4',
        name: 'test.bin',
        type: TransferType.upload,
        sizeMb: 10,
        progress: 1.25,
        addedAt: DateTime.now(),
      );
      expect(taskClampHigh.formattedProgress, equals('100.0%'));
    });
  });

  group('AppTransferTile Widget Layout Tests', () {
    testWidgets(
        'TC-04: Displays dedicated stage line without truncation and adaptive units when uploading',
        (tester) async {
      final task = TransferTask(
        id: 'task_widget_1',
        name: 'my_video.mp4',
        type: TransferType.upload,
        sizeMb: 250 / 1024, // 250 KB
        progress: 0.45,
        speedKbps: 320,
        status: TransferStatus.uploading,
        currentStage: 'Uploading part 1 of 2',
        addedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AppTransferTile(
              task: task,
              onPause: () {},
              onResume: () {},
              onCancel: () {},
            ),
          ),
        ),
      );

      // Verify file name is shown
      expect(find.text('my_video.mp4'), findsOneWidget);

      // Verify dedicated stage line is shown with full task description
      expect(find.text('Uploading part 1 of 2'), findsOneWidget);

      // Verify metrics line displays KB and KB/s with 1 decimal place percentage
      expect(find.text('45.0% • 112.5 / 250.0 KB • 320 KB/s'), findsOneWidget);

      // Verify stage text has maxLines 2
      final stageTextWidget =
          tester.widget<Text>(find.text('Uploading part 1 of 2'));
      expect(stageTextWidget.maxLines, equals(2));
    });

    testWidgets(
        'TC-05: Displays waiting stage and adaptive size when pending',
        (tester) async {
      final task = TransferTask(
        id: 'task_widget_2',
        name: 'document.pdf',
        type: TransferType.download,
        sizeMb: 450 / 1024, // 450 KB
        status: TransferStatus.pending,
        currentStage: 'Waiting in queue…',
        addedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AppTransferTile(
              task: task,
              onPause: () {},
              onResume: () {},
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('document.pdf'), findsOneWidget);
      expect(find.text('Waiting in queue…'), findsOneWidget);
      expect(find.text('450.0 KB'), findsOneWidget);
    });
  });
}
