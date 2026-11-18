/*
 * File: telegram_rate_limiter.dart
 * Description: Priority-aware token-bucket rate limiter managing Telegram per-chat invocation spacing and HTTP 429 flood wait backoffs.
 */

import 'dart:async';
import '../utils/app_logger.dart';

/// Priority levels for outbound Telegram API requests.
enum RequestPriority {
  /// Highest priority: Active visible photo and its thumbnail (jumps ahead of background jobs).
  immediate,

  /// Standard priority: User-initiated actions and visible folder browsing.
  normal,

  /// Lowest priority: Background prefetching of adjacent images.
  background,
}

class _QueuedRequest {
  final Completer<void> completer;
  final RequestPriority priority;
  _QueuedRequest(this.completer, this.priority);
}

/// Centralized token-bucket rate limiter for all Telegram API calls.
/// Ensures requests stay within ~1 req/sec sustained per chat and respects HTTP 429 retry_after headers.
class TelegramRateLimiter {
  static final TelegramRateLimiter instance = TelegramRateLimiter._internal();

  TelegramRateLimiter._internal();

  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _pauseUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minInterval = Duration(milliseconds: 1000);

  /// Telegram caps bots at ~20 new messages per minute in the same chat.
  static const Duration minSendInterval = Duration(seconds: 3);
  DateTime _lastSendTime = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _sendGate = Future.value();

  final List<_QueuedRequest> _queue = [];
  bool _isProcessing = false;

  /// Whether an HTTP 429 rate limit backoff is currently active.
  bool get isPaused => DateTime.now().isBefore(_pauseUntil);

  /// Remaining duration of the active HTTP 429 cooldown period, or [Duration.zero].
  Duration get remainingCooldown {
    final now = DateTime.now();
    return now.isBefore(_pauseUntil)
        ? _pauseUntil.difference(now)
        : Duration.zero;
  }

  /// Number of pending requests currently waiting for a rate-limited slot.
  int get queueLength => _queue.length;

  /// Snapshot of priority levels for all requests currently waiting in the queue.
  List<RequestPriority> get queuedPriorities =>
      _queue.map((r) => r.priority).toList();

  /// Wait for a serialized slot before making an outbound Telegram API call.
  /// High-priority requests jump ahead of background prefetches.
  Future<void> acquire([RequestPriority priority = RequestPriority.normal]) {
    final completer = Completer<void>();
    final item = _QueuedRequest(completer, priority);

    switch (priority) {
      case RequestPriority.immediate:
        // Insert after any existing immediate items, but ahead of normal/background
        final insertIndex =
            _queue.lastIndexWhere((r) => r.priority == RequestPriority.immediate);
        if (insertIndex == -1) {
          _queue.insert(0, item);
        } else {
          _queue.insert(insertIndex + 1, item);
        }
        break;
      case RequestPriority.normal:
        // Insert before background items
        final firstBgIndex =
            _queue.indexWhere((r) => r.priority == RequestPriority.background);
        if (firstBgIndex == -1) {
          _queue.add(item);
        } else {
          _queue.insert(firstBgIndex, item);
        }
        break;
      case RequestPriority.background:
        _queue.add(item);
        break;
    }

    _processQueue();
    return completer.future;
  }

  /// Like [acquire], but additionally spaces calls that post a new message to the channel
  /// (sendDocument, forwardMessage) by [minSendInterval] so bulk uploads avoid HTTP 429.
  Future<void> acquireSend([RequestPriority priority = RequestPriority.normal]) {
    final slot = _sendGate.then((_) async {
      while (true) {
        final intervalWait =
            minSendInterval - DateTime.now().difference(_lastSendTime);
        final cooldown = remainingCooldown;
        final wait = cooldown > intervalWait ? cooldown : intervalWait;
        if (wait <= Duration.zero) break;
        await Future.delayed(wait);
      }
      _lastSendTime = DateTime.now();
    });
    _sendGate = slot;
    return slot.then((_) => acquire(priority));
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final req = _queue.removeAt(0);

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

      if (!req.completer.isCompleted) {
        req.completer.complete();
      }
    }

    _isProcessing = false;
  }

  /// Inform limiter of an HTTP 429 response with retry_after seconds.
  void report429(int retryAfterSeconds) {
    _pauseUntil = DateTime.now().add(Duration(seconds: retryAfterSeconds + 1));
    AppLogger.w(
      'TelegramRateLimiter: HTTP 429 reported — backing off for ${retryAfterSeconds + 1}s',
      tag: 'RateLimiter',
    );
  }

  /// Reset rate limiter state on logout or test cleanup.
  void reset() {
    _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
    _pauseUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSendTime = DateTime.fromMillisecondsSinceEpoch(0);
    _sendGate = Future.value();
    for (final req in _queue) {
      if (!req.completer.isCompleted) req.completer.complete();
    }
    _queue.clear();
    _isProcessing = false;
  }
}
