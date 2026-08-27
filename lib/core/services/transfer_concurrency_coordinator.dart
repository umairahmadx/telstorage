/*
 * File: transfer_concurrency_coordinator.dart
 * Description: Global concurrency coordinator enforcing bounded simultaneous network transfers across uploads, downloads, and background workers.
 */

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Central coordinator enforcing a unified concurrency ceiling across all transfer operations.
///
/// Prevents thread pool exhaustion, buffer contention, and Telegram 429 flood rate limits
/// by bounding concurrent active operations across uploads, downloads, and packaging tasks.
class TransferConcurrencyCoordinator {
  static final TransferConcurrencyCoordinator instance =
      TransferConcurrencyCoordinator._();
  TransferConcurrencyCoordinator._();

  int _maxConcurrent = 3;

  /// Maximum concurrent active transfers allowed across all subsystems.
  int get maxConcurrent => _maxConcurrent;

  /// Modifies maximum concurrency limit for testing or device constraint tuning.
  @visibleForTesting
  void setMaxConcurrentForTesting(int value) {
    _maxConcurrent = value;
  }

  int _activeCount = 0;

  /// Current number of actively executing transfers holding permits.
  int get activeCount => _activeCount;

  final List<Completer<void>> _waiters = [];

  /// Executes [operation] within a guarded permit lease.
  /// Automatically releases the slot upon completion or error.
  Future<T> runGuarded<T>(Future<T> Function() operation) async {
    await acquire();
    try {
      return await operation();
    } finally {
      release();
    }
  }

  /// Acquires a transfer permit or waits in FIFO queue until one becomes available.
  Future<void> acquire() async {
    if (_activeCount < _maxConcurrent) {
      _activeCount++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  /// Releases an active permit, transferring it to the next queued waiter or decrementing active count.
  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next.complete();
    } else {
      if (_activeCount > 0) {
        _activeCount--;
      }
    }
  }

  /// Resets coordinator state and cancels any pending waiters.
  void reset() {
    _activeCount = 0;
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(
          StateError('TransferConcurrencyCoordinator was reset'),
        );
      }
    }
    _waiters.clear();
    _maxConcurrent = 3;
  }
}
