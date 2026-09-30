/*
 * File: global_workflow_rules_test.dart
 * Description: Architecture test enforcing that the global two-step proposal & approval
 * workflow rule exists, stays indexed in AGENTS.md, and retains every mandatory section.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Repo-relative path to the master workflow rule document.
  const String rulePath =
      '.agents/rules/global_proposal_approval_workflow_rules.md';

  /// Repo-relative path to the rules index document.
  const String agentsPath = '.agents/AGENTS.md';

  /// Section headings that must remain present in the master workflow rule.
  const List<String> mandatorySections = <String>[
    '## 1. The Two-Step Workflow (Mandatory Gate)',
    '## 2. Explicit Authorization',
    '## 3. Enterprise-Grade Quality Overrides Fast Completion',
    '## 4. Root-Cause Analysis Is Mandatory',
    '## 5. Mandatory Proposal Structure',
    '## 6. Mandatory Implementation Plan Detail',
    '## 8. Forbidden Behaviors',
    '## 9. Relationship To, and Precedence Over, Other Rule Modules',
    '## 10. Pre-Response Self-Check',
    '## 11. Gate Closure Reporting',
  ];

  group('Global Two-Step Proposal & Approval Workflow Rule', () {
    test('Rule document exists and is referenced in AGENTS.md', () {
      final File ruleFile = File(rulePath);
      final File agentsFile = File(agentsPath);

      expect(ruleFile.existsSync(), isTrue,
          reason: 'global_proposal_approval_workflow_rules.md must exist in '
              '.agents/rules/');
      expect(agentsFile.existsSync(), isTrue);

      final String agentsContent = agentsFile.readAsStringSync();
      expect(agentsContent.contains('global_proposal_approval_workflow_rules.md'),
          isTrue,
          reason: 'AGENTS.md must index the global proposal & approval rule');
    });

    test('AGENTS.md declares the master workflow gate ahead of other modules',
        () {
      final String agentsContent = File(agentsPath).readAsStringSync();
      expect(agentsContent.contains('Master Workflow Gate'), isTrue,
          reason: 'AGENTS.md must surface the workflow gate at the top');

      final int gateIndex = agentsContent.indexOf('Master Workflow Gate');
      final int modulesIndex = agentsContent.indexOf('Rule Modules');
      expect(gateIndex, lessThan(modulesIndex),
          reason: 'The workflow gate must appear before the rule module list');
      expect(agentsContent.contains('Phase 1'), isTrue);
      expect(agentsContent.contains('Phase 2'), isTrue);
    });

    test('Rule document retains all mandatory sections', () {
      final String ruleContent = File(rulePath).readAsStringSync();
      for (final String section in mandatorySections) {
        expect(ruleContent.contains(section), isTrue,
            reason: 'Master workflow rule lost required section: $section');
      }
    });

    test('Rule document mandates the two phases, root cause and a plan', () {
      final String ruleContent = File(rulePath).readAsStringSync();
      expect(ruleContent.contains('Phase 1'), isTrue);
      expect(ruleContent.contains('Phase 2'), isTrue);
      expect(ruleContent.contains('explicit'), isTrue,
          reason: 'The rule must define explicit authorization');
      expect(ruleContent.toLowerCase().contains('root-cause'), isTrue,
          reason: 'The rule must mandate root-cause analysis');
      expect(ruleContent.contains('Implementation Plan'), isTrue,
          reason: 'The rule must mandate a step-by-step implementation plan');
      expect(ruleContent.contains('## 7. Canonical Proposal Template'), isTrue,
          reason: 'The rule must ship a reusable proposal template');
    });

    test('Bug fix rule cross-links the global workflow rule', () {
      final File bugFixRule =
          File('.agents/rules/bug_fix_reproduction_rule.md');
      expect(bugFixRule.existsSync(), isTrue);
      expect(bugFixRule.readAsStringSync()
              .contains('global_proposal_approval_workflow_rules.md'),
          isTrue,
          reason: 'Bug fix rule must point at the canonical workflow gate');
    });
  });
}
