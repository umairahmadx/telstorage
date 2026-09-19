/*
 * File: download_disk_writer_native.dart
 * Description: Zero-buffer disk streaming writer for large downloads with progressive SHA-256 calculation and atomic staging.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../services/download_service.dart' show FileCorruptedException;
import 'native_save_helper.dart';

/// Manages streaming chunk writes to a temporary staging file on disk with concurrent SHA-256 hashing.
class DownloadDiskWriter {
  /// Temporary staging file receiving chunk bytes on disk.
  final File stagingFile;

  /// Optional explicit target path (used when staging files for archive packaging).
  final String? explicitTargetPath;

  /// Original file name.
  final String filename;

  /// Target subpath category.
  final String? subpath;

  /// Conflict resolution policy.
  final DownloadConflictPolicy policy;

  late final RandomAccessFile _raf;
  late final AccumulatorSink<Digest> _hashOutput;
  late final ByteConversionSink _hashInput;

  DownloadDiskWriter._({
    required this.stagingFile,
    required this.filename,
    this.subpath,
    this.policy = DownloadConflictPolicy.overwrite,
    this.explicitTargetPath,
  });

  /// Factory initializing a disk writer on a newly created temporary staging file.
  static Future<DownloadDiskWriter> create({
    required String filename,
    String? subpath,
    DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
    String? explicitTargetPath,
  }) async {
    File staging;
    if (explicitTargetPath != null) {
      final target = File(explicitTargetPath);
      if (!target.parent.existsSync()) {
        await target.parent.create(recursive: true);
      }
      final rand = const Uuid().v4().substring(0, 8);
      staging = File('${target.path}.tmp_${DateTime.now().microsecondsSinceEpoch}_$rand');
    } else {
      staging = await createStagedTempFile(filename, subpath: subpath);
    }

    final writer = DownloadDiskWriter._(
      stagingFile: staging,
      filename: filename,
      subpath: subpath,
      policy: policy,
      explicitTargetPath: explicitTargetPath,
    );
    await writer._init();
    return writer;
  }

  Future<void> _init() async {
    _raf = await stagingFile.open(mode: FileMode.write);
    _hashOutput = AccumulatorSink<Digest>();
    _hashInput = sha256.startChunkedConversion(_hashOutput);
  }

  /// Appends a raw downloaded chunk to disk and updates progressive SHA-256.
  Future<void> appendChunk(Uint8List chunkBytes) async {
    await _raf.writeFrom(chunkBytes);
    _hashInput.add(chunkBytes);
  }

  /// Flushes disk writes, closes handles, validates SHA-256, and atomically promotes staging file to destination.
  Future<NativeSaveResult> closeAndFinalize(String expectedHash) async {
    await _raf.flush();
    await _raf.close();
    _hashInput.close();

    final actualHash = _hashOutput.events.single.toString();
    if (actualHash != expectedHash) {
      try {
        if (stagingFile.existsSync()) await stagingFile.delete();
      } catch (_) {}
      throw FileCorruptedException();
    }

    if (explicitTargetPath != null) {
      final dest = File(explicitTargetPath!);
      if (dest.existsSync()) {
        try {
          await dest.delete();
        } catch (_) {}
      }
      try {
        await stagingFile.rename(dest.path);
      } catch (_) {
        await stagingFile.copy(dest.path);
        try {
          if (stagingFile.existsSync()) await stagingFile.delete();
        } catch (_) {}
      }
      return NativeSaveResult(
        savedPath: dest.path,
        message: 'Saved to ${dest.path}',
        success: true,
      );
    } else {
      return await finalizeStagedFile(
        stagingFile,
        filename,
        subpath: subpath,
        policy: policy,
      );
    }
  }

  /// Aborts active stream writing and cleans up any partial staging file.
  Future<void> abort() async {
    try {
      await _raf.close();
    } catch (_) {}
    try {
      if (stagingFile.existsSync()) await stagingFile.delete();
    } catch (_) {}
  }
}
