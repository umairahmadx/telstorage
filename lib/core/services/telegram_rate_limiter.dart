import '../utils/app_logger.dart';

/// Centralized token-bucket rate limiter for all Telegram API calls.
/// Ensures requests stay within ~1 req/sec sustained per chat and respects HTTP 429 retry_after headers.
class TelegramRateLimiter {
  static final TelegramRateLimiter instance = TelegramRateLimiter._internal();

  TelegramRateLimiter._internal();

  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _pauseUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minInterval = Duration(milliseconds: 1000); // 1 request per second

  /// Wait for a slot before making an outbound Telegram API call
  Future<void> acquire() async {
    final now = DateTime.now();

    // Check if dynamic 429 retry_after pause is active
    if (now.isBefore(_pauseUntil)) {
      final waitMs = _pauseUntil.difference(now).inMilliseconds;
      AppLogger.w(
        'TelegramRateLimiter: HTTP 429 active — pausing outbound calls for ${waitMs}ms',
        tag: 'RateLimiter',
      );
      await Future.delayed(Duration(milliseconds: waitMs));
    }

    final elapsed = DateTime.now().difference(_lastRequestTime);
    if (elapsed < _minInterval) {
      final delay = _minInterval - elapsed;
      await Future.delayed(delay);
    }
    _lastRequestTime = DateTime.now();
  }

  /// Inform limiter of an HTTP 429 response with retry_after seconds
  void report429(int retryAfterSeconds) {
    _pauseUntil = DateTime.now().add(Duration(seconds: retryAfterSeconds + 1));
    AppLogger.w(
      'TelegramRateLimiter: HTTP 429 reported — backing off for ${retryAfterSeconds + 1}s',
      tag: 'RateLimiter',
    );
  }

  /// Reset rate limiter state on logout
  void reset() {
    _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
    _pauseUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
