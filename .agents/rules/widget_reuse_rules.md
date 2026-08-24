# Widget Reuse & Zero Redundancy Rules

This document outlines the component reusability guidelines for TelStorage.

---

## 1. Zero Duplicate Widget Implementation

- Never write duplicate UI styling, card containers, dialog structures, or search bars across different screens.
- If a UI pattern appears on **more than one screen**, it MUST be placed in `lib/shared/widgets/`.

---

## 2. Standard Shared Components Catalog (`lib/shared/widgets/`)

| Component | Responsibility |
|---|---|
| `AppSurfaceCard` | Standard container with rounded corners, themed surface color, and optional border/onTap. |
| `AppSearchField` | Standardized rounded search input with prefix icon and text controller. |
| `AppSegmentedControl` | Horizontal pill-style tab/category switcher with animated indicator. |
| `AppDrawer` | Global side drawer for quick navigation, storage metrics, and links. |
| `MobileShell` | Bottom navigation bar shell managing tabs and root navigation state. |
| `FileDetailSheet` | Centralized modal sheet displaying metadata, preview, and actions for a `FileRecord`. |
| `ShareLinkSheet` | Modal bottom sheet for configuring and generating public web share links. |
| `ThumbnailWidget` | Cached image/video/pdf thumbnail loader with fallback category icons. |
| `AppEmptyState` | Standard empty list placeholder with centered icon, title, and subtitle. |
| `AppSectionLabel` | Consistent section header typography. |
| `QrDialog` | Pop-up modal rendering QR codes for web share URLs. |

---

## 3. Creating New Shared Widgets

When adding a new widget to `lib/shared/widgets/`:
1. Ensure it contains **zero hardcoded business logic** (receive callbacks via `VoidCallback` or `ValueChanged<T>`).
2. Add full doc comments (`/// ...`) for the widget class and all constructor properties.
3. Consume colors via `AppColors` or `AppColorsExtension`.
