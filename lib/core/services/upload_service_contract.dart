/*
 * File: upload_service_contract.dart
 * Description: Component and logic definition for upload_service_contract.dart in TelStorage.
 */

import 'dart:typed_data';
import '../errors/result.dart';

abstract class UploadServiceContract {
  Future<Result<Map<String, dynamic>>> uploadFile(
    Uint8List bytes,
    String name,
    String? folderId,
    void Function(double progress, String status) onProgress, {
    bool skipGlobalMetadataUpdate = false,
    String? taskId,
    String? precomputedHash,
    Uint8List? precomputedThumbnailBytes,
    String? thumbnailExtension,
  });
}
