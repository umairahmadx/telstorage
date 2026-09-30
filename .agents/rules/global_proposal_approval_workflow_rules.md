# Global Two-Step Proposal & Approval Workflow Rule (Master Rule)

This is the **highest-priority process rule** in TelStorage. Every other rule module governs *how* work must be written; this rule governs **whether work may be written at all**. No task — bug fix, feature, refactor, dependency bump, config change, test-only change, or documentation edit — may enter implementation until a written proposal has been delivered and **explicitly approved** by the user. Speed is never a valid justification for skipping this gate.

---

## 1. The Two-Step Workflow (Mandatory Gate)

Every task proceeds through exactly two phases, in this order. The two phases must **never** be merged into a single response, and Phase 2 must never be started speculatively.

| Phase | Name | Allowed Actions | Forbidden Actions |
|---|---|---|---|
| **Phase 1** | Proposal & Approval | Read/search/inspect code, run read-only commands (`flutter analyze`, `flutter test`, logs, `Select-String`/`rg`), author the proposal + implementation plan, ask clarifying questions | Any create/edit/delete in `lib/`, `test/`, `android/`, `ios/`, `backend/`, `docs/`, `pubspec.yaml`; any state-changing command (branch switching, `pub get`, codegen, formatting commits) |
| **Phase 2** | Implementation | Execute the approved plan in the approved order, verify each phase, report evidence | Deviating from approved scope, scope creep, "while I'm here" edits, silent design changes |

- **Hard gate**: Phase 2 is unreachable until the user responds to *this* proposal with explicit authorization (section 2).
- **Phase 1 output is a claim of Level 1 (Planned)** per the Verification & Claim Integrity rules: it must be written in "planned / will" language and must never say "fixed", "done", or "verified".
- If the task is ambiguous, Phase 1 ends with targeted questions instead of code. Under-asking is a violation; over-asking is not.

---

## 2. Explicit Authorization — What Counts and What Does Not

**Counts as authorization:**
1. An unambiguous affirmative reply to the specific proposal: *"approved"*, *"go ahead"*, *"proceed with the plan"*, *"implement it"*, *"yes — do Option B"*.
2. A scope-limited approval: *"implement steps 1–3 only"* → implement exactly steps 1–3, then return to Phase 1 for the remainder.
3. A direct instruction in the same turn that explicitly waives the gate (e.g. *"implement this immediately without a proposal"*). The waiver applies to that turn's task only.

**Does NOT count as authorization:**
1. Silence, or a reply that only adds new requirements or asks questions.
2. *"Continue"* after a proposal that was cut off mid-delivery — that means finish the **proposal**, not start editing.
3. The existence of the original request. A report that X is broken is a request for a **proposal** to fix X, not permission to edit X.
4. Approval granted earlier for a different task. There is no blanket or standing approval.
5. Anything inferred from tone, urgency, or frustration.

**Approval expiry (re-proposal required):** if during Phase 2 the approved design proves infeasible, incomplete, or wrong — a new file must be touched, a public contract must change, a dependency must be added, or a step must be replaced — **stop immediately**, return to Phase 1, re-propose the delta, and wait for authorization again. Continuing under stale approval is treated as an unauthorized edit.

---

## 3. Enterprise-Grade Quality Overrides Fast Completion

- **Tie-breaker rule**: whenever quality and speed conflict, the **enterprise-grade, long-term-stable** option wins — even when it takes longer, touches more files, or demands more verification.
- Proposals that win by being faster but weaker are rejected as if they had been written badly. The following are banned *inside* a proposal:
  1. `TODO`/`FIXME` or placeholder implementations standing in for real logic.
  2. Keeping commented-out or parallel legacy code "just in case" (see Coding Standards section 5).
  3. A patch that masks a symptom instead of removing the mechanism that produced it.
  4. Hardcoded colors, magic numbers, or copy that belong in `AppColors`, constants, or domain config.
  5. Duplicating a widget/state/empty-state instead of extending a shared component (see Widget Reuse rules).
  6. Skipping or shrinking the failing-test-first step to reach green more quickly.
  7. "We'll harden it in a later PR" for hardening that belongs to the fix — that work must be a numbered step **inside** the approved plan.
- **Long-term lens is mandatory**: every proposal states how the solution behaves for the next maintainer, at 10× data volume, under offline/network-flaky conditions, and against the Telegram backend failure modes.
- **Scope discipline still applies**: enterprise quality does not license speculative rewrites. Minimal change that *fully* removes the root cause is the target, and each touched file must be justified in one line.

---

## 4. Root-Cause Analysis Is Mandatory (Symptoms Are Not the Problem)

A proposal that describes only the symptom is not a proposal. Phase 1 must contain a root-cause analysis that reaches the **mechanism** level:

1. **Observed behavior** - stated exactly, with the literal error text, log line, or failing output.
2. **Expected behavior** - and the source of that expectation (spec, rule module, user statement, existing test).
3. **Reproduction evidence** - the read-only command/test run that demonstrates the failure today, with raw output. Reason-only claims are Claim Integrity Level 2 and must be labeled as such.
4. **Causal chain** - trace from the user-visible symptom back to the earliest point where system state was still correct. Ask "why" at least 5 times, or until you reach an invariant that **no test, type, or rule currently protects**.
5. **Root-cause statement** - one sentence naming the concrete defect class: the missing guard, wrong assumption, unenforced invariant, lifecycle/ownership flaw, race window, or missing normalization step.
6. **Why it survived** - the specific missing test, missing architecture guard, or missing documentation that allowed it to ship and stay shipped.
7. **Structural prevention** - how the proposed design makes the same class of defect *impossible or immediately loud*, not merely how it removes this instance.
8. **Scope evidence** - the literal repo-wide search command (`Select-String`/`rg`) across `lib/` and `test/` proving **every** call site sharing the same flawed pattern was enumerated, not just the reported one.

If the root cause cannot be established with the available evidence, the Phase 1 deliverable is an **investigation plan** (instrumentation, targeted logging, reproduction steps) - implementation remains forbidden until the cause is named.

---

## 5. Mandatory Proposal Structure (Sections A-I)

Every Phase 1 response uses these headings, in this order. A section that truly does not apply must be written as `N/A - <reason>`; silently dropping a section is a violation.

| Section | Name | Must Contain |
|---|---|---|
| **A** | Problem & Evidence | Observed vs. expected behavior, literal repro output, affected platforms/users |
| **B** | Root-Cause Analysis | The section-4 causal chain, one-sentence root cause, why it survived |
| **C** | Options Considered | 2+ realistic options where they exist (including the workaround and the do-nothing option), each with trade-offs and an explicit rejection reason |
| **D** | Recommended Solution & Design | Architecture and data flow, affected layers (UI / ViewModel / domain / data), contracts or interfaces introduced or changed, why this is the enterprise-grade choice, scalability and limits |
| **E** | Regression Prevention | The RED test(s) to be written first, invariant/architecture tests to add, diagnostics/observability to expose, documentation and rule-index updates |
| **F** | Impact & Blast Radius | Files/modules touched, public API and state changes, storage/Hive migrations, performance and RAM ceilings, offline and Telegram failure-mode behavior |
| **G** | Risks & Residual Risks | Concrete risks and the named residual risk that will remain untested; the banned absolute language from the Verification rules applies here |
| **H** | Rollout, Verification & Rollback | Ordered phases with the exact verification command per phase, feature-gating or safe-publish strategy, rollback path, manual/device tests still required |
| **I** | Definition of Done | Explicit acceptance criteria, the tests that must be green, and the closure state that will be reported |

---

## 6. Mandatory Implementation Plan Detail

Section D must be followed by a numbered, ordered, dependency-aware **implementation plan**. Every step declares:

1. **Step id and goal** - e.g. `Step 1 - Reproduce the defect as a failing test`.
2. **Exact files** - repo-relative paths created, modified, or deleted.
3. **Concrete change** - what actually changes in that file; "update the logic" and "fix the handling" are not descriptions.
4. **Verification** - the command executed after the step and the evidence expected from it (`flutter test test/...` expecting GREEN, `flutter analyze` expecting 0 issues, etc.).
5. **Blocking relationship** - which later steps cannot start until this one is verified.

Non-negotiable ordering:
- **Step 1 of any bug-fix plan is the failing (RED) reproduction test.** Writing test files is itself an implementation act, so it happens in Phase 2 as approved step 1 - never silently during Phase 1.
- Production edits follow in dependency order (domain/data before ViewModel before UI), each bounded by the 500-line file limit and the theming/widget-reuse rules.
- **The final step is always** full-suite verification (`flutter analyze` and `flutter test` run concurrently, per the Verification rules) plus the three-state closure report.
- Include estimated effort per phase and identify rollback points where the tree is left green.

---

## 7. Canonical Proposal Template

Copy this skeleton into the Phase 1 response and fill it in:

```markdown
## Proposal - <task title>  (Status: PLANNED - awaiting approval, no files changed)

### A. Problem & Evidence
### B. Root-Cause Analysis
### C. Options Considered
| Option | Effort | Trade-offs | Verdict |
### D. Recommended Solution & Design
### E. Regression Prevention
### F. Impact & Blast Radius
### G. Risks & Residual Risks
### H. Rollout, Verification & Rollback
### I. Definition of Done

## Implementation Plan
| # | Goal | Files | Concrete Change | Verification | Blocked By |
|---|---|---|---|---|---|
| 1 | RED reproduction test | test/... | ... | flutter test ... (expect FAIL) | - |
| 2 | ... | ... | ... | ... | 1 |

**Reply "approved" (or scope it, e.g. "steps 1-3 only") and I will begin implementation. Nothing has been changed yet.**
```

---

## 8. Forbidden Behaviors (Anti-Patterns)

| Anti-Pattern | Why It Is Forbidden | Required Behavior |
|---|---|---|
| Delivering a proposal and the code changes in the same response | Destroys the approval gate; the user reviews a fait accompli | Stop at the end of the proposal and wait |
| Editing files while "just drafting" the proposal | Writes are Phase 2 actions | Read-only tools only in Phase 1 |
| Asking "shall I proceed?" *after* already applying the edit | The question is decorative, not a gate | Revert, propose, wait |
| Vague plan ("refactor the service, then test it") | Not auditable, cannot be approved meaningfully | Per-step files, concrete changes, verification commands (section 6) |
| Symptom patch presented as a root-cause fix | Guarantees the defect class recurs | Section 4 depth bar |
| Choosing the shortcut because it is faster | Violates the quality-over-speed tie-breaker | Section 3 |
| Treating approval of a prior task as standing approval | Approvals are per-proposal | Seek approval for each proposal |
| Quietly expanding scope mid-implementation | Invalidates the approval | Stop and re-propose the delta (section 2, approval expiry) |
| Reporting the plan as "fixed/done/verified" | Claim Integrity Level 1 dressed up as Level 4 | "Planned" language until Level 4 evidence exists |

---

## 9. Relationship To, and Precedence Over, Other Rule Modules

1. **Precedence**: this rule outranks every other rule module on the question of *when* edits may occur. If another module appears to demand an immediate edit, the gate still holds and that module is satisfied inside Phase 2.
2. **Bug Fix Reproduction-First, section 3** ("show solution before execution") is the narrow form of this rule; this document is its canonical definition. The RED test is step 1 of the approved plan, which satisfies that rule's "reproduce before production edits" requirement.
3. **Verification, Reporting & Claim Integrity, section 1**: a proposal is a Level 1 claim; the three-state closure report is Phase 2's final artifact.
4. **Folder Structure, Coding Standards, Theming, Widget Reuse, Error Handling, Security, Performance, Ripple** modules constrain *what* the approved solution looks like; the proposal must state compliance with each module it touches.
5. Only an explicit user instruction can relax this gate, and only for the turn in which it is given.

---

## 10. Pre-Response Self-Check (Run Before Every Reply)

1. Which phase am I in for this task, and what artifact proves it (proposal delivered? approval quoted?).
2. Did any write/edit tool touch repository files during a Phase 1 turn? If yes, that is a violation - revert and re-propose.
3. Does the proposal contain sections A-I plus the per-step implementation plan, with no dropped headings?
4. Does the root-cause section name a mechanism, not a symptom?
5. Did I keep Level 1 ("planned") language throughout the proposal?
6. Has anything materially deviated from the approved plan? If yes, return to Phase 1 before continuing.
7. Am I unsure whether approval was given? Then ask; do not implement.

---

## 11. Gate Closure Reporting

The final Phase 2 report must:
1. State which user authorization unlocked the work (quote or paraphrase it).
2. Record every deviation from the approved plan and whether re-approval was requested for it.
3. Close with one of the three states defined by the Verification rules: `Holds up`, `Holds up with a named residual risk`, or `Not done yet`.
4. Confirm that the rule index (`.agents/AGENTS.md`) and any affected documentation were updated when behavior or rules changed.
