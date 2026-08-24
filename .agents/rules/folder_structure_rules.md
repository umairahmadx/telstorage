# Folder Structure & Architecture Rules

This document outlines the strict guidelines for how, where, and when directories and folders must be created in the TelStorage codebase.

---

## 1. Top-Level Directory Layout

```
lib/
├── app.dart               # Top-level MaterialApp and root configuration
├── main.dart              # Application entrypoint & initialization
├── core/                  # Shared domain-agnostic foundation & global services
├── features/              # Feature-first domain modules
└── shared/                # Shared reusable UI elements, dialogs, and navigation shell
```

---

## 2. Feature-First Folder Rules (`lib/features/<feature>/`)

### When to create a new Feature Folder:
Create a new feature folder inside `lib/features/` whenever implementing a distinct domain boundary or major user capability (e.g., `auth`, `browser`, `downloads`, `home`, `settings`, `sync`, `upload`).

### Feature Directory Structure:
```
lib/features/<feature_name>/
├── data/                  # Optional: API clients, data sources, repository implementations
│   └── repositories/
├── domain/                # Optional: Domain entity models, repository contracts, use cases
│   ├── repositories/
│   └── usecases/
└── presentation/          # Mandatory for UI features
    ├── screens/           # Dedicated screen directories
    └── viewmodels/        # Feature-level ViewModels (Bloc / Cubit) if shared across screens
```

---

## 3. Screen Folder Rules (`presentation/screens/<screen_name>/`)

### When and How Screen Folders MUST be Created:
- **Mandatory Subdirectory Rule**: Every screen widget MUST reside in its OWN dedicated subdirectory under `presentation/screens/<screen_name>/`.
  - ✅ **Correct**: `lib/features/settings/presentation/screens/storage_details/storage_details_screen.dart`
  - ❌ **Forbidden**: `lib/features/settings/presentation/screens/storage_details_screen.dart` (Bare file directly in `screens/`).

### Screen Internal Structure:
```
lib/features/<feature>/presentation/screens/<screen_name>/
├── <screen_name>_screen.dart     # Primary screen widget (StatelessWidget or StatefulWidget)
├── viewmodel/                    # Dedicated ViewModel if scoped to this screen
│   ├── <name>_view_model.dart    # Cubit or Bloc
│   ├── <name>_event.dart         # Bloc events (if using Bloc)
│   └── <name>_state.dart         # Immutable state model
└── widgets/                      # Screen-private widgets, dialogs, and sheets
    ├── <name>_dialogs.dart       # Extracted alert/bottom sheet dialogs
    └── <name>_card.dart          # Extracted UI section components
```

### When to create `widgets/` inside a Screen Folder:
1. **Screen length threshold**: When a screen file exceeds **300 lines of code**, extract logical sub-trees into separate files inside `widgets/`.
2. **Dialog & Sheet Extraction**: All modals, bottom sheets, and confirmation dialogs must be extracted to `widgets/<screen>_dialogs.dart` or dedicated widget files.
3. **Screen-Specific Scope**: Components that are ONLY used within this specific screen belong in this `widgets/` folder.

---

## 4. Shared Reusable Widgets (`lib/shared/widgets/`)

### When to place a widget in `lib/shared/widgets/`:
1. **Multi-screen reuse**: The widget is used (or intended to be used) across **2 or more screens** (e.g., `AppSurfaceCard`, `AppSearchField`, `AppSegmentedControl`, `FileDetailSheet`, `ShareLinkSheet`, `ThumbnailWidget`).
2. **Global Navigation Shells**: High-level app shell containers (`MobileShell`, `AppDrawer`, navigation bars).
3. **Design System Primitives**: Any custom base element that provides standard styling, borders, or haptics across the entire app.

---

## 5. Core Foundation Layout (`lib/core/`)

```
lib/core/
├── constants/             # Global constant values
├── errors/                # Result<T>, Failure, and error classes
├── events/                # Domain event bus
├── models/                # Global models (FileRecord, FolderRecord, DownloadJob)
├── navigation/            # Navigation intents and route arguments
├── routing/               # AppRouter and route definitions
├── services/              # Global singleton services (HiveService, TelegramService, etc.)
├── theme/                 # Centralized AppColors, AppTheme, and AppIcons
└── utils/                 # Platform-specific utilities, loggers, and helpers
```
