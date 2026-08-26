/*
 * File: download_job.dart
 * Description: Component and logic definition for download_job.dart in TelStorage.
 */

import 'package:hive/hive.dart';

part 'download_job.g.dart';

@HiveType(typeId: 2)
class DownloadJob extends HiveObject {
  @HiveField(0)
  final String fileId;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String mimeType;

  @HiveField(3)
  final double sizeMb;

  @HiveField(4)
  double progress; // 0.0 to 1.0

  @HiveField(5)
  String status; // 'queued', 'downloading', 'completed', 'failed', 'cancelled'

  @HiveField(6)
  String? localPath;

  @HiveField(7)
  String? error;

  @HiveField(8)
  final DateTime addedAt;

  @HiveField(9)
  DateTime? completedAt;

  @HiveField(10)
  final String? subpath;

  DownloadJob({
    required this.fileId,
    required this.name,
    required this.mimeType,
    required this.sizeMb,
    this.progress = 0.0,
    this.status = 'queued',
    this.localPath,
    this.error,
    required this.addedAt,
    this.completedAt,
    this.subpath,
  });

  bool get isComplete => status == 'completed';
  bool get isDownloading => status == 'downloading';
  bool get isQueued => status == 'queued';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
}
