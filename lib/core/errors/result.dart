/// File: result.dart
/// Description: Component and logic definition for result.dart in TelStorage.
library;

import 'package:flutter/foundation.dart';

/// Sealed class representing functional domain failures.
@immutable
sealed class StorageFailure {
  final String message;
  final Object? cause;

  const StorageFailure(this.message, [this.cause]);

  @override
  String toString() => message;
}

class NetworkFailure extends StorageFailure {
  const NetworkFailure(super.message, [super.cause]);
}

class HashMismatchFailure extends StorageFailure {
  const HashMismatchFailure([super.message = 'File integrity check failed: SHA-256 hash mismatch']);
}

class QuotaExceededFailure extends StorageFailure {
  const QuotaExceededFailure([super.message = 'Bandwidth or storage quota exceeded']);
}

class CancelledFailure extends StorageFailure {
  const CancelledFailure([super.message = 'Operation cancelled by user']);
}

class NotFoundFailure extends StorageFailure {
  const NotFoundFailure([super.message = 'Resource not found']);
}

class UnknownFailure extends StorageFailure {
  const UnknownFailure(super.message, [super.cause]);
}

/// Sealed class representing the result of an operation — either [Success] or [Failure].
@immutable
sealed class Result<S> {
  const Result();

  bool get isSuccess => this is Success<S>;
  bool get isFailure => this is Failure<S>;

  S? get dataOrNull => this is Success<S> ? (this as Success<S>).data : null;
  StorageFailure? get failureOrNull =>
      this is Failure<S> ? (this as Failure<S>).failure : null;

  T fold<T>(
    T Function(S data) onSuccess,
    T Function(StorageFailure failure) onFailure,
  ) {
    if (this is Success<S>) {
      return onSuccess((this as Success<S>).data);
    } else {
      return onFailure((this as Failure<S>).failure);
    }
  }
}

class Success<S> extends Result<S> {
  final S data;
  const Success(this.data);
}

class Failure<S> extends Result<S> {
  final StorageFailure failure;
  const Failure(this.failure);
}
