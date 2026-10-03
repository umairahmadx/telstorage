/*
 * File: document_viewer_viewmodel.dart
 * Description: State management for DocumentViewerScreen handling file downloads, format routing, and editing state.
 */

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/document_viewer_cache_service.dart';
import 'package:telstorage/core/utils/app_logger.dart';

/// State controller for document viewing, searching, and editing.
class DocumentViewerViewModel extends ChangeNotifier {
  /// Current target file record.
  FileRecord _currentFile;

  /// Cached local file path on disk.
  File? _localFile;

  /// Text content when in text/code mode.
  String _textContent = '';

  /// Original text content for dirty tracking.
  String _originalContent = '';

  /// Whether editor is currently in edit mode.
  bool _isEditMode = false;

  /// Whether content has unsaved modifications.
  bool _isDirty = false;

  /// Whether file is downloading or saving.
  bool _isLoading = true;

  /// Whether a save operation is currently in flight (guards double-submit).
  bool _isSaving = false;

  /// Error message if loading or saving failed.
  String? _errorMessage;

  /// Download or save progress percentage (0.0 to 1.0).
  double _progress = 0.0;

  /// Current progress status label.
  String _statusMessage = 'Loading document…';

  /// Whether top and bottom chrome are visible.
  bool _isChromeVisible = true;

  /// Current PDF page number (1-based).
  int _currentPage = 1;

  /// Total PDF page count.
  int _pageCount = 1;

  /// Constructs DocumentViewerViewModel.
  DocumentViewerViewModel({required FileRecord file}) : _currentFile = file;

  FileRecord get currentFile => _currentFile;
  File? get localFile => _localFile;
  String get textContent => _textContent;
  bool get isEditMode => _isEditMode;
  bool get isDirty => _isDirty;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  bool get isChromeVisible => _isChromeVisible;
  int get currentPage => _currentPage;
  int get pageCount => _pageCount;

  /// Initializes file retrieval from cache or network.
  Future<void> init() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final file = await DocumentViewerCacheService.instance.getOrDownloadFile(
        _currentFile,
        onProgress: (pct, msg) {
          _progress = pct;
          _statusMessage = msg;
          notifyListeners();
        },
      );

      if (file == null || !file.existsSync()) {
        _errorMessage = 'Could not load document.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      _localFile = file;

      if (DocumentViewerCacheService.isTextRecord(_currentFile)) {
        final text =
            await DocumentViewerCacheService.instance.readTextContent(file);
        _textContent = text ?? '';
        _originalContent = _textContent;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.e('DocumentViewerViewModel init failed: $e',
          tag: 'DocumentViewerViewModel');
      _errorMessage = 'Failed to load document: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets text content initially.
  void setTextContent(String content) {
    _textContent = content;
    _originalContent = content;
    _isDirty = false;
    notifyListeners();
  }

  /// Updates text content and flags dirty state.
  ///
  /// Listeners are only notified when the dirty flag actually flips, so typing
  /// does not rebuild the entire screen on every single keystroke. The editor
  /// controller stays the live source of truth while the user types; the
  /// ViewModel is synced on change and committed on save.
  void updateTextContent(String newContent) {
    _textContent = newContent;
    final wasDirty = _isDirty;
    _isDirty = newContent != _originalContent;
    if (_isDirty != wasDirty) notifyListeners();
  }

  /// Toggles between read-only and edit mode.
  void toggleEditMode() {
    _isEditMode = !_isEditMode;
    notifyListeners();
  }

  /// Toggles top/bottom chrome visibility.
  void toggleChrome() {
    _isChromeVisible = !_isChromeVisible;
    notifyListeners();
  }

  /// Explicitly sets chrome visibility.
  void setChromeVisible(bool visible) {
    if (_isChromeVisible != visible) {
      _isChromeVisible = visible;
      notifyListeners();
    }
  }

  /// Updates current page and page count.
  void setPage(int page, {int? total}) {
    _currentPage = page;
    if (total != null) _pageCount = total;
    notifyListeners();
  }

  /// Saves modified text content back to Telegram.
  ///
  /// Re-entrancy guarded: a second invocation while a save is already in flight
  /// (e.g. a double-tapped save button) returns immediately instead of
  /// launching a duplicate upload that would create two copies of the file.
  Future<bool> saveChanges() async {
    if (_isSaving) return false;
    if (!_isDirty) return true;

    _isSaving = true;
    _isLoading = true;
    _errorMessage = null;
    _progress = 0.0;
    _statusMessage = 'Saving changes to Telegram…';
    notifyListeners();

    try {
      final result = await DocumentViewerCacheService.instance.saveEditedFile(
        _currentFile,
        _textContent,
        onProgress: (pct, msg) {
          _progress = pct;
          _statusMessage = msg;
          notifyListeners();
        },
      );

      if (result is Success<FileRecord>) {
        _currentFile = result.data;
        // Repoint the local file: the superseded cache entry is deleted during
        // save, so the old path must not linger on the ViewModel.
        try {
          _localFile = await DocumentViewerCacheService.instance
              .getCacheTargetFile(result.data);
        } catch (_) {}
        _originalContent = _textContent;
        _isDirty = false;
        _isEditMode = false;
        _statusMessage = 'Saved';
        return true;
      }

      _errorMessage = 'Failed to save changes.';
      return false;
    } catch (e) {
      AppLogger.e('saveChanges failed: $e', tag: 'DocumentViewerViewModel');
      _errorMessage = 'Failed to save changes.';
      return false;
    } finally {
      _isSaving = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets loaded file state directly for testing purposes.
  @visibleForTesting
  void setLoadedForTest(File file, String content) {
    _localFile = file;
    _textContent = content;
    _originalContent = content;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Sets the in-flight saving state directly for testing purposes so widget
  /// tests can render the save progress overlay without a real upload.
  @visibleForTesting
  void setSavingForTest({
    required bool isSaving,
    String? statusMessage,
    double? progress,
  }) {
    _isSaving = isSaving;
    if (statusMessage != null) _statusMessage = statusMessage;
    if (progress != null) _progress = progress;
    notifyListeners();
  }
}
