# Image and Video Thumbnails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement client-side generation, upload, caching, and rendering of 150px JPEG thumbnails for images and videos on both Android and Web.

**Architecture:** Integrate thumbnail generation in `UploadService.uploadFile` using a conditional interop utility (`ThumbnailHelper`). Store the resulting Telegram `file_id` in the per-file metadata JSON and the local Hive cache (`FileRecord`). Implement a local-first `ThumbnailRepository` (in-memory for Web, temporary directory file-system for Android) and render previews in `_FileTile` and `_GridFileItem` using `ThumbnailWidget`.

**Tech Stack:** Flutter, Hive, get_thumbnail_video (for video frame extraction), dart:html (for Web Object URLs), dart:io (for Android temp files).

## Global Constraints
- Target Platforms: Android and Web (Chrome).
- Must avoid compile-time issues with `dart:io` on Web and `dart:html` on Android.
- Thumbnail dimensions: Max 150px resolution, compressed as JPEG at 70% quality.
- Upload failure fallback: If thumbnail generation fails, the main file upload must still succeed with a `null` thumbnail file ID.
- Network optimization: Deduplicate simultaneous requests for the same thumbnail.

---

### Task 1: Add Dependency to pubspec.yaml

**Files:**
- Modify: [pubspec.yaml](file:///c:/Users/umair-dell/StudioProjects/telstorage/pubspec.yaml)

**Interfaces:**
- Consumes: None
- Produces: `get_thumbnail_video` package available for imports.

- [ ] **Step 1: Add `get_thumbnail_video` to `pubspec.yaml`**
  Modify [pubspec.yaml](file:///c:/Users/umair-dell/StudioProjects/telstorage/pubspec.yaml) to add the package under `dependencies`:
  ```yaml
    # Video thumbnail extraction
    get_thumbnail_video: ^0.7.3
  ```

- [ ] **Step 2: Run flutter pub get**
  Run: `flutter pub get`
  Expected: Command completes successfully with status 0.

- [ ] **Step 3: Commit changes**
  Run:
  ```bash
  git add pubspec.yaml
  git commit -m "chore: add get_thumbnail_video dependency"
  ```

---

### Task 2: Update FileRecord Model and Generate Hive Adapter

**Files:**
- Modify: [file_record.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/models/file_record.dart)
- Generate: [file_record.g.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/models/file_record.g.dart)

**Interfaces:**
- Consumes: `FileRecord`
- Produces: `FileRecord` with a nullable `thumbnailFileId` field and rebuilt adapter.

- [ ] **Step 1: Modify `FileRecord` to add the `thumbnailFileId` field**
  Modify [file_record.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/models/file_record.dart):
  Add `@HiveField(10)` and field declaration:
  ```dart
    @HiveField(10)
    String? thumbnailFileId;
  ```
  Update constructor:
  ```dart
    FileRecord({
      // ... existing parameters ...
      this.thumbnailFileId,
    });
  ```
  Update `fromMap` factory:
  ```dart
    factory FileRecord.fromMap(Map<String, dynamic> map) {
      return FileRecord(
        // ... existing fields ...
        thumbnailFileId: map['thumbnail_file_id'] as String?,
      );
    }
  ```

- [ ] **Step 2: Generate the Hive Adapter**
  Run build_runner: `flutter pub run build_runner build --delete-conflicting-outputs`
  Expected: Rebuild completes successfully, and `file_record.g.dart` is updated with field index 10.

- [ ] **Step 3: Commit changes**
  Run:
  ```bash
  git add lib/core/models/file_record.dart lib/core/models/file_record.g.dart
  git commit -m "feat: add thumbnailFileId field to FileRecord Hive model"
  ```

---

### Task 3: Implement Conditional Platform Video Source Helpers

**Files:**
- Create: [thumbnail_helper_native.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/utils/thumbnail_helper_native.dart)
- Create: [thumbnail_helper_web.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/utils/thumbnail_helper_web.dart)

**Interfaces:**
- Consumes: `Uint8List bytes`, `String name`
- Produces: `ThumbnailHelper.prepareVideoSource` returning a `Future<String>` path/URL, and `ThumbnailHelper.cleanVideoSource` performing cleanup.

- [ ] **Step 1: Create `thumbnail_helper_native.dart`**
  Write [thumbnail_helper_native.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/utils/thumbnail_helper_native.dart) for Android file system:
  ```dart
  import 'dart:io';
  import 'dart:typed_data';
  import 'package:path_provider/path_provider.dart';

  class ThumbnailHelper {
    static Future<String> prepareVideoSource(Uint8List bytes, String name) async {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_thumb_$name');
      await tempFile.writeAsBytes(bytes);
      return tempFile.path;
    }

    static void cleanVideoSource(String source) {
      try {
        final file = File(source);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
  }
  ```

- [ ] **Step 2: Create `thumbnail_helper_web.dart`**
  Write [thumbnail_helper_web.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/utils/thumbnail_helper_web.dart) for Web HTML5 Object URLs:
  ```dart
  // ignore: avoid_web_libraries_in_flutter
  import 'dart:html' as html;
  import 'dart:typed_data';

  class ThumbnailHelper {
    static Future<String> prepareVideoSource(Uint8List bytes, String name) async {
      final blob = html.Blob([bytes]);
      return html.Url.createObjectUrlFromBlob(blob);
    }

    static void cleanVideoSource(String source) {
      try {
        html.Url.revokeObjectUrl(source);
      } catch (_) {}
    }
  }
  ```

- [ ] **Step 3: Commit changes**
  Run:
  ```bash
  git add lib/core/utils/thumbnail_helper_native.dart lib/core/utils/thumbnail_helper_web.dart
  git commit -m "feat: add platform-specific video helper stubs"
  ```

---

### Task 4: Implement Thumbnail Generator Utility

**Files:**
- Create: [thumbnail_generator.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/utils/thumbnail_generator.dart)

**Interfaces:**
- Consumes: Image / Video bytes (`Uint8List`) and names
- Produces: `ThumbnailGenerator.generateImageThumbnail` and `ThumbnailGenerator.generateVideoThumbnail` returning resized image bytes.

- [ ] **Step 1: Create `thumbnail_generator.dart`**
  Write [thumbnail_generator.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/utils/thumbnail_generator.dart) with conditional imports to resolve stubs:
  ```dart
  import 'dart:typed_data';
  import 'dart:ui' as ui;
  import 'package:get_thumbnail_video/index.dart';
  import 'package:get_thumbnail_video/get_thumbnail_video.dart';

  import 'thumbnail_helper_native.dart'
      if (dart.library.js_interop) 'thumbnail_helper_web.dart';

  class ThumbnailGenerator {
    static const int maxDimension = 150;
    static const int quality = 70;

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
      final sourcePath = await ThumbnailHelper.prepareVideoSource(videoBytes, filename);
      try {
        final uint8list = await VideoThumbnail.thumbnailData(
          video: sourcePath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: maxDimension,
          quality: quality,
        );
        if (uint8list == null) throw Exception('Failed to extract video thumbnail data');
        return uint8list;
      } finally {
        ThumbnailHelper.cleanVideoSource(sourcePath);
      }
    }
  }
  ```

- [ ] **Step 2: Commit changes**
  Run:
  ```bash
  git add lib/core/utils/thumbnail_generator.dart
  git commit -m "feat: add ThumbnailGenerator utility with conditional helper"
  ```

---

### Task 5: Implement Thumbnail Repository and Register in ServiceLocator

**Files:**
- Create: [thumbnail_repository.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/services/thumbnail_repository.dart)
- Modify: [service_locator.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/services/service_locator.dart)

**Interfaces:**
- Consumes: `TelegramService`
- Produces: `ThumbnailRepository` class and `ServiceLocator.instance.thumbnailRepository` getter.

- [ ] **Step 1: Create `thumbnail_repository.dart`**
  Write [thumbnail_repository.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/services/thumbnail_repository.dart):
  ```dart
  import 'dart:io';
  import 'dart:typed_data';
  import 'package:flutter/foundation.dart' show kIsWeb;
  import 'package:path_provider/path_provider.dart';
  import '../models/file_record.dart';
  import '../utils/app_logger.dart';
  import 'telegram_service.dart';

  class ThumbnailRepository {
    final TelegramService _telegram;
    final Map<String, Future<dynamic>> _activeDownloads = {};
    final Map<String, Uint8List> _webCache = {};

    ThumbnailRepository(this._telegram);

    Future<dynamic> getThumbnailData(FileRecord file) async {
      if (file.thumbnailFileId == null) return null;

      if (kIsWeb) {
        if (_webCache.containsKey(file.fileId)) {
          return _webCache[file.fileId];
        }
        if (_activeDownloads.containsKey(file.fileId)) {
          return _activeDownloads[file.fileId];
        }

        final downloadFuture = () async {
          try {
            final bytes = await _telegram.downloadByFileId(file.thumbnailFileId!);
            _webCache[file.fileId] = bytes;
            return bytes;
          } catch (e) {
            AppLogger.e('Failed to download web thumbnail: $e', tag: 'ThumbnailRepository');
            return null;
          } finally {
            _activeDownloads.remove(file.fileId);
          }
        }();

        _activeDownloads[file.fileId] = downloadFuture;
        return downloadFuture;
      } else {
        final tempDir = await getTemporaryDirectory();
        final localFile = File('${tempDir.path}/thumbnails/${file.fileId}.jpg');
        if (await localFile.exists()) {
          return localFile.path;
        }

        if (_activeDownloads.containsKey(file.fileId)) {
          return _activeDownloads[file.fileId];
        }

        final downloadFuture = () async {
          try {
            final thumbDir = Directory('${tempDir.path}/thumbnails');
            if (!await thumbDir.exists()) {
              await thumbDir.create(recursive: true);
            }
            final bytes = await _telegram.downloadByFileId(file.thumbnailFileId!);
            await localFile.writeAsBytes(bytes);
            return localFile.path;
          } catch (e) {
            AppLogger.e('Failed to download native thumbnail: $e', tag: 'ThumbnailRepository');
            return null;
          } finally {
            _activeDownloads.remove(file.fileId);
          }
        }();

        _activeDownloads[file.fileId] = downloadFuture;
        return downloadFuture;
      }
    }
  }
  ```

- [ ] **Step 2: Update `ServiceLocator` to register `ThumbnailRepository`**
  Modify [service_locator.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/services/service_locator.dart):
  Import `thumbnail_repository.dart`.
  Add repository field and getter:
  ```dart
    late ThumbnailRepository _thumbnailRepository;
    ThumbnailRepository get thumbnailRepository => _thumbnailRepository;
  ```
  Instantiate inside `_doInit()` after `_telegram` has been instantiated:
  ```dart
      _thumbnailRepository = ThumbnailRepository(_telegram);
  ```

- [ ] **Step 3: Commit changes**
  Run:
  ```bash
  git add lib/core/services/thumbnail_repository.dart lib/core/services/service_locator.dart
  git commit -m "feat: implement ThumbnailRepository and register in ServiceLocator"
  ```

---

### Task 6: Integrate Thumbnail Generation and Upload in UploadService

**Files:**
- Modify: [upload_service.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/services/upload_service.dart)

**Interfaces:**
- Consumes: `ThumbnailGenerator`
- Produces: `UploadService.uploadFile` generating, uploading, and appending `thumbnail_file_id` to file meta JSON.

- [ ] **Step 1: Update `uploadFile` pipeline**
  Modify [upload_service.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/services/upload_service.dart):
  Import `thumbnail_generator.dart`.
  In `uploadFile`, before uploading the chunks (e.g. after step 1 SHA-256 calculation), perform thumbnail generation:
  ```dart
        // ── Step 1.5: Generate and Upload Thumbnail ────────────────────────────
        String? thumbnailFileId;
        try {
          if (mimeType.startsWith('image/')) {
            onProgress(0.08, 'Generating thumbnail…');
            final thumbBytes = await ThumbnailGenerator.generateImageThumbnail(bytes);
            onProgress(0.10, 'Uploading thumbnail…');
            final thumbResult = await _telegram.uploadBytesWithFileId(thumbBytes, 'thumb_$fileId.jpg');
            thumbnailFileId = thumbResult['file_id'] as String;
          } else if (mimeType.startsWith('video/')) {
            onProgress(0.08, 'Generating video thumbnail…');
            final thumbBytes = await ThumbnailGenerator.generateVideoThumbnail(bytes, name);
            onProgress(0.10, 'Uploading thumbnail…');
            final thumbResult = await _telegram.uploadBytesWithFileId(thumbBytes, 'thumb_$fileId.jpg');
            thumbnailFileId = thumbResult['file_id'] as String;
          }
        } catch (e) {
          AppLogger.e('Thumbnail generation failed for $name: $e', tag: 'UploadService');
        }
  ```
  Inject the field inside `fileMeta` JSON payload:
  ```dart
        final fileMeta = <String, dynamic>{
          'file_id': fileId,
          'name': name,
          'folder_id': folderId,
          'sha256': hash,
          'size_mb': sizeMb,
          'mime_type': mimeType,
          'chunk_count': chunkInfos.length,
          'is_zipped': bytes.length > _partSize,
          'chunks': chunkInfos.map((c) => c.toJson()).toList(),
          'uploaded_at': DateTime.now().toIso8601String(),
          if (thumbnailFileId != null) 'thumbnail_file_id': thumbnailFileId,
        };
  ```

- [ ] **Step 2: Commit changes**
  Run:
  ```bash
  git add lib/core/services/upload_service.dart
  git commit -m "feat: integrate thumbnail generation and upload in UploadService"
  ```

---

### Task 7: Implement Thumbnail Widget and Integrate in UI

**Files:**
- Create: [thumbnail_widget.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/shared/widgets/thumbnail_widget.dart)
- Modify: [browser_screen.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/features/browser/screens/browser_screen.dart:1468-1476,1681-1683)

**Interfaces:**
- Consumes: `FileRecord`
- Produces: `ThumbnailWidget` rendering image preview or falling back to icons.

- [ ] **Step 1: Create `thumbnail_widget.dart`**
  Write [thumbnail_widget.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/shared/widgets/thumbnail_widget.dart):
  ```dart
  import 'dart:io';
  import 'dart:typed_data';
  import 'package:flutter/foundation.dart' show kIsWeb;
  import 'package:flutter/material.dart';
  import '../../core/models/file_record.dart';
  import '../../core/services/service_locator.dart';

  class ThumbnailWidget extends StatefulWidget {
    final FileRecord file;
    final double width;
    final double height;
    final BoxFit fit;
    final Widget fallback;

    const ThumbnailWidget({
      super.key,
      required this.file,
      required this.width,
      required this.height,
      this.fit = BoxFit.cover,
      required this.fallback,
    });

    @override
    State<ThumbnailWidget> createState() => _ThumbnailWidgetState();
  }

  class _ThumbnailWidgetState extends State<ThumbnailWidget> {
    late Future<dynamic> _thumbnailFuture;

    @override
    void initState() {
      super.initState();
      _thumbnailFuture = ServiceLocator.instance.thumbnailRepository.getThumbnailData(widget.file);
    }

    @override
    void didUpdateWidget(covariant ThumbnailWidget oldWidget) {
      super.didUpdateWidget(oldWidget);
      if (oldWidget.file.fileId != widget.file.fileId ||
          oldWidget.file.thumbnailFileId != widget.file.thumbnailFileId) {
        _thumbnailFuture = ServiceLocator.instance.thumbnailRepository.getThumbnailData(widget.file);
      }
    }

    @override
    Widget build(BuildContext context) {
      if (widget.file.thumbnailFileId == null) {
        return widget.fallback;
      }

      return FutureBuilder<dynamic>(
        future: _thumbnailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
            final data = snapshot.data;
            ImageProvider imageProvider;
            if (kIsWeb && data is Uint8List) {
              imageProvider = MemoryImage(data);
            } else if (!kIsWeb && data is String) {
              imageProvider = FileImage(File(data));
            } else {
              return widget.fallback;
            }

            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image(
                image: imageProvider,
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
                errorBuilder: (_, __, ___) => widget.fallback,
              ),
            );
          }

          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      );
    }
  }
  ```

- [ ] **Step 2: Update `_FileTile` in `browser_screen.dart`**
  Modify [browser_screen.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/features/browser/screens/browser_screen.dart):
  Import `thumbnail_widget.dart`.
  Locate lines 1468-1476 in `_FileTile` and replace:
  ```dart
            : Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _color().withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon(), color: _color(), size: 22),
              ),
  ```
  with:
  ```dart
            : ThumbnailWidget(
                file: file,
                width: 42,
                height: 42,
                fallback: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _color().withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_icon(), color: _color(), size: 22),
                ),
              ),
  ```

- [ ] **Step 3: Update `_GridFileItem` in `browser_screen.dart`**
  Locate lines 1681-1683 in `_GridFileItem` and replace:
  ```dart
        Expanded(
            child: Center(child: Icon(_icon(), size: 40, color: _color()))),
  ```
  with:
  ```dart
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ThumbnailWidget(
                file: file,
                width: double.infinity,
                height: double.infinity,
                fallback: Icon(_icon(), size: 40, color: _color()),
              ),
            ),
          ),
        ),
  ```

- [ ] **Step 4: Commit changes**
  Run:
  ```bash
  git add lib/shared/widgets/thumbnail_widget.dart lib/features/browser/screens/browser_screen.dart
  git commit -m "feat: integrate ThumbnailWidget in browser screen list and grid tiles"
  ```
