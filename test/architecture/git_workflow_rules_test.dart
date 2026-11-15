/*
 * File: git_workflow_rules_test.dart
 * Description: Architecture test enforcing that the Git Branching, Pull Request &
 * Repository Hygiene rule exists, stays indexed in AGENTS.md, and retains all mandatory sections.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Repo-relative path to the git workflow rule document.
  const String rulePath =
      '.agents/rules/git_workflow_branch_pr_hygiene_rules.md';

  /// Repo-relative path to the rules index document.
  const String agentsPath = '.agents/AGENTS.md';

  /// Section headings that must remain present in the git workflow rule.
  const List<String> mandatorySections = <String>[
    '## 1. Direct Commits to `main` Are Strictly Forbidden',
    '## 2. Post-Verification Branch Creation',
    '## 3. Conventional Commit Discipline',
    '## 4. Push & Pull Request Creation (Squash-and-Merge Convention)',
    '## 5. Post-Merge Cleanup & Main Synchronization',
    '## 6. Repository Single-Branch Invariant',
  ];

  group('Git Branching, Pull Request & Repository Hygiene Rule', () {
    test('Rule document exists and is referenced in AGENTS.md', () {
      final File ruleFile = File(rulePath);
      final File agentsFile = File(agentsPath);

      expect(ruleFile.existsSync(), isTrue,
          reason: 'git_workflow_branch_pr_hygiene_rules.md must exist in '
              '.agents/rules/');
      expect(agentsFile.existsSync(), isTrue);

      final String agentsContent = agentsFile.readAsStringSync();
      expect(
        agentsContent.contains('git_workflow_branch_pr_hygiene_rules.md'),
        isTrue,
        reason: 'AGENTS.md must index the git workflow rule',
      );
    });

    test('AGENTS.md indexes Rule 12 with mandatory guidelines', () {
      final String agentsContent = File(agentsPath).readAsStringSync();
      expect(
        agentsContent.contains('Git Branching, Pull Request & Repository Hygiene Rules'),
        isTrue,
        reason: 'AGENTS.md must surface the Git branching rule title',
      );
      expect(
        agentsContent.contains('Zero direct commits to `main`'),
        isTrue,
        reason: 'AGENTS.md must state prohibition of direct main commits',
      );
      expect(
        agentsContent.contains('Squash-and-Merge'),
        isTrue,
        reason: 'AGENTS.md must mandate squash-and-merge policy',
      );
    });

    test('Rule document retains all mandatory sections', () {
      final String ruleContent = File(rulePath).readAsStringSync();
      for (final String section in mandatorySections) {
        expect(ruleContent.contains(section), isTrue,
            reason: 'Git workflow rule lost required section: $section');
      }
    });

    test('Rule document mandates squash-and-merge and single-branch invariant',
        () {
      final String ruleContent = File(rulePath).readAsStringSync();
      expect(ruleContent.contains('Squash and merge'), isTrue);
      expect(ruleContent.contains('Single-Branch Invariant'), isTrue);
      expect(ruleContent.contains('git fetch origin --prune'), isTrue);
      expect(ruleContent.contains('git checkout main'), isTrue);
    });
  });
}
