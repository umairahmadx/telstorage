/// File: sealed_result_test.dart
/// Description: Unit tests for Result sealed hierarchy pattern matching and states.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/errors/result.dart';

String describeResult(Result<int> result) => switch (result) {
      Success<int>(data: final value) => 'success:$value',
      Failure<int>(failure: final failure) => 'failure:${failure.message}',
    };

void main() {
  test('Success is represented by the sealed result hierarchy', () {
    const result = Success<int>(42);

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull, 42);
    expect(describeResult(result), 'success:42');
  });

  test('Failure is represented by the sealed result hierarchy', () {
    const result = Failure<int>(NetworkFailure('offline'));

    expect(result.isFailure, isTrue);
    expect(result.failureOrNull?.message, 'offline');
    expect(describeResult(result), 'failure:offline');
  });
}
