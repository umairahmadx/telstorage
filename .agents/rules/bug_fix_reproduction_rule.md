# Bug Fix Reproduction-First & Test-Driven Discipline Rule

Whenever a bug, defect, or unexpected behavior is reported or given to solve, you MUST adhere to the following strict Red-Before-Green lifecycle:

---

## 1. Zero Production Edits Before Reproduction

- **Never** modify source code in `lib/` to fix a reported bug before demonstrating its failure.
- **Never** jump straight into implementing a fix without a failing automated test case.

---

## 2. Step 1: Write the Reproduction Test Case (RED)

1. Write an automated unit, widget, or integration test in `test/` that mirrors the user's reproduction scenario and triggers the bug through the actual code path.
2. Execute the test (`flutter test <test_path>`).
3. Verify and capture that the test **FAILS** with the exact error, assertion, or incorrect output described in the issue.
4. Show the raw terminal failure output as concrete evidence of reproduction.

---

## 3. Step 2: Show Solution Before Execution

- As per user global rules, explain the root cause and show the proposed production code changes to the user before executing the fix.

---

## 4. Step 3: Implement Minimal Fix (GREEN)

1. Apply the minimal, cleanest fix to the affected files in `lib/` (adhering strictly to the 500-line limit and centralized theming).
2. Re-run the reproduction test (`flutter test <test_path>`).
3. Verify and capture that the test now **PASSES** cleanly.
4. Show the raw terminal passing output as concrete verification.

---

## 5. Step 4: Regression Prevention & Quality Standards

1. Run `flutter test test/architecture/architecture_rules_test.dart` to ensure no files exceed 500 lines and doc comment standards are intact.
2. Run `flutter analyze` to ensure 0 lint or static analysis issues.
3. Run `flutter test` across the full test suite to guarantee zero regressions.
