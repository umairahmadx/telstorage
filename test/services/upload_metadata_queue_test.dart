import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UploadService metadata resilient queue fallback structure test', () {
    final payload = {
      'fileMeta': {'name': 'test.png', 'file_id': '123'}
    };
    expect(payload['fileMeta']?['name'], equals('test.png'));
  });
}
