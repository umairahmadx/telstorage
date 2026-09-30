# TelStorage Agent & Engineering Rules Index

Welcome to the TelStorage project rules repository. These rules govern engineering workflow, code architecture, quality, theming, documentation, and resilience across the codebase.

---

## ⚙️ Master Workflow Gate (Read First)

**Every task in this repository is gated by the [Global Two-Step Proposal & Approval Workflow Rule](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/global_proposal_approval_workflow_rules.md).**

1. **Phase 1 - Propose**: deliver a comprehensive solution built on mechanism-level root-cause analysis, plus a step-by-step implementation plan with per-step verification. Then **stop**. Read-only inspection only; no file may be created, edited, or deleted.
2. **Phase 2 - Implement**: only after **explicit user authorization** to that proposal, execute the approved plan exactly, verify it, and report evidence.

Enterprise-grade quality and long-term stability always outrank fast completion, and every proposal must include the regression prevention and prevention-of-recurrence plan, not just the immediate fix. No other rule module authorizes skipping this gate.

---

## 📚 Rule Modules

1. [**Folder Structure & Architecture Rules**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/folder_structure_rules.md)
   - How and when features, screen directories, viewmodels, and `widgets/` folders must be created.
   - Clean separation of UI, ViewModel, Domain, and Data layers.

2. [**Coding & Documentation Standards**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/coding_standards_rules.md)
   - Strict 500-line file limit (test-enforced).
   - Top-level multiline doc comments (`/* ... */`).
   - Class, method, and variable documentation standards.

3. [**Centralized Colors & Theming**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/theme_colors_rules.md)
   - Zero hardcoded colors in UI widgets.
   - Centralized `AppColors` and `AppColorsExtension` design tokens.

4. [**Widget Reuse & Shared Components**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/widget_reuse_rules.md)
   - Zero widget redundancy.
   - Catalog of standard `lib/shared/widgets/` components.

5. [**Error Handling, Resilience & KISS**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/error_handling_resilience_rules.md)
   - `Result<T>` pattern for all asynchronous operations.
   - Graceful fallback UI on offline/error states.
   - Resilient background queues with retry/backoff.

6. [**Interactive Ripple & Curved Ink Effects**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/interactive_ripple_rules.md)
   - Foreground surface ink ripples with `Clip.antiAlias`.
   - Matching `borderRadius` and `CircleBorder` on curved and circular buttons/cards.
   - Proper shaping for widgets with built-in ripples (`ListTile`, `ElevatedButton`, `FilledButton`, `IconButton`).

7. [**Verification, Reporting & Claim Integrity Rules**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/verification_reporting_rules.md)
   - 4-Level Claim Integrity framework (Planned, Reasoned, Executed Non-Adversarial, Executed Adversarial Shown).
   - Mandatory Red-before-Green discipline through actual caller entry points.
   - Delegation verification (UI preflight vs. ViewModel execution).
   - Repo-wide search scope evidence with literal commands.
   - Full test suite execution and ban on absolute language.
   - Explicit 3-state closure reports (`Holds up`, `Holds up with a named residual risk`, `Not done yet`).
   - Parallel background execution of `flutter analyze` and `flutter test`.

8. [**Security, Data Integrity & Telegram Architecture Rules**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/security_data_integrity_rules.md)
   - Zero secret/payload logging and `.gitignore` credential hygiene.
   - Handling Telegram backend failure modes (token revocation, flood waits/429, invalid message IDs).
   - Chunk manifest verification passes and SHA-256 digest validation.

9. [**Performance, Concurrency & Observability Rules**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/performance_observability_rules.md)
   - Bounded transfer concurrency limits (uploads + downloads combined).
   - Streaming memory ceiling vs. full file RAM buffering for chunking/zipping pipelines.
   - Background queue worker inspectable state (active task, stage, last error, progress) and diagnostics.

10. [**Bug Fix Reproduction-First Rule**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/bug_fix_reproduction_rule.md)
    - Mandatory automated reproduction test (RED) before touching production code.
    - Raw terminal failure output shown before applying the fix.
    - Verified passing output (GREEN) after fix, followed by full regression test run.

11. [**Global Two-Step Proposal & Approval Workflow Rule (Master Rule)**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/global_proposal_approval_workflow_rules.md)
    - Two-phase gate: propose a comprehensive, root-cause-driven solution first, then implement only after explicit user authorization.
    - Definition of what counts (and does not count) as explicit approval, including approval expiry when the approved design changes.
    - Enterprise-grade quality and long-term stability always take precedence over fast completion.
    - Mechanism-level root-cause analysis bar: symptoms are never accepted as the problem, plus why it survived and how recurrence is blocked.
    - Mandatory proposal sections A-I and a numbered, dependency-aware implementation plan with per-step verification.
    - Canonical proposal template, forbidden workflow anti-patterns, precedence over all other rule modules, and a pre-response self-check.
    - Guarded by `test/architecture/global_workflow_rules_test.dart`.

