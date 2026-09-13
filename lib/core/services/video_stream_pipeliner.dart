/*
 * File: video_stream_pipeliner.dart
 * Description: High-performance packet stream pipeliner delivering real-time network packets directly to video player sockets with concurrent disk caching.
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../models/chunk_info.dart';
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import 'service_locator.dart';
import 'telegram_rate_limiter.dart';
import 'video_chunk_cache_manager.dart';

/// Callback signature for mocking chunk streams during testing.
typedef StreamFetcher = Stream<List<int>> Function(String fileId, int chunkIndex);

/// Engine responsible for streaming incoming network packets directly to HTTP client
/// response sockets while concurrently appending them to local disk cache.
class VideoStreamPipeliner {
  StreamFetcher? _streamFetcherForTesting;

  /// Sets custom stream fetcher for unit testing isolation.
  void setStreamFetcherForTesting(StreamFetcher? fetcher) {
    _streamFetcherForTesting = fetcher;
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
      );
    }

    // 3. Setup temporary disk cache sink for concurrent caching
    final chunkDir = await VideoChunkCacheManager.instance.getChunkDir(record.fileId);
    final targetFile = File('${chunkDir.path}/chunk_$chunkIndex.part');
    final uniqueSuffix = '${DateTime.now().microsecondsSinceEpoch}_$chunkIndex';
    final tmpFile = File('${chunkDir.path}/chunk_${chunkIndex}_$uniqueSuffix.part.tmp');
    IOSink? fileSink;

    try {
      fileSink = tmpFile.openWrite();
    } catch (e) {
      AppLogger.w('Failed to open disk cache sink for ${record.fileId}: $e',
          tag: 'VideoStreamPipeliner');
    }

    var currentByteOffset = 0;
    var totalWritten = 0;

    try {
      await for (final packet in networkStream) {
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
          output.add(slice);
          totalWritten += slice.length;
          if (output is HttpResponse) {
            await output.flush();
          }
        }

        currentByteOffset += packet.length;
      }

      // Close and commit disk cache file if fully received
      if (fileSink != null) {
        try {
          await fileSink.flush();
          await fileSink.close();
          fileSink = null;

          if (tmpFile.existsSync() && tmpFile.lengthSync() > 0) {
            if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
              try {
                tmpFile.deleteSync();
              } catch (_) {}
            } else {
              await tmpFile.rename(targetFile.path);
              try {
                targetFile.setLastModifiedSync(DateTime.now());
              } catch (_) {}
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
      if (tmpFile.existsSync()) {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
      rethrow;
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
