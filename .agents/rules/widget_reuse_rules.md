# Widget Reuse & Zero Redundancy Rules

This document outlines mandatory component reusability guidelines and the centralized shared widget catalog in TelStorage.

---

## 1. Zero Duplicate Widget Policy

- **Strict Mandate**: Never define duplicate UI styling, tile layouts, card containers, dialog structures, or empty states inside local feature directories.
- If a UI pattern appears on **more than one screen**, or is a standard UI element (such as a file tile, folder tile, status badge, action card, or empty state), it MUST be placed in `lib/shared/widgets/`.
- No feature screen in `lib/features/` may define its own custom file list tile, folder tile, or empty state. All features must consume components from `lib/shared/widgets/shared_widgets.dart`.

---

## 2. Master Shared Components Catalog (`lib/shared/widgets/`)

| Category | Component | Responsibility |
|---|---|---|
| **Tiles** | `AppFileTile` | Standard file list item with thumbnail, title, size/date, selection checkbox, and trailing action/menu. |
| | `AppFileGridTile` | Standard file grid card with thumbnail, title, size, and selection state. |
| | `AppFolderTile` | Standard folder item with folder icon, title, and item count badge. |
| | `AppTransferTile` | Active upload / download progress tile with speed indicator and progress bar. |
| **Cards** | `AppSurfaceCard` | Base card container with rounded corners, themed background, and optional border/onTap. |
| | `AppActionCard` | Standard interactive card with leading icon container, title, subtitle, and trailing widget. |
| **User** | `AppUserAvatar` | Reusable user avatar with initials, border, and optional sync/online status dot. |
| **Badges** | `AppStatusBadge` | Standardized status pill with icon, label, and accent border. |
| | `AppSectionLabel` | Consistent section header typography. |
| **Bars** | `AppBatchActionBar` | Bottom floating action bar for batch operations (copy, move, delete, clear). |
| **Dialogs** | `FileDetailSheet` | Centralized 'About File' modal sheet with preview, metadata, and full actions. |
| | `AppSortFilterSheet` | Centralized sort and filter modal bottom sheet. |
| | `AppDialogs` | Centralized static helper for confirmation (`showConfirm`), input (`showInput`), and details (`showFileDetail`). |
| | `ShareLinkSheet` | Modal bottom sheet for configuring and generating public web share links. |
| | `QrDialog` | Pop-up modal rendering QR codes for web share URLs. |
| **Feedback** | `AppEmptyState` | Standard empty list placeholder with centered icon, title, subtitle, and optional CTA button. |
| **Inputs** | `AppSearchField` | Standardized rounded search input with prefix icon and text controller. |
| | `AppSegmentedControl` | Horizontal pill-style category switcher with animated indicator. |
| **Media** | `ThumbnailWidget` | 400px WebP cached thumbnail loader with universal smart badging. |
| **Navigation** | `AppDrawer` | Global side drawer for navigation and profile info. |
| | `MobileShell` | Bottom navigation bar shell managing root tabs. |

---

## 3. Creating and Consuming Shared Widgets

1. **Clean Separation**: Shared widgets must contain zero hardcoded feature-specific business logic (receive callbacks via `VoidCallback` or `ValueChanged<T>`).
2. **Documentation**: Every widget must have a clean `/* ... */` header comment and doc comments (`/// ...`) for all constructor properties.
3. **Theming**: Consume colors strictly via `AppColors` or `AppColorsExtension`. Never use hardcoded raw colors.
4. **Single Import**: Use `import 'package:telstorage/shared/widgets/shared_widgets.dart';` for clean access.
