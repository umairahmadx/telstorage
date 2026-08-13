import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ensure no Dart file in lib/ exceeds 500 lines of code', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib directory must exist');

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    final oversizedFiles = <String, int>{};

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync().length;
      if (lines > 500) {
        oversizedFiles[file.path] = lines;
      }
    }

    if (oversizedFiles.isNotEmpty) {
      final summary = oversizedFiles.entries
          .map((e) => '${e.key}: ${e.value} lines')
          .join('\n');
      fail('The following files exceed the 500 line limit:\n$summary');
    }

    expect(oversizedFiles, isEmpty);
  });
}
