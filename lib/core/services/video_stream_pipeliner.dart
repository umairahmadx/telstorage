/*
 * File: video_stream_pipeliner.dart
 * Description: High-performance packet stream pipeliner delivering real-time network packets directly to video player sockets with concurrent disk caching.
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/chunk_info.dart';
import '../models/file_record.dart';
import '../models/video_stream_models.dart';
import '../utils/app_logger.dart';
import 'app_cache_manager.dart';
import 'service_locator.dart';
import 'telegram_rate_limiter.dart';
import 'video_chunk_cache_manager.dart';

/// Callback signature for mocking chunk streams during testing.
typedef StreamFetcher = Stream<List<int>> Function(String fileId, int chunkIndex);

/// Engine responsible for streaming incoming network packets directly to HTTP client
/// response sockets while concurrently appending them to local disk cache.
class VideoStreamPipeliner {
  StreamFetcher? _streamFetcherForTesting;
  final Map<String, Set<CancelToken>> _activeTokens = {};

  /// Sets custom stream fetcher for unit testing isolation.
  void setStreamFetcherForTesting(StreamFetcher? fetcher) {
    _streamFetcherForTesting = fetcher;
  }

  /// Cancels any active network streams for [fileId] and cleans up.
  void cancelForFile(String fileId) {
    final tokens = _activeTokens.remove(fileId);
    if (tokens != null) {
      for (final token in tokens) {
        token.cancel('Streaming cancelled for $fileId');
      }
    }
  }

  /// Cancels all active network streams across all files.
  void cancelAll() {
    final all = _activeTokens.values.expand((s) => s).toList();
    _activeTokens.clear();
    for (final token in all) {
      token.cancel('All streaming cancelled');
    }
  }

  /// Pipes the requested byte slice of a specific chunk directly to [output].
  ///
  /// If the chunk is already cached on local disk, reads directly from disk at bus speed.
  /// If the chunk is not cached, opens a streaming connection to Telegram, forwards
  /// matching packet slices immediately to [output], and persists the complete chunk
  /// to disk cache for future reads.
  /// Returns the number of bytes written to [output].
  Future<int> pipeChunkRange({
    required FileRecord record,
    required int chunkIndex,
    required int sliceStart,
    required int sliceEnd,
    required StreamSink<List<int>> output,
    Map<int, ChunkInfo>? chunkMap,
    RequestPriority priority = RequestPriority.immediate,
  }) async {
    // 1. Fast path: Check local disk cache
    final cachedChunk = await VideoChunkCacheManager.instance.getCachedChunk(
      record.fileId,
      chunkIndex,
    );

    if (cachedChunk != null && cachedChunk.existsSync()) {
      final fileSize = cachedChunk.lengthSync();
      final boundedStart = sliceStart.clamp(0, fileSize);
      final boundedEnd = sliceEnd.clamp(boundedStart, fileSize);

      if (boundedEnd > boundedStart) {
        final stream = cachedChunk.openRead(boundedStart, boundedEnd);
        await for (final chunk in stream) {
          output.add(chunk);
          if (output is HttpResponse) {
            await output.flush();
          }
        }
        return boundedEnd - boundedStart;
      }
      return 0;
    }

    // 2. Network streaming path: Resolve stream source
    final token = CancelToken();
    _activeTokens.putIfAbsent(record.fileId, () => {}).add(token);

    IOSink? fileSink;
    File? tmpFile;
    var totalWritten = 0;

    try {
      if (output is HttpResponse) {
        output.done.catchError((_) {
          token.cancel('Client connection closed');
        });
      }

      final Stream<List<int>> networkStream;
      if (_streamFetcherForTesting != null) {
        networkStream = _streamFetcherForTesting!(record.fileId, chunkIndex);
      } else {
        final remoteFileId = _resolveChunkFileId(record, chunkIndex, chunkMap);
        if (remoteFileId == null || remoteFileId.isEmpty) {
          throw StateError('Cannot resolve Telegram fileId for ${record.fileId} chunk $chunkIndex');
        }
        networkStream = await ServiceLocator.instance.telegram.streamByFileId(
          remoteFileId,
          priority: priority,
          cancelToken: token,
        );
      }

      // 3. Setup temporary disk cache sink for concurrent caching
      final chunkDir = await VideoChunkCacheManager.instance.getChunkDir(record.fileId);
      final targetFile = File('${chunkDir.path}/chunk_$chunkIndex.part');
      final uniqueSuffix = '${DateTime.now().microsecondsSinceEpoch}_$chunkIndex';
      tmpFile = File('${chunkDir.path}/chunk_${chunkIndex}_$uniqueSuffix.part.tmp');

      try {
        fileSink = tmpFile.openWrite();
      } catch (e) {
        AppLogger.w('Failed to open disk cache sink for ${record.fileId}: $e',
            tag: 'VideoStreamPipeliner');
      }

      var currentByteOffset = 0;

      final completer = Completer<int>();
      late StreamSubscription<List<int>> subscription;

      subscription = networkStream.listen(
        (packet) {
          if (token.isCancelled) {
            subscription.cancel();
            if (!completer.isCompleted) completer.complete(totalWritten);
            return;
          }

          if (chunkIndex == 0 && currentByteOffset == 0 && record.chunkCount > 1) {
            final header = ZipHeaderInfo.tryParse(Uint8List.fromList(packet));
            if (header != null && header.compressionMethod != 0) {
              subscription.cancel();
              if (!completer.isCompleted) {
                completer.completeError(
                  UnsupportedError('Unsupported compression method: ${header.compressionMethod}'),
                );
              }
              return;
            }
          }

          // Concurrently append full packet to disk cache
          if (fileSink != null) {
            try {
              fileSink.add(packet);
            } catch (_) {}
          }

          // Forward matching packet slice directly to player socket
          final packetStart = currentByteOffset;
          final packetEnd = currentByteOffset + packet.length;
          final overlapStart = max(packetStart, sliceStart);
          final overlapEnd = min(packetEnd, sliceEnd);

          if (overlapEnd > overlapStart) {
            final slice = packet.sublist(
              overlapStart - packetStart,
              overlapEnd - packetStart,
            );
            try {
              output.add(slice);
              totalWritten += slice.length;
            } catch (_) {
              token.cancel('Output socket write error');
              subscription.cancel();
              if (!completer.isCompleted) completer.complete(totalWritten);
              return;
            }
          }

          currentByteOffset += packet.length;
        },
        onError: (err, st) {
          if (!completer.isCompleted) {
            if (token.isCancelled || (err is DioException && err.type == DioExceptionType.cancel)) {
              completer.complete(totalWritten);
            } else {
              completer.completeError(err, st);
            }
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(totalWritten);
        },
        cancelOnError: true,
      );

      token.whenCancel.then((_) {
        subscription.cancel();
        if (!completer.isCompleted) completer.complete(totalWritten);
      });

      try {
        await completer.future;
      } finally {
        await subscription.cancel();
      }

        // Close and commit disk cache file if fully received and not cancelled
        if (fileSink != null) {
          try {
            await fileSink.flush();
            await fileSink.close();
            fileSink = null;

            if (token.isCancelled) {
              if (tmpFile.existsSync()) {
                try {
                  tmpFile.deleteSync();
                } catch (_) {}
              }
            } else if (tmpFile.existsSync() && tmpFile.lengthSync() > 0) {
              if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
                try {
                  tmpFile.deleteSync();
                } catch (_) {}
              } else {
                await tmpFile.rename(targetFile.path);
                try {
                  targetFile.setLastModifiedSync(DateTime.now());
                } catch (_) {}
                VideoChunkCacheManager.instance.chunkChangeNotifier.value++;
                AppCacheManager.instance.notifyCacheChanged();
                unawaited(VideoChunkCacheManager.instance.evictOldestIfNeeded(
                  activeFileId: record.fileId,
                ));
              }
            }
          } catch (e) {
            AppLogger.w('Failed to commit cached chunk to disk: $e',
                tag: 'VideoStreamPipeliner');
          }
        }

        return totalWritten;
      } catch (e) {
        if (fileSink != null) {
          try {
            await fileSink.close();
          } catch (_) {}
        }
        if (tmpFile != null && tmpFile.existsSync()) {
          try {
            tmpFile.deleteSync();
          } catch (_) {}
        }
        if (token.isCancelled || (e is DioException && e.type == DioExceptionType.cancel)) {
          return totalWritten;
        }
        rethrow;
      } finally {
        final tokens = _activeTokens[record.fileId];
      if (tokens != null) {
        tokens.remove(token);
        if (tokens.isEmpty) _activeTokens.remove(record.fileId);
      }
    }
  }

  /// Resolves the remote Telegram fileId from record or chunk mapping.
  String? _resolveChunkFileId(
    FileRecord record,
    int chunkIndex,
    Map<int, ChunkInfo>? chunkMap,
  ) {
    if (chunkMap != null) {
      final target = chunkMap[chunkIndex + 1] ?? chunkMap[chunkIndex];
      if (target != null && target.fileId != null && target.fileId!.isNotEmpty) {
        return target.fileId;
      }
    }

    if (record.chunkCount == 1 && chunkIndex == 0 && record.fileId.isNotEmpty) {
      return record.fileId;
    }

    return null;
  }
}
