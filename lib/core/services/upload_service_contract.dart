/// File: upload_service_contract.dart
/// Description: Component and logic definition for upload_service_contract.dart in TelStorage.
library;

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
