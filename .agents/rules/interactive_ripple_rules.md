# Interactive Ripple & Curved Ink Effects Rules

This rule module governs the ripple and splash feedback of all interactive UI components across TelStorage, ensuring ripples are always rendered **on top of the surface** and strictly **clipped to curved boundaries** (never square or rendered behind opaque backgrounds).

---

## 🎯 Core Principles

1. **Foreground Surface Rendering**:
   - Interactive components with a solid background must paint the ink splash **on** the surface, not behind it.
   - Never wrap `InkWell` around an opaque `Container(decoration: BoxDecoration(color: ...))` because the container color will paint over and hide the ripple.

2. **Corner Curve & Shape Matching**:
   - Every curved clickable widget must constrain its ripple to the exact `borderRadius` or `shape`.
   - The surface container must specify `clipBehavior: Clip.antiAlias` and matching `borderRadius: BorderRadius.circular(radius)` to prevent square ink bleeds.

3. **Built-in Ripple Widget Configuration**:
   - Built-in ripple widgets (`ListTile`, `ElevatedButton`, `FilledButton`, `OutlinedButton`, `IconButton`) must use explicit rounded shapes (e.g. `RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))` or `CircleBorder()`).
   - When hosted inside cards (`AppSurfaceCard`), the parent card must have `clipBehavior: Clip.antiAlias` so built-in ripples never bleed past the card corners.

---

## 📐 Canonical Code Patterns

### 1. Standard Interactive Curved Surface / Card
```dart
Material(
  color: backgroundColor,
  borderRadius: BorderRadius.circular(radius),
  clipBehavior: Clip.antiAlias,
  child: InkWell(
    onTap: onTap,
    onLongPress: onLongPress,
    borderRadius: BorderRadius.circular(radius),
    child: Padding(
      padding: padding,
      child: content,
    ),
  ),
)
```

### 2. Circular Action Buttons & FABs
```dart
Material(
  color: backgroundColor,
  shape: const CircleBorder(),
  clipBehavior: Clip.antiAlias,
  child: InkWell(
    customBorder: const CircleBorder(),
    onTap: onTap,
    child: SizedBox(
      width: size,
      height: size,
      child: Center(child: icon),
    ),
  ),
)
```

### 3. ListTile in Cards & Drawers
```dart
ListTile(
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  ),
  onTap: onTap,
  // ...
)
```

---

## 🚫 Forbidden Anti-Patterns

| Anti-Pattern | Why It Fails | Correct Solution |
|---|---|---|
| `InkWell(child: Container(color: Colors.blue))` | Solid container paints over ink splash, rendering it on the back side of the app. | Move `color` to `Material(color: Colors.blue, ...)` and place `InkWell` as its child. |
| `GestureDetector(onTap: ..., child: Container(...))` on primary buttons | Provides zero ripple/press visual feedback to user taps. | Use `AppSurfaceCard`, `Material + InkWell`, or standard buttons. |
| `InkWell` without `borderRadius` or `Clip.antiAlias` on curved cards | Ink splash bleeds out into sharp square corners when tapped. | Add `borderRadius: BorderRadius.circular(r)` and `clipBehavior: Clip.antiAlias`. |
