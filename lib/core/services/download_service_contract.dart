import 'dart:typed_data';
import '../models/file_record.dart';
import 'download_service.dart';

abstract class DownloadServiceContract {
  Future<Uint8List> downloadFile(
    FileRecord record,
    void Function(double progress, String status) onProgress,
  );
  Future<SaveResult> saveAndOpen(Uint8List bytes, String filename);
  Future<void> saveFile(Uint8List bytes, String filename);
}
