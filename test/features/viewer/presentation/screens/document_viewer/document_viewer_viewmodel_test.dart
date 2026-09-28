/*
 * File: document_viewer_viewmodel_test.dart
 * Description: Unit tests for DocumentViewerViewModel state changes, edit mode, and reading themes.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/viewmodel/document_viewer_viewmodel.dart';

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
    expect(vm.readingTheme, equals(DocumentReadingTheme.original));
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

  test('setReadingTheme updates theme and notifies listeners', () {
    final vm = DocumentViewerViewModel(file: mockPdf);
    vm.setReadingTheme(DocumentReadingTheme.dark);
    expect(vm.readingTheme, equals(DocumentReadingTheme.dark));

    vm.setReadingTheme(DocumentReadingTheme.sepia);
    expect(vm.readingTheme, equals(DocumentReadingTheme.sepia));
  });

  test('toggleChrome flips visibility', () {
    final vm = DocumentViewerViewModel(file: mockPdf);
    expect(vm.isChromeVisible, isTrue);
    vm.toggleChrome();
    expect(vm.isChromeVisible, isFalse);
    vm.toggleChrome();
    expect(vm.isChromeVisible, isTrue);
  });
}
