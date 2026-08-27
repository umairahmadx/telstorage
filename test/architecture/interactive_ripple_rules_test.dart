/*
 * File: interactive_ripple_rules_test.dart
 * Description: Architecture test enforcing that interactive UI components use foreground Material clipping and avoid ink occlusion anti-patterns.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Interactive Ripple & Curved Ink Effect Rules', () {
    test('Rule document exists and is referenced in AGENTS.md', () {
      final ruleFile = File('.agents/rules/interactive_ripple_rules.md');
      final agentsFile = File('.agents/AGENTS.md');

      expect(ruleFile.existsSync(), isTrue,
          reason: 'interactive_ripple_rules.md must exist in .agents/rules/');
      expect(agentsFile.existsSync(), isTrue);

      final agentsContent = agentsFile.readAsStringSync();
      expect(agentsContent.contains('interactive_ripple_rules.md'), isTrue,
          reason: 'AGENTS.md must index interactive_ripple_rules.md');
    });

    test(
        'Zero instances of InkWell directly wrapping an opaque background Container in lib/shared/widgets/',
        () {
      final sharedDir = Directory('lib/shared/widgets');
      final files = sharedDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      // Check for InkWell wrapping a Container that specifies its own background color (directly or via BoxDecoration color)
      final directColorPattern = RegExp(
          r'InkWell\s*\([^)]*child:\s*Container\s*\([^)]*(?<!Border\.all\()color\s*:\s*colors\.',
          dotAll: true);
      final boxDecorationColorPattern = RegExp(
          r'InkWell\s*\([^)]*child:\s*Container\s*\([^)]*decoration:\s*BoxDecoration\s*\([^)]*color\s*:\s*colors\.',
          dotAll: true);

      for (final file in files) {
        final content = file.readAsStringSync();
        final hasDirectColor = directColorPattern.hasMatch(content);
        final hasBoxDecorationColor =
            boxDecorationColorPattern.hasMatch(content);

        expect(
          hasDirectColor || hasBoxDecorationColor,
          isFalse,
          reason:
              '${file.path} has InkWell directly wrapping an opaque Container, which hides ripples behind the widget.',
        );
      }
    });
  });
}
