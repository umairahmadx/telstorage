/*
 * File: video_stream_pipeliner.dart
 * Description: High-performance packet stream pipeliner delivering real-time network packets directly to video player sockets with concurrent disk caching.
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import '../models/chunk_info.dart';
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import 'app_cache_manager.dart';
import 'in_flight_chunk_registry.dart';
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
    InFlightChunkRegistry.instance.cancelForFile(fileId);
    final tokens = _activeTokens.remove(fileId);
    if (tokens != null) {
      for (final token in tokens) {
        token.cancel('Streaming cancelled for $fileId');
      }
    }
  }

  /// Cancels all active network streams across all files.
  void cancelAll() {
    InFlightChunkRegistry.instance.cancelAll();
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
      final expectedSize = _resolveExpectedChunkSize(record, chunkIndex, chunkMap);
      if (fileSize < expectedSize) {
        AppLogger.w(
          'Cached chunk $chunkIndex for ${record.fileId} incomplete ($fileSize < $expectedSize bytes). Purging corrupt chunk.',
          tag: 'VideoStreamPipeliner',
        );
        try { cachedChunk.deleteSync(); } catch (_) {}
      } else {
        final boundedStart = sliceStart.clamp(0, fileSize);
        final boundedEnd = sliceEnd.clamp(boundedStart, fileSize);

        if (boundedEnd > boundedStart) {
          AppLogger.i(
            '[PIPELINE_DISK_HIT] Serving chunk $chunkIndex for ${record.fileId} '
            'slice=$boundedStart..$boundedEnd (${boundedEnd - boundedStart} bytes) from disk cache',
            tag: 'VideoStreamPipeliner',
          );
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

      InFlightChunkTask? inFlightTask = InFlightChunkRegistry.instance.get(record.fileId, chunkIndex);
      if (inFlightTask != null && !inFlightTask.isFinished) {
        AppLogger.i(
          '[PIPELINE_DEDUP_WAIT] Awaiting active in-flight chunk download for ${record.fileId} chunk $chunkIndex',
          tag: 'VideoStreamPipeliner',
        );
        File? completedFile;
        try {
          completedFile = await inFlightTask.completionFuture;
        } catch (_) {}

        final cached = completedFile ?? await VideoChunkCacheManager.instance.getCachedChunk(record.fileId, chunkIndex);
        if (cached != null && cached.existsSync()) {
          final fileSize = cached.lengthSync();
          final boundedStart = sliceStart.clamp(0, fileSize);
          final boundedEnd = sliceEnd.clamp(boundedStart, fileSize);
          if (boundedEnd > boundedStart) {
            final stream = cached.openRead(boundedStart, boundedEnd);
            await for (final chunk in stream) {
              output.add(chunk);
              if (output is HttpResponse) await output.flush();
            }
            return boundedEnd - boundedStart;
          }
          return 0;
        }
      }

      final Stream<List<int>> networkStream;
      final bool isTaskOwner;
      if (_streamFetcherForTesting != null) {
        networkStream = _streamFetcherForTesting!(record.fileId, chunkIndex);
        inFlightTask = InFlightChunkRegistry.instance.register(record.fileId, chunkIndex, cancelToken: token);
        isTaskOwner = true;
      } else {
        final remoteFileId = _resolveChunkFileId(record, chunkIndex, chunkMap);
        if (remoteFileId == null || remoteFileId.isEmpty) {
          throw StateError('Cannot resolve Telegram fileId for ${record.fileId} chunk $chunkIndex');
        }
        AppLogger.i(
          '[PIPELINE_NET_START] Streaming chunk $chunkIndex for ${record.fileId} '
          'slice=$sliceStart..$sliceEnd from Telegram (priority: $priority)',
          tag: 'VideoStreamPipeliner',
        );
        networkStream = await ServiceLocator.instance.telegram.streamByFileId(
          remoteFileId,
          priority: priority,
          cancelToken: token,
        );
        inFlightTask = InFlightChunkRegistry.instance.register(record.fileId, chunkIndex, cancelToken: token);
        isTaskOwner = true;
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
      var isStreamComplete = false;

      final completer = Completer<int>();
      late StreamSubscription<List<int>> subscription;

      subscription = networkStream.listen(
        (packet) {
          if (token.isCancelled) {
            subscription.cancel();
            if (!completer.isCompleted) completer.complete(totalWritten);
            return;
          }

          if (isTaskOwner) {
            inFlightTask?.addPacket(packet);
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
              if (totalWritten == 0 && slice.isNotEmpty) {
                AppLogger.i(
                  '[PIPELINE_FIRST_PACKET] Received first packet for chunk $chunkIndex '
                  'of ${record.fileId} (${slice.length} bytes)',
                  tag: 'VideoStreamPipeliner',
                );
              }
              output.add(slice);
              totalWritten += slice.length;
              if (totalWritten >= (sliceEnd - sliceStart)) {
                if (!completer.isCompleted) completer.complete(totalWritten);
              }
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
          if (isTaskOwner) {
            inFlightTask?.fail(err, st);
          }
          if (!completer.isCompleted) {
            if (token.isCancelled || (err is DioException && err.type == DioExceptionType.cancel)) {
              completer.complete(totalWritten);
            } else {
              completer.completeError(err, st);
            }
          }
        },
        onDone: () {
          isStreamComplete = true;
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
        if (!isStreamComplete && !token.isCancelled) {
          await Future.delayed(Duration.zero);
        }
      } finally {
        if (token.isCancelled || isStreamComplete) {
          await subscription.cancel();
        }
      }

        // Close and commit disk cache file if fully received and not cancelled
        if (fileSink != null) {
          try {
            await fileSink.flush();
            await fileSink.close();
            fileSink = null;

            final expectedSize = _resolveExpectedChunkSize(record, chunkIndex, chunkMap);
            final isFullyCached = isStreamComplete ||
                (tmpFile.existsSync() && tmpFile.lengthSync() >= expectedSize);

            if (token.isCancelled || !isFullyCached) {
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
                if (isTaskOwner) {
                  inFlightTask.complete(targetFile);
                }
                AppLogger.i(
                  '[PIPELINE_COMMIT] Chunk $chunkIndex for ${record.fileId} committed to disk '
                  '(${targetFile.lengthSync()} bytes)',
                  tag: 'VideoStreamPipeliner',
                );
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
    if (chunkMap != null && chunkMap.isNotEmpty) {
      final isZeroBased = chunkMap.containsKey(0) && !chunkMap.containsKey(chunkMap.length);
      final key = isZeroBased ? chunkIndex : (chunkIndex + 1);
      final target = chunkMap[key];
      if (target != null && target.fileId != null && target.fileId!.isNotEmpty) {
        return target.fileId;
      }
    }

    if (record.chunkCount == 1 && chunkIndex == 0 && record.fileId.isNotEmpty && !record.fileId.contains('-')) {
      return record.fileId;
    }

    return null;
  }

  /// Resolves the expected total byte length of a chunk to verify integrity before caching.
  int _resolveExpectedChunkSize(
    FileRecord record,
    int chunkIndex,
    Map<int, ChunkInfo>? chunkMap,
  ) {
    if (chunkMap != null && chunkMap.isNotEmpty) {
      final isZeroBased = chunkMap.containsKey(0) && !chunkMap.containsKey(chunkMap.length);
      final key = isZeroBased ? chunkIndex : (chunkIndex + 1);
      final target = chunkMap[key];
      if (target != null && target.sizeMb > 0) {
        return (target.sizeMb * 1024 * 1024).round();
      }
    }

    final totalBytes = max(1, (record.sizeMb * 1024 * 1024).round());
    if (record.chunkCount <= 1) {
      return totalBytes;
    }

    const defaultPartSize = 19 * 1024 * 1024;
    if (chunkIndex == record.chunkCount - 1) {
      final remainder = totalBytes - (chunkIndex * defaultPartSize);
      return remainder > 0 ? remainder : defaultPartSize;
    }
    return defaultPartSize;
  }

  /// Visible for unit testing chunk fileId resolution.
  String? resolveChunkFileIdForTesting(
    FileRecord record,
    int chunkIndex,
    Map<int, ChunkInfo>? chunkMap,
  ) => _resolveChunkFileId(record, chunkIndex, chunkMap);
}
