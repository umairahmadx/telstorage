/*
 * Receives OS file shares before authentication and keeps them pending until
 * the upload destination flow accepts or cancels them.
 */

import 'package:flutter/foundation.dart';
import 'package:file_share_intent/file_share_intent.dart';

import '../../../../core/utils/app_logger.dart';
import 'incoming_share_file_stub.dart'
    if (dart.library.io) 'incoming_share_file_native.dart';

class IncomingShareService extends ChangeNotifier {
  IncomingShareService._();

  static final IncomingShareService instance = IncomingShareService._();

  final Map<String, SharedMediaFile> _pending = {};
  final Map<String, DateTime> _recentPaths = {};
  bool _initialized = false;

  bool get hasPending => _pending.isNotEmpty;

  List<SharedMediaFile> get pendingFiles => List.unmodifiable(_pending.values);

  Future<void> initialize() async {
    if (_initialized ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    _initialized = true;

    FileShareIntent.instance.getMediaStream().listen(
      _accept,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.e(
          'Failed to receive shared files: $error',
          tag: 'IncomingShare',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );

    try {
      _accept(await FileShareIntent.instance.getInitialMedia());
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to read initial shared files: $error',
        tag: 'IncomingShare',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Completes an incoming share after the user starts or cancels its flow.
  Future<void> complete(List<SharedMediaFile> files) async {
    for (final file in files) {
      _pending.remove(file.path);
    }
    try {
      await FileShareIntent.instance.reset();
    } catch (error) {
      AppLogger.w(
        'Could not reset consumed share intent: $error',
        tag: 'IncomingShare',
        error: error,
      );
    }
    notifyListeners();
  }

  static String localPathFor(SharedMediaFile file) {
    final uri = Uri.tryParse(file.path);
    return uri?.scheme == 'file' ? uri!.toFilePath() : file.path;
  }

  static Future<void> deleteTemporaryFiles(
    Iterable<SharedMediaFile> files,
  ) async {
    for (final file in files) {
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
        continue;
      }
      try {
        final path = localPathFor(file);
        await deleteIncomingShareFile(path);
      } catch (error) {
        AppLogger.w(
          'Could not remove temporary shared file: $error',
          tag: 'IncomingShare',
        );
      }
    }
  }

  void _accept(List<SharedMediaFile> files) {
    final now = DateTime.now();
    _recentPaths.removeWhere(
      (_, receivedAt) =>
          now.difference(receivedAt) > const Duration(seconds: 10),
    );
    var changed = false;
    for (final file in files) {
      if (file.path.isEmpty) continue;
      final lastReceived = _recentPaths[file.path];
      if (lastReceived != null &&
          now.difference(lastReceived) <= const Duration(seconds: 10)) {
        continue;
      }
      _recentPaths[file.path] = now;
      _pending[file.path] = file;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
