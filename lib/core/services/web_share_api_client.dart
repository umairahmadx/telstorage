/*
 * File: web_share_api_client.dart
 * Description: Component and logic definition for web_share_api_client.dart in TelStorage.
 */

import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'transfer_queue_service.dart';

class WebShareApiClient {
  static const _r2MinimumTransferTimeout = Duration(minutes: 5);
  static const _r2MaximumTransferTimeout = Duration(minutes: 45);
  static const _assumedMinimumUploadSpeedBytesPerSecond = 64 * 1024;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://storage.to/api',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Duration _r2TransferTimeout(int byteLength) {
    final estimatedSeconds =
        (byteLength / _assumedMinimumUploadSpeedBytesPerSecond).ceil();
    final bufferedSeconds = estimatedSeconds * 2;
    final timeoutSeconds =
        _r2MinimumTransferTimeout.inSeconds + bufferedSeconds;

    return Duration(
      seconds: timeoutSeconds
          .clamp(
            _r2MinimumTransferTimeout.inSeconds,
            _r2MaximumTransferTimeout.inSeconds,
          )
          .toInt(),
    );
  }

  Future<String> getOrCreateVisitorToken() async {
    const storage = FlutterSecureStorage();
    String? token = await storage.read(key: 'visitor_token');
    if (token == null) {
      token =
          'visitor_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
      await storage.write(key: 'visitor_token', value: token);
    }
    return token;
  }

  Future<Map<String, dynamic>> uploadToStorageTo({
    required Uint8List bytes,
    required String transferId,
    required String filename,
    required String mimeType,
    required String visitorToken,
    required void Function(double pct) onProgress,
  }) async {
    if (TransferQueueService.instance.isCancelled(transferId)) {
      throw Exception('Share cancelled by user');
    }

    final initRes = await _dio.post(
      '/upload/init',
      data: {
        'filename': filename,
        'content_type': mimeType,
        'size': bytes.length,
      },
      options: Options(
        headers: {
          'X-Visitor-Token': visitorToken,
          'Content-Type': 'application/json',
        },
      ),
    );

    if (initRes.data['success'] != true) {
      throw Exception(initRes.data['error'] ?? 'Upload initialization failed');
    }

    final type = initRes.data['type'] as String? ?? 'single';
    final r2Key = initRes.data['r2_key'] as String;
    String finalOwnerToken = initRes.data['owner_token'] as String? ?? '';

    if (type == 'single') {
      final uploadUrl = initRes.data['upload_url'] as String;
      await _dio.put(
        uploadUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(
          sendTimeout: _r2TransferTimeout(bytes.length),
          receiveTimeout: _r2TransferTimeout(bytes.length),
          headers: {
            Headers.contentLengthHeader: bytes.length,
            Headers.contentTypeHeader: mimeType,
          },
        ),
        onSendProgress: (sent, total) {
          final pct = total > 0 ? sent / total : 0.0;
          onProgress(pct);
        },
      );
    } else {
      final uploadId = initRes.data['upload_id'] as String;
      final partSize = initRes.data['part_size'] as int;
      final totalParts = initRes.data['total_parts'] as int;
      final initialUrls = initRes.data['initial_urls'] as Map<String, dynamic>;

      final List<Map<String, dynamic>> completedParts = [];

      for (var i = 0; i < totalParts; i++) {
        while (TransferQueueService.instance.isPaused(transferId)) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (TransferQueueService.instance.isCancelled(transferId)) {
          throw Exception('Share cancelled by user');
        }
        final partNumber = i + 1;
        final start = i * partSize;
        final end = (start + partSize).clamp(0, bytes.length);
        final partBytes = bytes.sublist(start, end);

        String partUrl = initialUrls[partNumber.toString()] as String? ?? '';
        if (partUrl.isEmpty) {
          final partUrlRes = await _dio.post(
            '/upload/parts',
            data: {
              'upload_id': uploadId,
              'part_numbers': [partNumber]
            },
            options:
                Options(headers: {'Authorization': 'Owner $finalOwnerToken'}),
          );
          if (partUrlRes.data['success'] == true) {
            final partUrls = partUrlRes.data['part_urls'] as List;
            if (partUrls.isNotEmpty) partUrl = partUrls.first['url'] as String;
          }
        }

        if (partUrl.isEmpty) throw Exception('Failed to get part URL');

        final res = await _dio.put(
          partUrl,
          data: Stream.fromIterable([partBytes]),
          options: Options(
            sendTimeout: _r2TransferTimeout(partBytes.length),
            receiveTimeout: _r2TransferTimeout(partBytes.length),
            headers: {
              Headers.contentLengthHeader: partBytes.length,
              Headers.contentTypeHeader: mimeType,
            },
          ),
          onSendProgress: (sent, total) {
            final partPct = total > 0 ? sent / total : 0.0;
            onProgress((i + partPct) / totalParts);
          },
        );

        final etag =
            res.headers.value('etag') ?? res.headers.value('ETag') ?? '';
        if (etag.isEmpty) throw Exception('No ETag');
        completedParts.add({'partNumber': partNumber, 'etag': etag});
      }

      await _dio.post(
        '/upload/complete-multipart',
        data: {'upload_id': uploadId, 'parts': completedParts},
        options: Options(headers: {
          'Authorization': 'Owner $finalOwnerToken',
          'Content-Type': 'application/json'
        }),
      );
    }

    final confirmRes = await _dio.post(
      '/upload/confirm',
      data: {
        'filename': filename,
        'size': bytes.length,
        'content_type': mimeType,
        'r2_key': r2Key,
      },
      options: Options(headers: {
        'X-Visitor-Token': visitorToken,
        'Content-Type': 'application/json'
      }),
    );

    if (confirmRes.data['success'] != true) {
      throw Exception('Confirmation failed');
    }

    final fileData = confirmRes.data['file'] as Map<String, dynamic>;
    return {
      'id': fileData['id'] as String,
      'share_url': fileData['url'] as String,
      'owner_token': confirmRes.data['owner_token'] as String,
    };
  }

  Future<void> deleteShareRemote(String storageToId, String ownerToken) async {
    await _dio.delete(
      '/file/$storageToId',
      options: Options(headers: {'Authorization': 'Owner $ownerToken'}),
    );
  }

  Future<bool> setPasswordRemote(
      String storageToId, String ownerToken, String password) async {
    final res = await _dio.post(
      '/file/$storageToId/password',
      data: {'password': password},
      options: Options(headers: {
        'Authorization': 'Owner $ownerToken',
        'Content-Type': 'application/json'
      }),
    );
    return res.data['success'] == true;
  }

  Future<bool> setExpiryRemote(
      String storageToId, String ownerToken, int days) async {
    final res = await _dio.post(
      '/file/$storageToId/expiry',
      data: {'days': days},
      options: Options(headers: {
        'Authorization': 'Owner $ownerToken',
        'Content-Type': 'application/json'
      }),
    );
    return res.data['success'] == true;
  }

  Future<bool> setMaxDownloadsRemote(
      String storageToId, String ownerToken, int? maxDownloads) async {
    final res = await _dio.post(
      '/file/$storageToId/max-downloads',
      data: {'max_downloads': maxDownloads},
      options: Options(headers: {
        'Authorization': 'Owner $ownerToken',
        'Content-Type': 'application/json'
      }),
    );
    return res.data['success'] == true;
  }

  Future<bool> setVanitySlugRemote(
      String storageToId, String ownerToken, String vanitySlug) async {
    final res = await _dio.post(
      '/file/$storageToId/alias',
      data: {'alias': vanitySlug},
      options: Options(headers: {
        'Authorization': 'Owner $ownerToken',
        'Content-Type': 'application/json'
      }),
    );
    return res.data['success'] == true;
  }

  Future<void> uploadThumbnailRemote(
      String storageToId, String ownerToken, Uint8List imageBytes) async {
    final formData = FormData.fromMap({
      'thumbnail': MultipartFile.fromBytes(imageBytes, filename: 'thumb.jpg'),
    });

    final res = await _dio.post(
      '/file/$storageToId/thumbnail',
      data: formData,
      options: Options(headers: {
        'Authorization': 'Owner $ownerToken',
        'Content-Type': 'multipart/form-data',
      }),
    );

    if (res.data['success'] != true) {
      throw Exception(res.data['error'] ?? 'Thumbnail upload failed');
    }
  }

  Future<Map<String, dynamic>> getBandwidthStatusRemote(
      String visitorToken) async {
    final res = await _dio.get(
      '/bandwidth/status',
      options: Options(headers: {'X-Visitor-Token': visitorToken}),
    );
    return res.data as Map<String, dynamic>;
  }

  Future<bool> isFilePendingRemote(String storageToId) async {
    final res = await _dio.get('/file/$storageToId/status');
    return res.data['pending'] as bool? ?? false;
  }
}
