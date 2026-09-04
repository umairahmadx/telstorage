# Verification, Reporting & Claim Integrity Rules

These rules govern how work is reported, tested, and verified across all bug fixes, features, and refactors. They exist because "it should work" and "it works" are fundamentally different claims, and only demonstrated evidence belongs in completion reports.

---

## 1. Claim Integrity & Verification Levels

Rank every claim honestly using these 4 levels:

1. **Level 1 (Planned)**: A diff or approach described, not yet applied. Say *"planned"*, never *"fixed"*.
2. **Level 2 (Reasoned)**: Traced through code by reading, not running. Say *"should"*, never *"does"*.
3. **Level 3 (Executed, Non-Adversarial)**: Code ran and something passed, but the test did not genuinely exercise or reproduce the bug. Treat as unproven.
4. **Level 4 (Executed, Adversarial, Shown)**: The bug was reproduced failing (**RED**), the fix was applied, and the same test now passes (**GREEN**) through the real production code path, with raw terminal output shown. This is the **ONLY** level that earns the words *"fixed"*, *"verified"*, or *"resolved"*.

Never report a Level 1 or Level 2 claim using Level 4 language. If Level 4 evidence is missing, state exactly what is absent.

---

## 2. Mandatory Red-Before-Green Discipline

- Before touching production code for a bug fix, write a test that fails against the *current* code.
- Exercise the **actual call path** a caller/user hits—never test solely via isolated helper functions with hand-fed arguments.
- Show raw failing output first (**RED**), apply the production fix, then show raw passing output (**GREEN**). A test that only ever ran after the fix proves nothing.

---

## 3. Trace Delegation Across Layers (Don't Assume It)

- Before claiming that fixing File A covers File B, inspect File B's code and verify that B actually delegates to A.
- If File B contains its own independent copy of the logic (e.g. independent UI pre-flight validation vs. ViewModel execution), it requires its own red test and independent fix. Grep alone does not prove delegation—read the call site.

---

## 4. Prove Scope Completeness with Literal Commands

- *"We checked everywhere"* is not evidence.
- Run the literal search command (`grep`, `Select-String`, or `rg`) across the entire repository.
- State the literal command and output, explicitly verifying zero remaining hits in both `lib/` and `test/`.

---

## 5. Full-Suite Execution (Prevent Silent Regressions)

- After applying any fix or updating test mocks, run the **entire test suite** (`flutter test`), not just the modified files.
- Shared mocks, state singletons, and test fixtures are common sources of silent regressions in unrelated tests.

---

## 6. Ban Absolute Language & Acknowledge Residual Risk

- **Banned Words**: Never use *"guaranteed"*, *"100%"*, *"totally"*, *"always works"*, *"never fails"*, or *"impossible to break"* for:
  - OS scheduling / background processes
  - Network conditions / bandwidth throttling
  - Third-party APIs (e.g. Telegram API)
  - Concurrency and race conditions
  - Physical device constraints (OEM battery killers, Doze mode)
- State the specific residual risk instead of asserting there is none.

---

## 7. Simulated Environment vs. Physical Reality

- Unit and widget tests run in a simulated test environment.
- Tests cannot prove real-world Doze-mode survival, OEM background kills, hardware storage corruption, or live network latency.
- When changes touch these areas, explicitly identify the manual/hardware test required, and never conflate *"all tests passed"* with *"verified in production"*.

---

## 8. Multi-Symptom Bug Coverage

- When a bug report lists multiple symptoms (e.g. download folder, export zip, multiselect download), explicitly map **each** symptom to its specific root call site.
- Provide individual red/green verification for each symptom. Do not let one passing path stand in for the rest.

---

## 9. Three-State Report Closures

Every completion report must conclude with one of three explicit states:
- **`Holds up`**: Level 4 evidence achieved, scope completeness verified with literal command, full suite green.
- **`Holds up with a named residual risk`**: State the exact untested condition (e.g., OEM battery management) and why.
- **`Not done yet`**: State exactly what is missing (e.g., missing red run, unverified delegation, scope check).

Do not pad with ambiguous hedging once a fix has legitimately earned `Holds up`.

---

## 10. Parallel Analysis & Test Execution

- When verifying changes, `flutter analyze` and `flutter test` should always be executed concurrently in parallel background tasks rather than sequentially.
- Parallel execution maximizes verification throughput and efficiency.
