/*
 * File: telegram_dns_resolver.dart
 * Description: Resilient DNS resolver with DNS-over-HTTPS (DoH) and static IP fallback for Telegram Bot API.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

/// Delegate signature for system host lookup.
typedef HostLookupDelegate = Future<List<InternetAddress>> Function(String host);

/// Delegate signature for DNS-over-HTTPS lookup.
typedef DohLookupDelegate = Future<InternetAddress?> Function(String host);

/// Service providing resilient DNS resolution for Telegram Bot API hostnames.
///
/// When standard system DNS queries fail (e.g. due to ISP DNS blocking, DNS poisoning,
/// or network glitches), this resolver seamlessly falls back to DNS-over-HTTPS (DoH)
/// via Cloudflare/Google public DNS, and finally to hardcoded Telegram API IP fallbacks.
class TelegramDnsResolver {
  /// Singleton instance of TelegramDnsResolver.
  static final TelegramDnsResolver instance = TelegramDnsResolver();

  /// Known verified static IPv4 addresses for api.telegram.org as ultimate fallback.
  static const List<String> staticFallbackIps = [
    '149.154.167.220',
    '149.154.167.99',
  ];

  /// Time-to-live for cached DNS resolution results (10 minutes).
  static const Duration cacheTtl = Duration(minutes: 10);

  /// In-memory cache storing resolved IP and resolution timestamp.
  final Map<String, (InternetAddress address, DateTime expiry)> _cache = {};

  /// Injectable delegate for system DNS lookup (defaults to InternetAddress.lookup).
  @visibleForTesting
  HostLookupDelegate? lookupDelegate;

  /// Injectable delegate for DoH lookup.
  @visibleForTesting
  DohLookupDelegate? dohLookupDelegate;

  /// Clears the in-memory DNS cache.
  void resetCache() {
    _cache.clear();
  }

  /// Resolves [hostname] into a valid [InternetAddress].
  ///
  /// Priority order:
  /// 1. In-memory cache if not expired.
  /// 2. Standard system DNS lookup.
  /// 3. DNS-over-HTTPS (DoH) via Cloudflare (1.1.1.1) and Google (8.8.8.8).
  /// 4. Known static fallback IPs for `api.telegram.org`.
  Future<InternetAddress?> resolve(String hostname) async {
    final now = DateTime.now();

    // 1. Check in-memory cache
    final cached = _cache[hostname];
    if (cached != null && now.isBefore(cached.$2)) {
      return cached.$1;
    }

    // 2. Standard system DNS lookup
    try {
      final lookup = lookupDelegate ?? InternetAddress.lookup;
      final results = await lookup(hostname).timeout(const Duration(seconds: 3));
      if (results.isNotEmpty) {
        final address = results.first;
        _cache[hostname] = (address, now.add(cacheTtl));
        return address;
      }
    } catch (e) {
      AppLogger.w(
        'System DNS lookup failed for $hostname: $e. Attempting DoH fallback...',
        tag: 'TelegramDnsResolver',
      );
    }

    // 3. DNS-over-HTTPS (DoH) fallback
    try {
      final dohLookup = dohLookupDelegate ?? _queryDoh;
      final dohAddress = await dohLookup(hostname);
      if (dohAddress != null) {
        _cache[hostname] = (dohAddress, now.add(cacheTtl));
        AppLogger.i(
          'Resolved $hostname via DoH fallback to ${dohAddress.address}',
          tag: 'TelegramDnsResolver',
        );
        return dohAddress;
      }
    } catch (e) {
      AppLogger.w(
        'DoH lookup failed for $hostname: $e. Checking static fallback...',
        tag: 'TelegramDnsResolver',
      );
    }

    // 4. Static fallback IPs for api.telegram.org
    if (hostname.contains('telegram.org')) {
      final fallbackAddress = InternetAddress(staticFallbackIps.first);
      _cache[hostname] = (fallbackAddress, now.add(cacheTtl));
      AppLogger.w(
        'Using static IP fallback for $hostname: ${fallbackAddress.address}',
        tag: 'TelegramDnsResolver',
      );
      return fallbackAddress;
    }

    return null;
  }

  /// Queries Cloudflare or Google DoH endpoints to resolve [hostname].
  Future<InternetAddress?> _queryDoh(String hostname) async {
    final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    try {
      // Primary: Cloudflare DoH
      final cfUri = Uri.parse('https://1.1.1.1/dns-query?name=$hostname&type=A');
      final req = await client.getUrl(cfUri).timeout(const Duration(seconds: 4));
      req.headers.set('Accept', 'application/dns-json');
      final resp = await req.close().timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final answers = json['Answer'] as List<dynamic>?;
        if (answers != null && answers.isNotEmpty) {
          for (final ans in answers) {
            final data = ans['data']?.toString();
            if (data != null && data.isNotEmpty && !data.contains(':')) {
              return InternetAddress(data);
            }
          }
        }
      }
    } catch (e) {
      AppLogger.d('Cloudflare DoH query failed: $e', tag: 'TelegramDnsResolver');
    } finally {
      client.close(force: true);
    }

    // Secondary: Google DoH
    final googleClient = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    try {
      final googleUri = Uri.parse('https://dns.google/resolve?name=$hostname&type=A');
      final req = await googleClient.getUrl(googleUri).timeout(const Duration(seconds: 4));
      final resp = await req.close().timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final answers = json['Answer'] as List<dynamic>?;
        if (answers != null && answers.isNotEmpty) {
          for (final ans in answers) {
            final data = ans['data']?.toString();
            if (data != null && data.isNotEmpty && !data.contains(':')) {
              return InternetAddress(data);
            }
          }
        }
      }
    } catch (e) {
      AppLogger.d('Google DoH query failed: $e', tag: 'TelegramDnsResolver');
    } finally {
      googleClient.close(force: true);
    }

    return null;
  }
}
