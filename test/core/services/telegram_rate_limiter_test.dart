/*
 * File: telegram_rate_limiter_test.dart
 * Description: Unit tests validating TelegramRateLimiter serialization, 429 cooldown tracking, and thundering-herd prevention.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';

void main() {
  group('TelegramRateLimiter Tests', () {
    setUp(() {
      TelegramRateLimiter.instance.reset();
    });

    tearDown(() {
      TelegramRateLimiter.instance.reset();
    });

    test('TC-01: report429 sets isPaused to true and calculates remainingCooldown', () {
      final limiter = TelegramRateLimiter.instance;
      expect(limiter.isPaused, isFalse);
      expect(limiter.remainingCooldown, equals(Duration.zero));

      limiter.report429(5);

      expect(limiter.isPaused, isTrue);
      expect(limiter.remainingCooldown.inSeconds, greaterThanOrEqualTo(4));
    });

    test('TC-02: acquire serializes concurrent requests without bursting simultaneously', () async {
      final limiter = TelegramRateLimiter.instance;
      final executionTimestamps = <DateTime>[];

      // Launch 3 requests concurrently
      await Future.wait([
        limiter.acquire().then((_) => executionTimestamps.add(DateTime.now())),
        limiter.acquire().then((_) => executionTimestamps.add(DateTime.now())),
        limiter.acquire().then((_) => executionTimestamps.add(DateTime.now())),
      ]);

      expect(executionTimestamps.length, equals(3));
      // First to second should be spaced
      final diff1 = executionTimestamps[1].difference(executionTimestamps[0]).inMilliseconds;
      // Second to third should be spaced
      final diff2 = executionTimestamps[2].difference(executionTimestamps[1]).inMilliseconds;

      expect(diff1, greaterThanOrEqualTo(900), reason: 'Calls must be spaced by at least 1s');
      expect(diff2, greaterThanOrEqualTo(900), reason: 'Calls must be spaced by at least 1s');
    });

    test('TC-03: reset clears isPaused and remainingCooldown', () {
      final limiter = TelegramRateLimiter.instance;
      limiter.report429(10);
      expect(limiter.isPaused, isTrue);

      limiter.reset();
      expect(limiter.isPaused, isFalse);
      expect(limiter.remainingCooldown, equals(Duration.zero));
    });

    test('TC-04: acquire prioritizes immediate over normal and background requests', () {
      final limiter = TelegramRateLimiter.instance;
      // Pause limiter so items accumulate in the queue without draining
      limiter.report429(10);

      // 1. Initial request takes the active in-flight slot (which is paused by 429)
      limiter.acquire(RequestPriority.background);

      // 2. Queue up remaining requests in reverse priority order while active slot is waiting
      limiter.acquire(RequestPriority.background);
      limiter.acquire(RequestPriority.normal);
      limiter.acquire(RequestPriority.immediate);

      // 3 items should now be waiting in the queue
      expect(limiter.queueLength, equals(3));

      // Items in queue must be strictly prioritized: immediate, normal, background
      expect(
        limiter.queuedPriorities,
        equals([
          RequestPriority.immediate,
          RequestPriority.normal,
          RequestPriority.background,
        ]),
      );
    });
  });
}
