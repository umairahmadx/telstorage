# TelStorage Agent & Engineering Rules Index

Welcome to the TelStorage project rules repository. These rules govern code architecture, quality, theming, documentation, and resilience across the codebase.

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

8. [**Security, Data Integrity & Telegram Architecture Rules**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/security_data_integrity_rules.md)
   - Zero secret/payload logging and `.gitignore` credential hygiene.
   - Handling Telegram backend failure modes (token revocation, flood waits/429, invalid message IDs).
   - Chunk manifest verification passes and SHA-256 digest validation.

9. [**Performance, Concurrency & Observability Rules**](file:///c:/Users/umair-dell/StudioProjects/telstorage/.agents/rules/performance_observability_rules.md)
   - Bounded transfer concurrency limits (uploads + downloads combined).
   - Streaming memory ceiling vs. full file RAM buffering for chunking/zipping pipelines.
   - Background queue worker inspectable state (active task, stage, last error, progress) and diagnostics.


