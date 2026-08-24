# Coding & Documentation Standards Rules

This document outlines mandatory coding and documentation requirements enforced in TelStorage.

---

## 1. File Length Limit (< 500 Lines)

- **Strict Limit**: No `.dart` file in `lib/` may exceed **500 lines of code** (automated test enforced via `architecture_rules_test.dart`).
- **Refactoring Strategy**:
  - Extract widget sub-trees into `widgets/` folder.
  - Extract dialogs and bottom sheets into `<feature>_dialogs.dart`.
  - Extract complex business logic and helper calculations into domain use cases or utility classes.

---

## 2. Top-Level Library Header Comments

Every `.dart` file (excluding generated `.g.dart` files) MUST begin with a doc header followed by `library;`:

```dart
/// File: <file_name>.dart
/// Description: <Clear explanation of the file's responsibility>
library;

import 'package:flutter/material.dart';
...
```

### Why this format?
1. Satisfies the `slash_for_doc_comments` Dart lint.
2. Satisfies the `dangling_library_doc_comments` Dart lint by attaching the doc comment directly to the library directive.
3. Automatically passes the automated `architecture_rules_test.dart` Rule 2.

---

## 3. Class, Method & Variable Documentation

- **Classes**: Every class and enum must have a single-line or multi-line doc comment (`/// ...`).
- **Methods & Functions**: Every method (public or private) must have a doc comment explaining its purpose, parameters, and return value.
- **Fields & State Variables**: Every class property and state variable must have a doc comment explaining its role.

```dart
/// State controller for file management.
class BrowserViewModel extends Cubit<BrowserState> {
  /// File repository instance.
  final StorageRepository _storageRepo;

  /// Loads directory files for the given [folderId].
  Future<void> loadDirectory({String? folderId}) async {
    ...
  }
}
```

---

## 4. Package Import Conventions

- Always prefer `package:telstorage/...` package imports over deeply nested relative paths (`../../../../...`).
- Group imports logically:
  1. `dart:...` packages
  2. `package:...` 3rd-party packages (Flutter, BLoC, etc.)
  3. `package:telstorage/...` internal packages
