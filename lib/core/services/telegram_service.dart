import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';

/// All raw Telegram Bot API calls
class TelegramService {
  late final String _token;
  late final String _channelId;
  final _dio = Dio();

  String get _base => '${AppConstants.telegramApiBase}$_token';
  String get _fileBase => '${AppConstants.telegramFileBase}$_token';

  Future<void> init(String token, String channelId) async {
    _token = token;
    _channelId = channelId;
  }

  /// Upload a file (chunk or metadata json) → returns message_id and file_id
  Future<Map<String, dynamic>> uploadBytesWithFileId(
      Uint8List bytes, String filename) async {
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
      final fileId = result['document']['file_id'] as String;

      AppLogger.d(
          'Uploaded successfully, message_id: $messageId, file_id: $fileId',
          tag: 'TelegramService');
      return {
        'message_id': messageId,
        'file_id': fileId,
      };
    } catch (e) {
      AppLogger.e('Upload failed: $e', tag: 'TelegramService', error: e);
      throw Exception('Failed to upload file: $e');
    }
  }

  /// Upload a file (chunk or metadata json) → returns message_id only (legacy)
  Future<int> uploadBytes(Uint8List bytes, String filename) async {
    final result = await uploadBytesWithFileId(bytes, filename);
    return result['message_id'] as int;
  }

  /// Download file bytes by file_id (preferred method)
  Future<Uint8List> downloadByFileId(String fileId) async {
    try {
      AppLogger.d('Downloading file with file_id: $fileId',
          tag: 'TelegramService');

      // Step 1: Get file path using file_id
      AppLogger.d('Getting file path...', tag: 'TelegramService');
      final filePathRes = await _dio.get(
        '$_base/getFile',
        queryParameters: {'file_id': fileId},
      );

      final filePath = filePathRes.data['result']['file_path'] as String;
      AppLogger.d('Got file path: $filePath', tag: 'TelegramService');

      // Step 2: Download the actual file
      final fileUrl = '$_fileBase/$filePath';

      // On web, use your own Cloudflare Worker proxy
      final workerUrl = dotenv.env['WORKER_URL'] ??
          'https://telstorage-proxy.umair-ahmed-64422.workers.dev';

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
    } catch (e) {
      AppLogger.e('Download failed: $e', tag: 'TelegramService', error: e);
      throw Exception('Failed to download file: $e');
    }
  }

  /// Download file bytes by message_id (legacy - requires lookup)
  Future<Uint8List> downloadBytes(int messageId) async {
    try {
      AppLogger.d('Starting download for message_id: $messageId',
          tag: 'TelegramService');

      // Step 1: Get file_id from the message
      AppLogger.d('Fetching file_id from message...', tag: 'TelegramService');
      final fileId = await getFileIdFromMessage(messageId);
      AppLogger.d('Got file_id: $fileId', tag: 'TelegramService');

      // Step 2: Download using file_id
      return await downloadByFileId(fileId);
    } catch (e) {
      AppLogger.e('Download failed: $e', tag: 'TelegramService', error: e);
      throw Exception('Failed to download file: $e');
    }
  }

  /// Delete a message (used for cleanup)
  Future<void> deleteMessage(int messageId) async {
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
      final fileId = fwdMsg['document']?['file_id'] as String?;

      // Clean up the forwarded copy
      await deleteMessage(fwdMsgId);

      if (fileId == null) {
        throw Exception('Pinned message has no document');
      }

      AppLogger.d('Got file_id: $fileId', tag: 'TelegramService');
      return fileId;
    } catch (e) {
      AppLogger.e('getFileIdOfMessage failed: $e',
          tag: 'TelegramService', error: e);
      throw Exception('Failed to get file_id of message $messageId: $e');
    }
  }

  /// Pin a message (used for .metadata.json)
  Future<void> pinMessage(int messageId) async {
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
  }

  /// Get pinned message_id
  Future<int> getPinnedMessageId() async {
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
  }

  Future<String> getFileIdFromMessage(int messageId) async {
    return getFileIdOfMessage(messageId);
  }
}
