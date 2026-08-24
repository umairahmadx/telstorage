# Centralized Colors & Theme Rules

This document outlines the strict styling, color token, and theming standards for TelStorage.

---

## 1. Zero Hardcoded Colors Rule

- **Strict Enforcement**: Raw hex color literals (e.g. `Color(0xFF4A6CF7)`) and standard Flutter color constants (e.g. `Colors.blue`, `Colors.grey`) are **strictly prohibited** in all UI screen and widget files.
- **Automated Validation**: Enforced by `test/architecture/architecture_rules_test.dart` (Rule 3).

---

## 2. Centralized Palette (`AppColors`)

All color constants must be defined in `lib/core/theme/app_colors.dart`:
- **Grayscale / Surfaces**: `AppColors.black`, `AppColors.white`, `AppColors.grey900`..`grey50`.
- **Navy Dark Surfaces**: `AppColors.navy900`..`navy600`.
- **Brand / Accents**: `AppColors.primary`, `AppColors.primaryLight`, `AppColors.accent`, `AppColors.success`, `AppColors.error`, `AppColors.warning`.
- **File Badge Badges**: `AppColors.filePdf`, `AppColors.fileVideo`, `AppColors.fileZip`, `AppColors.fileText`, etc.

---

## 3. Dynamic Theme Tokens (`AppColorsExtension`)

UI widgets that adapt dynamically to Light and Dark themes MUST consume colors through `Theme.of(context).extension<AppColorsExtension>()!`:

```dart
final colors = Theme.of(context).extension<AppColorsExtension>()!;

Container(
  color: colors.bgSurface,
  decoration: BoxDecoration(
    border: Border.all(color: colors.borderSubtle),
  ),
  child: Text(
    'Title',
    style: TextStyle(color: colors.textPrimary),
  ),
)
```
