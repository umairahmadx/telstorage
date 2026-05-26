import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../constants/app_constants.dart';

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
  Future<Map<String, dynamic>> uploadBytesWithFileId(Uint8List bytes, String filename) async {
    try {
      print('📤 [TelegramService] Uploading: $filename (${bytes.length} bytes)');
      
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
      
      print('✅ [TelegramService] Uploaded successfully, message_id: $messageId, file_id: $fileId');
      return {
        'message_id': messageId,
        'file_id': fileId,
      };
    } catch (e) {
      print('❌ [TelegramService] Upload failed: $e');
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
      print('📥 [TelegramService] Downloading file with file_id: $fileId');
      
      // Step 1: Get file path using file_id
      print('📥 [TelegramService] Getting file path...');
      final filePathRes = await _dio.get(
        '$_base/getFile',
        queryParameters: {'file_id': fileId},
      );

      final filePath = filePathRes.data['result']['file_path'] as String;
      print('📥 [TelegramService] Got file path: $filePath');

      // Step 2: Download the actual file
      final fileUrl = '$_fileBase/$filePath';
      
      // On web, use your own Cloudflare Worker proxy
      final workerUrl = dotenv.env['WORKER_URL'] ?? 'https://telstorage-proxy.umair-ahmed-64422.workers.dev';
      
      final downloadUrl = kIsWeb 
          ? '$workerUrl?url=${Uri.encodeComponent(fileUrl)}'
          : fileUrl;
      
      print('📥 [TelegramService] Downloading from: ${kIsWeb ? "Cloudflare Worker proxy" : "direct"}');
      
      final fileRes = await _dio.get(
        downloadUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = Uint8List.fromList(fileRes.data as List<int>);
      print('📥 [TelegramService] Downloaded ${bytes.length} bytes');
      return bytes;
    } catch (e) {
      print('❌ [TelegramService] Download failed: $e');
      throw Exception('Failed to download file: $e');
    }
  }

  /// Download file bytes by message_id (legacy - requires lookup)
  Future<Uint8List> downloadBytes(int messageId) async {
    try {
      print('📥 [TelegramService] Starting download for message_id: $messageId');
      
      // Step 1: Get file_id from the message
      print('📥 [TelegramService] Fetching file_id from message...');
      final fileId = await getFileIdFromMessage(messageId);
      print('📥 [TelegramService] Got file_id: $fileId');
      
      // Step 2: Download using file_id
      return await downloadByFileId(fileId);
    } catch (e) {
      print('❌ [TelegramService] Download failed: $e');
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
      print(
        '🔍 [TelegramService] Getting file_id for message $messageId '
        'via forward...',
      );
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

      print('✅ [TelegramService] Got file_id: $fileId');
      return fileId;
    } catch (e) {
      print('❌ [TelegramService] getFileIdOfMessage failed: $e');
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
        throw Exception(
          'Bot needs admin permission to pin messages. '
          'Please make your bot an admin in the channel with "Pin Messages" permission.'
        );
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

  /// Get file_id from a document message (needed for downloads)
  Future<String> getFileIdFromMessage(int messageId) async {
    try {
      print('🔍 [TelegramService] Looking for file_id for message_id: $messageId');
      
      // Use getUpdates to fetch recent message history
      final res = await _dio.get(
        '$_base/getUpdates',
        queryParameters: {
          'offset': -1, // Get recent updates
          'limit': 100,
          'allowed_updates': ['channel_post', 'message'],
        },
      );

      print('🔍 [TelegramService] Got ${res.data['result'].length} updates');
      
      final updates = res.data['result'] as List;
      for (final update in updates) {
        final message = update['channel_post'] ?? update['message'];
        if (message != null && message['message_id'] == messageId) {
          final document = message['document'];
          if (document != null) {
            final fileId = document['file_id'] as String;
            print('✅ [TelegramService] Found file_id: $fileId');
            return fileId;
          }
        }
      }

      print('❌ [TelegramService] Message $messageId not found in recent updates');
      print('💡 [TelegramService] Trying alternative method: fetching chat history...');
      
      // Alternative: Try to get the message directly via chat history
      // This requires the message to be recent enough
      throw Exception(
        'Message $messageId not found in recent updates. '
        'The message might be too old or the bot needs to receive new updates. '
        'Try sending a test message to the channel first.'
      );
    } catch (e) {
      print('❌ [TelegramService] Failed to get file_id: $e');
      throw Exception('Failed to get file_id: $e');
    }
  }
}
