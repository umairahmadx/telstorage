/*
 * File: auto_backup_lifecycle.dart
 * Description: Foreground lifecycle bridge for consuming pending auto-backup work.
 */

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Runs a pending auto-backup callback when the application resumes.
class AutoBackupLifecycleObserver with WidgetsBindingObserver {
  /// Callback that consumes pending foreground backup work.
  final Future<void> Function() onResume;

  /// Prevents overlapping resume-triggered backup consumption.
  bool _resumeInProgress = false;

  /// Constructs an observer for the supplied resume callback.
  AutoBackupLifecycleObserver({required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _resumeInProgress) return;
    unawaited(_consumePendingBackup());
  }

  /// Invokes the resume callback and releases the overlap guard.
  Future<void> _consumePendingBackup() async {
    _resumeInProgress = true;
    try {
      await onResume();
    } finally {
      _resumeInProgress = false;
    }
  }
}
