/*
 * File: telegram_dio_adapter_native.dart
 * Description: Native platform adapter configuration injecting TelegramDnsResolver into IOHttpClientAdapter.
 */

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'telegram_dns_resolver.dart';

/// Configures [dio] with a custom [HttpClient.connectionFactory] that intercepts
/// host lookups for Telegram domains and delegates to [TelegramDnsResolver].
void configureTelegramDioAdapter(Dio dio) {
  final adapter = dio.httpClientAdapter;
  if (adapter is IOHttpClientAdapter) {
    adapter.createHttpClient = () {
      final client = HttpClient();
      client.connectionFactory = (uri, host, port) async {
        final targetHost = host ?? uri.host;
        final targetPort = port ?? uri.port;
        if (targetHost.contains('telegram.org')) {
          final resolved = await TelegramDnsResolver.instance.resolve(targetHost);
          if (resolved != null) {
            if (uri.scheme == 'https') {
              return SecureSocket.startConnect(
                resolved,
                targetPort,
                onBadCertificate: (cert) =>
                    cert.subject.contains('telegram.org') ||
                    cert.subject.contains('api.telegram.org'),
              );
            }
            return Socket.startConnect(resolved, targetPort);
          }
        }
        if (uri.scheme == 'https') {
          return SecureSocket.startConnect(
            targetHost,
            targetPort,
            onBadCertificate: (cert) =>
                cert.subject.contains('telegram.org') ||
                cert.subject.contains('api.telegram.org'),
          );
        }
        return Socket.startConnect(targetHost, targetPort);
      };
      return client;
    };
  }
}
