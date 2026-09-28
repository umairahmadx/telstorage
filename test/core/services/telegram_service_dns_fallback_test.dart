/*
 * File: telegram_service_dns_fallback_test.dart
 * Description: Unit tests validating TelegramService's integration with TelegramDnsResolver for connection factory interception.
 */

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/telegram_dns_resolver.dart';
import 'package:telstorage/core/services/telegram_service.dart';

void main() {
  group('TelegramService DNS Fallback Integration Tests', () {
    late TelegramDnsResolver resolver;

    setUp(() {
      resolver = TelegramDnsResolver.instance;
      resolver.resetCache();
    });

    test('TC-TG-DNS-01: Configures IOHttpClientAdapter with custom DNS resolution for telegram.org', () async {
      final resolvedHosts = <String>[];
      resolver.lookupDelegate = (host) async {
        resolvedHosts.add(host);
        return [InternetAddress('149.154.167.220')];
      };

      final dio = Dio();
      final service = TelegramService(dio: dio);
      await service.init('test_token', '-100123456');

      expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
      final ioAdapter = dio.httpClientAdapter as IOHttpClientAdapter;
      expect(ioAdapter.createHttpClient, isNotNull);

      // Verify createHttpClient returns a configured client without throwing
      final client = ioAdapter.createHttpClient!();
      expect(client, isA<HttpClient>());

      // Making a simulated request triggers connectionFactory resolution
      try {
        final req = await client.getUrl(Uri.parse('https://api.telegram.org/bot123/getMe')).timeout(const Duration(milliseconds: 200));
        await req.close();
      } catch (_) {
        // Socket connection may fail in sandbox, but resolver MUST have been queried
      }

      expect(resolvedHosts, contains('api.telegram.org'));
      client.close(force: true);
    });
  });
}
