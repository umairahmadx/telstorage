/*
 * File: download_service_contract.dart
 * Description: Contract defining file downloading and saving pipelines with conflict policy support.
 */

import 'dart:typed_data';
import '../models/download_conflict_policy.dart';
import '../models/file_record.dart';
import 'download_service.dart';

abstract class DownloadServiceContract {
  Future<Uint8List> downloadFile(
    FileRecord record,
    void Function(double progress, String status) onProgress,
  );
  Future<SaveResult> saveAndOpen(
    Uint8List bytes,
    String filename, {
    String? subpath,
    DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
  });
}
