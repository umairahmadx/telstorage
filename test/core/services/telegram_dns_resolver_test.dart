/*
 * File: telegram_dns_resolver_test.dart
 * Description: Unit tests for TelegramDnsResolver verifying standard DNS lookup, DoH fallback, and static IP fallback.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/telegram_dns_resolver.dart';

void main() {
  group('TelegramDnsResolver Tests', () {
    late TelegramDnsResolver resolver;

    setUp(() {
      resolver = TelegramDnsResolver();
      resolver.resetCache();
    });

    test('TC-DNS-01: Uses standard system DNS lookup when available', () async {
      resolver.lookupDelegate = (host) async {
        return [InternetAddress('1.2.3.4')];
      };

      final address = await resolver.resolve('api.telegram.org');
      expect(address, isNotNull);
      expect(address!.address, equals('1.2.3.4'));
    });

    test('TC-DNS-02: Falls back to DoH when system DNS lookup throws SocketException', () async {
      resolver.lookupDelegate = (host) async {
        throw const SocketException("Failed host lookup: 'api.telegram.org'", osError: OSError('No address associated with hostname', 7));
      };
      resolver.dohLookupDelegate = (host) async {
        return InternetAddress('149.154.167.220');
      };

      final address = await resolver.resolve('api.telegram.org');
      expect(address, isNotNull);
      expect(address!.address, equals('149.154.167.220'));
    });

    test('TC-DNS-03: Falls back to static known IP when both system DNS and DoH fail', () async {
      resolver.lookupDelegate = (host) async {
        throw const SocketException("Failed host lookup: 'api.telegram.org'");
      };
      resolver.dohLookupDelegate = (host) async {
        throw Exception('DoH unreachable');
      };

      final address = await resolver.resolve('api.telegram.org');
      expect(address, isNotNull);
      expect(TelegramDnsResolver.staticFallbackIps.contains(address!.address), isTrue);
    });

    test('TC-DNS-04: Caches resolved IP in memory within TTL', () async {
      int systemCallCount = 0;
      resolver.lookupDelegate = (host) async {
        systemCallCount++;
        return [InternetAddress('149.154.167.99')];
      };

      final first = await resolver.resolve('api.telegram.org');
      final second = await resolver.resolve('api.telegram.org');

      expect(first!.address, equals('149.154.167.99'));
      expect(second!.address, equals('149.154.167.99'));
      expect(systemCallCount, equals(1));
    });
  });
}
