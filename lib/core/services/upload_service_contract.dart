import 'dart:typed_data';

abstract class UploadServiceContract {
  Future<Map<String, dynamic>> uploadFile(
    Uint8List bytes,
    String name,
    String? folderId,
    void Function(double progress, String status) onProgress, {
    bool skipGlobalMetadataUpdate = false,
  });
}
