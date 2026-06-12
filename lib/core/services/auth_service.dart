import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import 'service_locator.dart';

/// Handles authentication via Google Apps Script
class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  final _storage = const FlutterSecureStorage();
  final _dio = Dio();

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await _dio.get(
        AppConstants.scriptUrl,
        queryParameters: {
          'action': 'login',
          'email': email,
          'password': password,
        },
      );

      if (res.data['success'] == true) {
        await _storage.write(key: 'bot_token', value: res.data['bot_token']);
        await _storage.write(key: 'channel_id', value: res.data['channel_id']);
        await _storage.write(key: 'email', value: email);
      }

      return res.data as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> register(
    String email,
    String password,
    String botToken,
    String channelId,
  ) async {
    try {
      final res = await _dio.get(
        AppConstants.scriptUrl,
        queryParameters: {
          'action': 'register',
          'email': email,
          'password': password,
          'bot_token': botToken,
          'channel_id': channelId,
        },
      );
      if (res.data['success'] == true) {
        await _storage.write(key: 'bot_token', value: botToken);
        await _storage.write(key: 'channel_id', value: channelId);
        await _storage.write(key: 'email', value: email);
      }
      return res.data as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'bot_token');
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    ServiceLocator.instance.reset();
    await _storage.deleteAll();
  }

  Future<String?> getToken() async => _storage.read(key: 'bot_token');
  Future<String?> getChannelId() async => _storage.read(key: 'channel_id');
  Future<String?> getEmail() async => _storage.read(key: 'email');
}
