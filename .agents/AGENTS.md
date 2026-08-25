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
