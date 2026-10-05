/*
 * File: connectivity_test.dart
 * Description: Unit tests for Connectivity unmetered-network detection override.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/utils/connectivity.dart';

void main() {
  group('Connectivity', () {
    test('isUnmetered honors the test override', () async {
      Connectivity.mockUnmeteredStatus = true;
      expect(await Connectivity.isUnmetered(), isTrue);

      Connectivity.mockUnmeteredStatus = false;
      expect(await Connectivity.isUnmetered(), isFalse);

      Connectivity.mockUnmeteredStatus = null;
    });
  });
}
