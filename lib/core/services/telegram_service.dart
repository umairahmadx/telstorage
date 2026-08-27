/*
 * File: telegram_service.dart
 * Description: Low-level Telegram Bot API client managing authenticated uploads, downloads, pins, and rate-limited requests.
 */

import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../constants/app_constants.dart';
import '../events/domain_event_bus.dart';
import '../utils/app_logger.dart';
import 'telegram_rate_limiter.dart';

/// Exception thrown when Telegram returns HTTP 401 Unauthorized (token revoked/invalid).
class TelegramAuthException implements Exception {
  final String message;
  TelegramAuthException(
      [this.message =
          'Telegram bot token is invalid or has been revoked (HTTP 401).']);

  @override
  String toString() => 'TelegramAuthException: $message';
}

/// All raw Telegram Bot API calls with media extraction and proxy support.
class TelegramService {
  late final String _token;
  late final String _channelId;
  final Dio _dio;

  TelegramService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 120),
                receiveTimeout: const Duration(seconds: 60),
              ),
            );

  String get _base => '${AppConstants.telegramApiBase}$_token';
  String get _fileBase => '${AppConstants.telegramFileBase}$_token';

  /// Initializes bot token and destination channel ID.
  Future<void> init(String token, String channelId) async {
    _token = token;
    _channelId = channelId;
  }

  /// Helper executing API actions with automatic 3-attempt exponential retry on network/transient failures.
  Future<T> _withRetry<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
    String operationName = 'Telegram operation',
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await action();
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          AppLogger.e(
            'Telegram bot token invalid/revoked (HTTP 401). Failing fast.',
            tag: 'TelegramService',
          );
          DomainEventBus.instance.fire(AuthTokenRevokedEvent());
          throw TelegramAuthException();
        }

        if (e.response?.statusCode == 429) {
          final retryAfter =
              e.response?.data?['parameters']?['retry_after'] as int? ?? 5;
          TelegramRateLimiter.instance.report429(retryAfter);
          if (attempt < maxAttempts) {
            await Future.delayed(Duration(seconds: retryAfter));
            continue;
          }
        }

        final isTransient = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            (e.response?.statusCode != null &&
                e.response!.statusCode! >= 500 &&
                e.response!.statusCode! <= 504);

        if (isTransient && attempt < maxAttempts) {
          final delayMs = 1000 * (1 << (attempt - 1));
          AppLogger.w(
            '$operationName transient network error (attempt $attempt/$maxAttempts): $e. Retrying in ${delayMs}ms...',
            tag: 'TelegramService',
          );
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        rethrow;
      } catch (e) {
        if (attempt < maxAttempts) {
          final delayMs = 1000 * (1 << (attempt - 1));
          AppLogger.w(
            '$operationName error (attempt $attempt/$maxAttempts): $e. Retrying in ${delayMs}ms...',
            tag: 'TelegramService',
          );
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        rethrow;
      }
    }
  }

  /// Upload a file (chunk or metadata json) → returns message_id and file_id
  Future<Map<String, dynamic>> uploadBytesWithFileId(
      Uint8List bytes, String filename) async {
    return _withRetry(() async {
      await TelegramRateLimiter.instance.acquire();
      try {
        AppLogger.d('Uploading: $filename (${bytes.length} bytes)',
            tag: 'TelegramService');

        final formData = FormData.fromMap({
          'chat_id': _channelId,
          'document': MultipartFile.fromBytes(bytes, filename: filename),
        });

        final res = await _dio.post('$_base/sendDocument', data: formData);

        if (res.data['ok'] != true) {
          throw Exception('Upload failed: ${res.data['description']}');
        }

        final result = res.data['result'];
        final messageId = result['message_id'] as int;

        // Extract file_id across all possible Telegram media response types
        String? fileId;
        if (result['document'] != null) {
          fileId = result['document']['file_id'] as String;
        } else if (result['photo'] != null &&
            result['photo'] is List &&
            (result['photo'] as List).isNotEmpty) {
          fileId = (result['photo'] as List).last['file_id'] as String;
        } else if (result['video'] != null) {
          fileId = result['video']['file_id'] as String;
        } else if (result['audio'] != null) {
          fileId = result['audio']['file_id'] as String;
        } else if (result['sticker'] != null) {
          fileId = result['sticker']['file_id'] as String;
        } else if (result['animation'] != null) {
          fileId = result['animation']['file_id'] as String;
        } else if (result['voice'] != null) {
          fileId = result['voice']['file_id'] as String;
        } else if (result['video_note'] != null) {
          fileId = result['video_note']['file_id'] as String;
        }

        if (fileId == null) {
          AppLogger.e('No file_id found in result: $result',
              tag: 'TelegramService');
          throw Exception('Telegram response missing file_id');
        }

        AppLogger.d(
            'Uploaded successfully, message_id: $messageId, file_id: $fileId',
            tag: 'TelegramService');
        return {
          'message_id': messageId,
          'file_id': fileId,
        };
      } on DioException {
        rethrow;
      } catch (e) {
        AppLogger.e('Upload failed: $e', tag: 'TelegramService', error: e);
        throw Exception('Failed to upload file: $e');
      }
    }, operationName: 'uploadBytesWithFileId($filename)');
  }

  /// Download file bytes by file_id with Web proxy fallback
  Future<Uint8List> downloadByFileId(String fileId) async {
    return _withRetry(() async {
      await TelegramRateLimiter.instance.acquire();
      try {
        AppLogger.d('Downloading file with file_id: $fileId',
            tag: 'TelegramService');

        final workerUrl =
            (dotenv.isInitialized ? dotenv.env['WORKER_URL'] : null) ??
                'https://telstorage-proxy.umair-ahmed-64422.workers.dev';

        // Step 1: Get file path using file_id
        AppLogger.d('Getting file path...', tag: 'TelegramService');
        final getFileEndpoint = '$_base/getFile';
        final requestGetFileUrl = kIsWeb
            ? '$workerUrl?url=${Uri.encodeComponent('$getFileEndpoint?file_id=$fileId')}'
            : getFileEndpoint;

        final filePathRes = await _dio.get(
          requestGetFileUrl,
          queryParameters: kIsWeb ? null : {'file_id': fileId},
        );

        final filePath = filePathRes.data['result']['file_path'] as String;
        AppLogger.d('Got file path: $filePath', tag: 'TelegramService');

        // Step 2: Download the actual file
        final fileUrl = '$_fileBase/$filePath';

        final downloadUrl =
            kIsWeb ? '$workerUrl?url=${Uri.encodeComponent(fileUrl)}' : fileUrl;

        AppLogger.d('Downloading from: ${kIsWeb ? "proxy" : "direct"}',
            tag: 'TelegramService');

        final fileRes = await _dio.get(
          downloadUrl,
          options: Options(responseType: ResponseType.bytes),
        );

        final bytes = Uint8List.fromList(fileRes.data as List<int>);
        AppLogger.d('Downloaded ${bytes.length} bytes', tag: 'TelegramService');
        return bytes;
      } on DioException {
        rethrow;
      } catch (e) {
        AppLogger.e('Download failed: $e', tag: 'TelegramService', error: e);
        throw Exception('Failed to download file: $e');
      }
    }, operationName: 'downloadByFileId($fileId)');
  }

  /// Delete a message (used for cleanup)
  Future<void> deleteMessage(int messageId) async {
    if (messageId <= 0) return;
    await TelegramRateLimiter.instance.acquire();
    try {
      await _dio.post(
        '$_base/deleteMessage',
        data: {
          'chat_id': _channelId,
          'message_id': messageId,
        },
      );
    } catch (e) {
      // Ignore errors - message might already be deleted
    }
  }

  /// Get the file_id of a known message_id by forwarding it to the same
  /// channel and reading back the document file_id, then deleting the copy.
  /// Used to discover the pinned metadata file_id on a fresh device.
  Future<String> getFileIdOfMessage(int messageId) async {
    return _withRetry(() async {
      await TelegramRateLimiter.instance.acquire();
      try {
        AppLogger.d('Getting file_id for message $messageId via forward...',
            tag: 'TelegramService');
        // Forward the message to the same channel to get a fresh message object
        final fwdRes = await _dio.post(
          '$_base/forwardMessage',
          data: {
            'chat_id': _channelId,
            'from_chat_id': _channelId,
            'message_id': messageId,
          },
        );

        if (fwdRes.data['ok'] != true) {
          throw Exception(
            'forwardMessage failed: ${fwdRes.data['description']}',
          );
        }

        final fwdMsg = fwdRes.data['result'];
        final fwdMsgId = fwdMsg['message_id'] as int;

        String? fileId;
        if (fwdMsg['document'] != null) {
          fileId = fwdMsg['document']['file_id'] as String?;
        } else if (fwdMsg['sticker'] != null) {
          fileId = fwdMsg['sticker']['file_id'] as String?;
        } else if (fwdMsg['photo'] != null &&
            fwdMsg['photo'] is List &&
            (fwdMsg['photo'] as List).isNotEmpty) {
          fileId = (fwdMsg['photo'] as List).last['file_id'] as String?;
        } else if (fwdMsg['video'] != null) {
          fileId = fwdMsg['video']['file_id'] as String?;
        } else if (fwdMsg['animation'] != null) {
          fileId = fwdMsg['animation']['file_id'] as String?;
        }

        // Clean up the forwarded copy
        await deleteMessage(fwdMsgId);

        if (fileId == null) {
          throw Exception('Pinned message has no document');
        }

        AppLogger.d('Got file_id: $fileId', tag: 'TelegramService');
        return fileId;
      } on DioException {
        rethrow;
      } catch (e) {
        AppLogger.e('getFileIdOfMessage failed: $e',
            tag: 'TelegramService', error: e);
        throw Exception('Failed to get file_id of message $messageId: $e');
      }
    }, operationName: 'getFileIdOfMessage($messageId)');
  }

  /// Pin a message (used for .metadata.json)
  Future<void> pinMessage(int messageId) async {
    return _withRetry(() async {
      await TelegramRateLimiter.instance.acquire();
      try {
        final response = await _dio.post(
          '$_base/pinChatMessage',
          data: {
            'chat_id': _channelId,
            'message_id': messageId,
            'disable_notification': true,
          },
        );

        if (response.data['ok'] != true) {
          throw Exception('Pin failed: ${response.data['description']}');
        }
      } catch (e) {
        // Check if it's a permission error
        if (e.toString().contains('not enough rights') ||
            e.toString().contains('CHAT_ADMIN_REQUIRED')) {
          throw Exception('Bot needs admin permission to pin messages. '
              'Please make your bot an admin in the channel with "Pin Messages" permission.');
        }
        throw Exception('Failed to pin message: $e');
      }
    }, operationName: 'pinMessage($messageId)');
  }

  /// Get pinned message_id
  Future<int> getPinnedMessageId() async {
    return _withRetry(() async {
      await TelegramRateLimiter.instance.acquire();
      try {
        final res = await _dio.get(
          '$_base/getChat',
          queryParameters: {'chat_id': _channelId},
        );

        final pinnedMsg = res.data['result']['pinned_message'];
        if (pinnedMsg == null) {
          throw Exception('No pinned message found');
        }

        return pinnedMsg['message_id'] as int;
      } catch (e) {
        throw Exception('Failed to get pinned message: $e');
      }
    }, operationName: 'getPinnedMessageId()');
  }

  /// Unpin all messages in the channel to prevent accumulation of old pins.
  Future<void> unpinAllMessages() async {
    await TelegramRateLimiter.instance.acquire();
    try {
      final response = await _dio.post(
        '$_base/unpinAllChatMessages',
        data: {
          'chat_id': _channelId,
        },
      );

      if (response.data['ok'] != true) {
        AppLogger.w('unpinAllMessages warning: ${response.data['description']}',
            tag: 'TelegramService');
      }
    } catch (e) {
      AppLogger.w('unpinAllMessages warning: $e', tag: 'TelegramService');
    }
  }

  /// Alias retrieving the permanent Telegram file_id of a message_id.
  Future<String> getFileIdFromMessage(int messageId) async {
    return getFileIdOfMessage(messageId);
  }
}
