/*
 * File: document_viewer_viewmodel_test.dart
 * Description: Unit tests for DocumentViewerViewModel state changes and edit mode.
 */

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/upload_service.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/viewmodel/document_viewer_viewmodel.dart';

/// Upload stand-in that blocks on a gate and always fails, so save behaviour
/// can be observed mid-flight without touching Hive or the file system.
class _GatedUploadService extends Fake implements UploadService {
  final Completer<void> gate = Completer<void>();
  int calls = 0;

  @override
  Future<Result<Map<String, dynamic>>> uploadFile(
    Uint8List? bytes,
    String name,
    String? folderId,
    Function(double progress, String status) onProgress, {
    String? filePath,
    int? fileLength,
    bool skipGlobalMetadataUpdate = false,
    String? taskId,
    String? precomputedHash,
    Uint8List? precomputedThumbnailBytes,
    String? thumbnailExtension,
  }) async {
    calls++;
    await gate.future;
    return const Failure(UnknownFailure('upload failed'));
  }
}

void main() {
  late FileRecord mockPdf;
  late FileRecord mockText;

  setUp(() {
    mockPdf = FileRecord(
      fileId: 'pdf1',
      name: 'doc.pdf',
      metadataMessageId: 1,
      sizeMb: 1.0,
      mimeType: 'application/pdf',
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: 'h1',
    );

    mockText = FileRecord(
      fileId: 'txt1',
      name: 'notes.dart',
      metadataMessageId: 2,
      sizeMb: 0.1,
      mimeType: 'text/plain',
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: 'h2',
    );
  });

  test('DocumentViewerViewModel initial state', () {
    final vm = DocumentViewerViewModel(file: mockText);
    expect(vm.currentFile.fileId, equals('txt1'));
    expect(vm.isEditMode, isFalse);
    expect(vm.isDirty, isFalse);
    expect(vm.isChromeVisible, isTrue);
  });

  test('toggleEditMode toggles state and notifies listeners', () {
    final vm = DocumentViewerViewModel(file: mockText);
    bool notified = false;
    vm.addListener(() => notified = true);

    vm.toggleEditMode();
    expect(vm.isEditMode, isTrue);
    expect(notified, isTrue);

    vm.toggleEditMode();
    expect(vm.isEditMode, isFalse);
  });

  test('updateTextContent marks dirty state', () {
    final vm = DocumentViewerViewModel(file: mockText);
    vm.setTextContent('initial');
    expect(vm.isDirty, isFalse);

    vm.updateTextContent('modified');
    expect(vm.isDirty, isTrue);
    expect(vm.textContent, equals('modified'));
  });

  test('toggleChrome flips visibility', () {
    final vm = DocumentViewerViewModel(file: mockPdf);
    expect(vm.isChromeVisible, isTrue);
    vm.toggleChrome();
    expect(vm.isChromeVisible, isFalse);
    vm.toggleChrome();
    expect(vm.isChromeVisible, isTrue);
  });

  test('updateTextContent only notifies when the dirty flag changes', () {
    final vm = DocumentViewerViewModel(file: mockText);
    vm.setTextContent('a');

    int notifications = 0;
    vm.addListener(() => notifications++);

    vm.updateTextContent('b'); // clean -> dirty: notify
    expect(notifications, 1);

    vm.updateTextContent('c'); // dirty -> dirty: no rebuild
    expect(notifications, 1,
        reason: 'Per-keystroke edits must not rebuild the whole screen');

    vm.updateTextContent('a'); // dirty -> clean: notify
    expect(notifications, 2);
  });

  test('a second save while one is in flight is ignored', () async {
    final fakeUpload = _GatedUploadService();
    ServiceLocator.instance.setUploadServiceForTesting(fakeUpload);

    final vm = DocumentViewerViewModel(file: mockText);
    vm.setTextContent('a');
    vm.updateTextContent('b'); // mark dirty

    final first = vm.saveChanges();
    final second = vm.saveChanges(); // must be blocked by the re-entrancy guard

    await Future<void>.delayed(Duration.zero);
    expect(fakeUpload.calls, 1,
        reason: 'Double-tapping save must not launch a duplicate upload');

    fakeUpload.gate.complete();
    expect(await first, isFalse);
    expect(await second, isFalse);
  });

  test('a failed save surfaces an error and keeps the file dirty', () async {
    final fakeUpload = _GatedUploadService();
    ServiceLocator.instance.setUploadServiceForTesting(fakeUpload);

    final vm = DocumentViewerViewModel(file: mockText);
    vm.setTextContent('a');
    vm.toggleEditMode(); // realistic flow: user is in edit mode when saving
    vm.updateTextContent('b');

    final saving = vm.saveChanges();
    expect(vm.isSaving, isTrue);

    fakeUpload.gate.complete();
    final ok = await saving;

    expect(ok, isFalse);
    expect(vm.errorMessage, isNotNull);
    expect(vm.isSaving, isFalse);
    expect(vm.isDirty, isTrue,
        reason: 'Unsaved edits must survive a failed save');
    expect(vm.isEditMode, isTrue);
  });
}
