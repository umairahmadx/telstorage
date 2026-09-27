import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FLUTTER_TEST environment variable is detected to safely guard native plugins', () {
    expect(Platform.environment.containsKey('FLUTTER_TEST'), isTrue);
  });
}
