/// File: service_locator_test.dart
/// Description: Unit test validating ServiceLocator singleton registration and access.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/service_locator.dart';

void main() {
  group('ServiceLocator Tests', () {
    test('ServiceLocator provides singleton instance', () {
      final instance1 = ServiceLocator.instance;
      final instance2 = ServiceLocator.instance;

      expect(identical(instance1, instance2), isTrue);
    });

    test('ServiceLocator exposes static and always-available services', () {
      final locator = ServiceLocator.instance;
      expect(locator.navigation, isNotNull);
      expect(locator.transferQueue, isNotNull);
      expect(locator.isInitialized, isFalse);
    });
  });
}
