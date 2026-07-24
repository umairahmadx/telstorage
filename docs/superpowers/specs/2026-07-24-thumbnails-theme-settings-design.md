# Media Thumbnails, Theme Color Singleton & Redesigned Settings Screen Design Spec

**Date**: 2026-07-24  
**Status**: Approved by User  
**Target Platform**: Flutter (Cross-platform: Web & Mobile)

---

## 1. Executive Summary

This design specification outlines three major enhancements to TelStorage:
1. **Unified Media Thumbnail Pipeline**: Streamlining thumbnail generation and Telegram cloud upload for Images, Videos, and PDFs so that all media types share a single, reliable upload path (`thumb_$fileId.<ext>`) and metadata binding.
2. **Centralized Color Singleton & Theme Test Suite**: Guaranteeing 100% theme compliance across the codebase (`lib/`) using `AppTheme` and `AppColorsExtension` as the single canonical source of truth for both Light and Dark modes. Automated tests enforce zero hardcoded colors in `lib/` and verify token completeness for all theme modes.
3. **Card-Based Control Center (Remade Settings Screen)**: Re-architecting `SettingsScreen` (the More tab) into a modern, card-based control center built strictly with theme tokens, featuring profile management, Telegram cloud storage analytics (with web share quota removed), appearance controls, app tools, and a styled log out action.

---

## 2. Architecture & Detailed Specifications

### Component 1: Unified Media Thumbnail Pipeline

#### Data Model (`ThumbnailResult`)
```dart
class ThumbnailResult {
  final Uint8List bytes;
  final String extension; // 'jpg' for images/videos, 'png' for PDFs
  const ThumbnailResult(this.bytes, this.extension);
}
```

#### Dispatcher Logic (`ThumbnailGenerator`)
- `ThumbnailGenerator.generate({required Uint8List bytes, required String filename, required String mimeType})`:
  - **Image (`image/`)**: Resizes image to target max dimension ($150\text{px}$) PNG/JPEG bytes via Flutter codec.
  - **Video (`video/`)**: Extracts a thumbnail frame using `VideoThumbnail.thumbnailData` with temp file cleanup.
  - **PDF (`application/pdf`)**: Renders page 1 to PNG bytes using `PdfDocument.openData`.
  - **Error Handling**: Catches exceptions per format and logs warnings gracefully, returning `null` if thumbnail generation is unsupported or fails, ensuring file upload is never blocked.

#### Upload Integration (`UploadService` & `WebShareQueueService`)
In `UploadService.uploadFile()`:
```dart
final thumbResult = await ThumbnailGenerator.generate(
  bytes: bytes,
  filename: name,
  mimeType: mimeType,
);

if (thumbResult != null) {
  internalOnProgress(0.10, 'Uploading thumbnail…');
  final uploaded = await _telegram.uploadBytesWithFileId(
    thumbResult.bytes,
    'thumb_${fileId}.${thumbResult.extension}',
  );
  thumbnailFileId = uploaded['file_id'] as String;
}
```
- The returned `thumbnailFileId` is saved in `fileMeta['thumbnail_file_id']` and written to local Hive storage and Telegram index JSON.
- `ThumbnailRepository` and `ThumbnailWidget` consume `thumbnailFileId` to download, cache, and display thumbnails across list and grid views for image, video, and PDF files.

---

### Component 2: Color Singleton & Theme Test Suite

#### 1. Centralized Color Tokens (`AppTheme` & `AppColorsExtension`)
- Location: `lib/core/theme/app_theme.dart`.
- Defines all static color constants and ThemeExtensions (`AppColorsExtension`) for Light and Dark themes.
- Replaces any ad-hoc hardcoded color fallbacks across `lib/` (e.g. replacing raw `Colors.green` in `home_screen.dart` with `colors.success`).

#### 2. Test Suite Specifications (`test/`)
1. **`test/no_hardcoded_colors_test.dart`**:
   - Scans all `.dart` files under `lib/` (excluding `lib/core/theme/app_theme.dart`).
   - Uses RegExp matching for `Colors.<name>` (excluding `Colors.transparent`), `Color(0x...)`, `Color.fromARGB(...)`, and `Color.fromRGBO(...)`.
   - Fails if any hardcoded visual color exists in widget/screen code.
2. **`test/theme_colors_test.dart`** (New):
   - Instantiates `AppTheme.light()` and `AppTheme.dark()`.
   - Asserts that both ThemeData instances have non-null `AppColorsExtension`.
   - Asserts that all color token properties (`bgPrimary`, `bgSurface`, `borderSubtle`, `textPrimary`, `filePdf`, `fileVideo`, `success`, `error`, `warning`, etc.) are non-null for both modes.

---

### Component 3: Remade Settings Screen (Card-Based Control Center)

#### Architecture (MVVM)
- **View (`SettingsScreen`)**: Modular, theme-aware Flutter screen.
- **ViewModel (`HomeCubit` & `ThemeService`)**: Manages profile data, Telegram cloud storage used MB, and reactive theme mode changes.

#### Section Cards Layout
1. **Profile Control Card**:
   - User initial avatar badge inside a circular themed container.
   - User name, email, and "Connected to Telegram Cloud" status tag.
2. **Telegram Cloud Storage Analytics Card**:
   - `XX MB / Unlimited` storage indicator.
   - Animated visual progress bar indicating storage usage derived from `storageUsedMb`.
   - *Note: Web Share Quota has been explicitly removed as requested.*
3. **Appearance Card**:
   - Interactive 3-option segmented pill toggle (`Light` | `Dark` | `System`).
   - Reactive update via `ThemeService.instance.setThemeMode(...)`.
4. **App Tools & Preferences Card**:
   - Action tiles: **Clear Thumbnail Cache**, **Public Web Shares**, **About App (v1.0.0)**.
5. **Account & Log Out Danger Card**:
   - Styled danger tile using `colors.error` token.
   - Triggers `AuthService.instance.logout()` after user confirmation dialog.

---

## 3. Verification Plan

### Automated Tests
- Run `flutter test test/no_hardcoded_colors_test.dart` to verify zero hardcoded color references outside `app_theme.dart`.
- Run `flutter test test/theme_colors_test.dart` to verify Light and Dark theme token completeness.
- Run `flutter test` to ensure all existing widget/unit tests pass without errors.

### Manual Verification
- Test uploading Image, Video, and PDF files and verify thumbnail generation logs, Telegram thumbnail upload messages, and list/grid thumbnail rendering in `ThumbnailWidget`.
- Test Settings Screen in both Light Mode and Dark Mode to verify contrast, card layouts, theme switching, storage metrics display, and log out functionality.
