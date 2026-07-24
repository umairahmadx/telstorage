# Media Thumbnails, Theme Color Singleton & Redesigned Settings Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Streamline Image, Video, and PDF thumbnail generation/upload; enforce a 100% hardcoded-color-free theme color singleton with unit tests; and redesign `SettingsScreen` into a modern Card-Based Control Center.

**Architecture:** 
- `ThumbnailGenerator` exposes a unified dispatcher for images, videos, and PDFs returning `ThumbnailResult?`. `UploadService` uses this to upload `thumb_$fileId.<ext>` to Telegram metadata.
- Centralize all visual colors in `AppTheme` / `AppColorsExtension`. Enhance `no_hardcoded_colors_test.dart` and add `theme_colors_test.dart` to verify Light & Dark mode token completeness.
- Re-architect `SettingsScreen` into modular, theme-tokenized cards (Profile, Storage Analytics, Appearance, App Tools, Log Out).

**Tech Stack:** Flutter, Dart, BLoC / Cubit, `pdfx`, `get_thumbnail_video`, `flutter_test`.

## Global Constraints
- All visual colors must be defined in `lib/core/theme/app_theme.dart` and accessed via `Theme.of(context).extension<AppColorsExtension>()!`. Zero hardcoded `Color(...)` or `Colors.xyz` in `lib/` (except `Colors.transparent`).
- Web Share Quota must be completely removed from the Settings screen.
- Thumbnail generation failures for videos/PDFs must log errors gracefully and return `null` without throwing unhandled exceptions that break file uploads.

---

### Task 1: Unified Media Thumbnail Pipeline

**Files:**
- Modify: `lib/core/utils/thumbnail_generator.dart`
- Modify: `lib/core/services/upload_service.dart:96-128`

**Interfaces:**
- Consumes: `ThumbnailGenerator.generate(bytes, filename, mimeType)`
- Produces: `ThumbnailResult` containing `Uint8List bytes` and `String extension` ('jpg' | 'png').

- [ ] **Step 1: Write unit tests for ThumbnailResult & ThumbnailGenerator dispatcher**

Create `test/thumbnail_generator_test.dart`:
```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/utils/thumbnail_generator.dart';

void main() {
  test('ThumbnailResult holds bytes and extension', () {
    final result = ThumbnailResult(Uint8List.fromList([1, 2, 3]), 'jpg');
    expect(result.bytes.length, 3);
    expect(result.extension, 'jpg');
  });

  test('ThumbnailGenerator returns null for unsupported mime type', () async {
    final bytes = Uint8List.fromList([0, 0, 0, 0]);
    final result = await ThumbnailGenerator.generate(
      bytes: bytes,
      filename: 'test.unknown',
      mimeType: 'application/unknown',
    );
    expect(result, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/thumbnail_generator_test.dart`
Expected: FAIL due to missing `ThumbnailResult` or `ThumbnailGenerator.generate`.

- [ ] **Step 3: Update `ThumbnailGenerator` with `ThumbnailResult` and unified `generate` method**

In `lib/core/utils/thumbnail_generator.dart`:
```dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:pdfx/pdfx.dart';
import '../utils/app_logger.dart';

import 'thumbnail_helper_native.dart'
    if (dart.library.js_interop) 'thumbnail_helper_web.dart';

class ThumbnailResult {
  final Uint8List bytes;
  final String extension;
  const ThumbnailResult(this.bytes, this.extension);
}

class ThumbnailGenerator {
  static const int maxDimension = 150;
  static const int quality = 70;

  static Future<ThumbnailResult?> generate({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    try {
      if (mimeType.startsWith('image/')) {
        final thumbBytes = await generateImageThumbnail(bytes);
        return ThumbnailResult(thumbBytes, 'jpg');
      } else if (mimeType.startsWith('video/')) {
        final thumbBytes = await generateVideoThumbnail(bytes, filename);
        return ThumbnailResult(thumbBytes, 'jpg');
      } else if (mimeType == 'application/pdf') {
        final thumbBytes = await generatePdfThumbnail(bytes);
        return ThumbnailResult(thumbBytes, 'png');
      }
    } catch (e) {
      AppLogger.w('Thumbnail generation failed for $filename ($mimeType): $e',
          tag: 'ThumbnailGenerator');
    }
    return null;
  }

  static Future<Uint8List> generateImageThumbnail(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: maxDimension,
    );
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ui.Image image = fi.image;
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) throw Exception('Failed to generate image thumbnail');
    return byteData.buffer.asUint8List();
  }

  static Future<Uint8List> generateVideoThumbnail(
    Uint8List videoBytes,
    String filename,
  ) async {
    final sourcePath =
        await ThumbnailHelper.prepareVideoSource(videoBytes, filename);
    try {
      final uint8list = await VideoThumbnail.thumbnailData(
        video: sourcePath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxDimension,
        quality: quality,
      );
      if (uint8list == null) throw Exception('Null video thumbnail output');
      return uint8list;
    } finally {
      ThumbnailHelper.cleanVideoSource(sourcePath);
    }
  }

  static Future<Uint8List> generatePdfThumbnail(Uint8List pdfBytes) async {
    final document = await PdfDocument.openData(pdfBytes);
    final page = await document.getPage(1);
    final pageImage = await page.render(
      width: page.width * 2,
      height: page.height * 2,
      format: PdfPageImageFormat.png,
    );
    await page.close();
    await document.close();
    if (pageImage == null) throw Exception('Failed to render PDF page');
    return pageImage.bytes;
  }
}
```

- [ ] **Step 4: Streamline thumbnail generation & upload in `UploadService`**

In `lib/core/services/upload_service.dart` (lines 96-128), update the thumbnail step to:
```dart
      // ── Step 1.5: Generate and Upload Thumbnail ────────────────────────────
      String? thumbnailFileId;
      try {
        internalOnProgress(0.08, 'Generating thumbnail…');
        final thumbResult = await ThumbnailGenerator.generate(
          bytes: bytes,
          filename: name,
          mimeType: mimeType,
        );

        if (thumbResult != null) {
          internalOnProgress(0.10, 'Uploading thumbnail…');
          final uploadRes = await _telegram.uploadBytesWithFileId(
            thumbResult.bytes,
            'thumb_${fileId}.${thumbResult.extension}',
          );
          thumbnailFileId = uploadRes['file_id'] as String;
        }
      } catch (e) {
        AppLogger.e('Thumbnail upload step failed for $name: $e',
            tag: 'UploadService');
      }
```

- [ ] **Step 5: Run unit tests to verify they pass**

Run: `flutter test test/thumbnail_generator_test.dart`
Expected: PASS

- [ ] **Step 6: Commit Task 1**

```bash
git add lib/core/utils/thumbnail_generator.dart lib/core/services/upload_service.dart test/thumbnail_generator_test.dart
git commit -m "feat: unify image, video, and pdf thumbnail generation and upload pipeline"
```

---

### Task 2: Hardcoded Colors Cleanup & Theme Color Test Suite

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart` (Replace `Colors.green` with `colors.success`)
- Modify: `test/no_hardcoded_colors_test.dart`
- Create: `test/theme_colors_test.dart`

**Interfaces:**
- Consumes: `AppTheme.light()`, `AppTheme.dark()`, `AppColorsExtension`
- Produces: Passing automated test suite enforcing zero hardcoded colors in `lib/` and 100% non-null theme tokens.

- [ ] **Step 1: Replace hardcoded color in `home_screen.dart`**

In `lib/features/home/screens/home_screen.dart`:
Replace line 93:
`backgroundColor: Theme.of(context).extension<AppColorsExtension>()?.success ?? Colors.green),`
With:
`backgroundColor: colors.success),`

- [ ] **Step 2: Run `no_hardcoded_colors_test.dart` to verify pass**

Run: `flutter test test/no_hardcoded_colors_test.dart`
Expected: PASS with 0 violations found.

- [ ] **Step 3: Create `test/theme_colors_test.dart`**

Create `test/theme_colors_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/theme/app_theme.dart';

void main() {
  test('AppTheme light and dark themes contain non-null AppColorsExtension', () {
    final lightTheme = AppTheme.light();
    final darkTheme = AppTheme.dark();

    final lightColors = lightTheme.extension<AppColorsExtension>();
    final darkColors = darkTheme.extension<AppColorsExtension>();

    expect(lightColors, isNotNull, reason: 'Light theme must have AppColorsExtension');
    expect(darkColors, isNotNull, reason: 'Dark theme must have AppColorsExtension');

    final colorLists = [lightColors!, darkColors!];
    for (final ext in colorLists) {
      expect(ext.bgPrimary, isNotNull);
      expect(ext.bgSurface, isNotNull);
      expect(ext.bgSurfaceInset, isNotNull);
      expect(ext.borderSubtle, isNotNull);
      expect(ext.textPrimary, isNotNull);
      expect(ext.textSecondary, isNotNull);
      expect(ext.textTertiary, isNotNull);
      expect(ext.accentPrimary, isNotNull);
      expect(ext.filePdf, isNotNull);
      expect(ext.fileVideo, isNotNull);
      expect(ext.fileZip, isNotNull);
      expect(ext.fileFolder, isNotNull);
      expect(ext.fileFolderBg, isNotNull);
      expect(ext.filePalette, isNotNull);
      expect(ext.fileVideoBg, isNotNull);
      expect(ext.fileTextBg, isNotNull);
      expect(ext.fileGenericBg, isNotNull);
      expect(ext.filePdfBg, isNotNull);
      expect(ext.glowColor, isNotNull);
      expect(ext.selectionColor, isNotNull);
      expect(ext.selectionColorAlt, isNotNull);
      expect(ext.success, isNotNull);
      expect(ext.error, isNotNull);
      expect(ext.warning, isNotNull);
    }
  });
}
```

- [ ] **Step 4: Run both theme tests to verify they pass**

Run: `flutter test test/no_hardcoded_colors_test.dart test/theme_colors_test.dart`
Expected: PASS

- [ ] **Step 5: Commit Task 2**

```bash
git add lib/features/home/screens/home_screen.dart test/no_hardcoded_colors_test.dart test/theme_colors_test.dart
git commit -m "test: cleanup hardcoded colors and add theme color extension validation tests"
```

---

### Task 3: Redesign Settings Screen (Card-Based Control Center)

**Files:**
- Modify: `lib/features/settings/screens/settings_screen.dart`

**Interfaces:**
- Consumes: `HomeCubit`, `HomeState`, `ThemeService`, `AuthService`, `AppColorsExtension`
- Produces: Remade `SettingsScreen` matching Card-Based Control Center layout with Web Share Quota removed.

- [ ] **Step 1: Re-architect `SettingsScreen` with modular section card widgets**

Replace `lib/features/settings/screens/settings_screen.dart` with:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/theme_service.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../home/bloc/home_cubit.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<HomeCubit>().refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: colors.bgPrimary,
          appBar: AppBar(
            backgroundColor: colors.bgPrimary,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.menu_rounded, color: colors.textPrimary),
              onPressed: () => MobileShell.of(context)?.openDrawer(),
            ),
            title: Text(
              'Control Center',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              _buildProfileCard(colors, state),
              const SizedBox(height: 24),
              _sectionLabel(colors, 'STORAGE & CLOUD'),
              const SizedBox(height: 10),
              _buildStorageCard(colors, state),
              const SizedBox(height: 24),
              _sectionLabel(colors, 'APPEARANCE'),
              const SizedBox(height: 10),
              _buildAppearanceCard(colors),
              const SizedBox(height: 24),
              _sectionLabel(colors, 'PREFERENCES & TOOLS'),
              const SizedBox(height: 10),
              _buildToolsCard(colors),
              const SizedBox(height: 32),
              _buildLogoutButton(colors),
              const SizedBox(height: 60),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(AppColorsExtension colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildProfileCard(AppColorsExtension colors, HomeState state) {
    final name = state.userName ?? 'User';
    final email = state.userEmail ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              shape: BoxShape.circle,
              border: Border.all(color: colors.accentPrimary.withOpacity(0.3), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Connected to Telegram Cloud',
                    style: TextStyle(
                      color: colors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageCard(AppColorsExtension colors, HomeState state) {
    final usedMb = state.storageUsedMb;
    final usedText = usedMb >= 1024
        ? '${(usedMb / 1024).toStringAsFixed(1)} GB'
        : '${usedMb.toStringAsFixed(0)} MB';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.cloud_outlined, color: colors.textPrimary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Telegram Cloud Storage',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '$usedText / Unlimited',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (usedMb / 102400).clamp(0.02, 1.0),
                    minHeight: 6,
                    backgroundColor: colors.bgSurfaceInset,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceCard(AppColorsExtension colors) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.bgSurfaceInset,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.contrast_rounded, color: colors.textPrimary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Theme Mode',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeService.instance.themeModeNotifier,
                builder: (context, mode, _) {
                  final modeText = mode == ThemeMode.system
                      ? 'System'
                      : (mode == ThemeMode.dark ? 'Dark' : 'Light');
                  return Text(
                    modeText,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeService.instance.themeModeNotifier,
              builder: (context, currentMode, _) {
                return Row(
                  children: [
                    _buildThemeToggle(ThemeMode.light, 'Light', currentMode, colors),
                    _buildThemeToggle(ThemeMode.dark, 'Dark', currentMode, colors),
                    _buildThemeToggle(ThemeMode.system, 'System', currentMode, colors),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeToggle(
    ThemeMode mode,
    String label,
    ThemeMode currentMode,
    AppColorsExtension colors,
  ) {
    final isSelected = currentMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => ThemeService.instance.setThemeMode(mode),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colors.accentPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? colors.bgPrimary : colors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolsCard(AppColorsExtension colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: Column(
        children: [
          _buildToolTile(
            colors,
            icon: Icons.share_outlined,
            title: 'Public Web Shares',
            subtitle: 'Manage active storage.to shared links',
            onTap: () => Navigator.pushNamed(context, AppRouter.browser),
          ),
          Divider(color: colors.borderSubtle, height: 1),
          _buildToolTile(
            colors,
            icon: Icons.info_outline_rounded,
            title: 'About TelStorage',
            subtitle: 'v1.0.0 — Telegram-powered Cloud Storage',
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildToolTile(
    AppColorsExtension colors, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.bgSurfaceInset,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: colors.textPrimary, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 12,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: colors.textTertiary, size: 20),
    );
  }

  Widget _buildLogoutButton(AppColorsExtension colors) {
    return GestureDetector(
      onTap: () => _logout(colors),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: colors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.error.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: colors.error, size: 20),
            const SizedBox(width: 10),
            Text(
              'Log Out',
              style: TextStyle(
                color: colors.error,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout(AppColorsExtension colors) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Log out?', style: TextStyle(color: colors.textPrimary)),
        content: Text('Your files are safely stored on Telegram.',
            style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Log out', style: TextStyle(color: colors.textPrimary)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final nav = Navigator.of(context);
      await AuthService.instance.logout();
      nav.pushReplacementNamed(AppRouter.login);
    }
  }
}
```

- [ ] **Step 2: Run all tests to ensure zero breakages and zero hardcoded color violations**

Run: `flutter test`
Expected: PASS (All tests succeed).

- [ ] **Step 3: Commit Task 3**

```bash
git add lib/features/settings/screens/settings_screen.dart
git commit -m "feat: remake settings screen into card-based control center without webshare quota"
```
