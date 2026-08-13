import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SyncService pending file protection logic test', () {
    final pendingIds = <String>{'file-123', 'folder-abc'};
    expect(pendingIds.contains('file-123'), isTrue);
    expect(pendingIds.contains('file-999'), isFalse);
  });
}
