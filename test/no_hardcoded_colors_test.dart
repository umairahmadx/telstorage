import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ensure no hardcoded visual colors exist in lib outside app_theme.dart', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), true, reason: 'lib directory must exist');

    // Matches color literals (excluding Colors.transparent)
    final hardcodedColorRegExp = RegExp(
      r'\bColors\.(?!(transparent\b))[a-zA-Z0-9_]+\b|\bColor\(0x[0-9a-fA-F]+\)|\bColor\.fromARGB\(|\bColor\.fromRGBO\(',
    );

    final violations = <String>[];

    final files = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.replaceAll('\\', '/').endsWith('lib/core/theme/app_theme.dart'));

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();
        if (trimmed.startsWith('//')) continue;

        if (hardcodedColorRegExp.hasMatch(line)) {
          final normalizedPath = file.path.replaceAll('\\', '/');
          violations.add('$normalizedPath:${i + 1}: ${line.trim()}');
        }
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Found hardcoded color references outside lib/core/theme/app_theme.dart:\n\n'
        '${violations.join('\n')}\n\n'
        'All visual colors must be configured in lib/core/theme/app_theme.dart and consumed via Theme tokens.',
      );
    }
  });
}
