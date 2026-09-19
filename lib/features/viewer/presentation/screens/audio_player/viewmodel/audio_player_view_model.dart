/*
 * File: audio_player_view_model.dart
 * Description: State management for AudioPlayerScreen coordinating playlist playback, streaming URL resolution, chunk buffer tracking, seeking, speed, and repeat modes.
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/services/video_chunk_cache_manager.dart';
import '../../../../../../core/services/video_stream_server.dart';
import '../../../../../../core/utils/app_logger.dart';

/// Repeat modes for audio playlist playback.
enum AudioRepeatMode {
  /// Playback stops after the last track in the playlist.
  off,

  /// Entire playlist repeats continuously from the beginning.
  all,

  /// Current track loops indefinitely.
  one,
}

/// Manages audio playback lifecycle, playlist navigation, loopback proxy stream resolution,
/// chunk buffer merging, and playback speeds.
class AudioPlayerViewModel extends ChangeNotifier {
  List<FileRecord> _playlist = const [];
  int _currentIndex = 0;
  VideoPlayerController? _controller;

  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<DurationRange> _buffered = const [];
  Set<int> _cachedChunks = const {};
  List<DurationRange> _mergedBuffered = const [];
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  AudioRepeatMode _repeatMode = AudioRepeatMode.off;
  String? _errorMessage;

  StreamRegistration? _registration;
  int _initGeneration = 0;

  /// Ordered playlist of viewable audio files.
  List<FileRecord> get playlist => _playlist;

  /// Index of currently selected track.
  int get currentIndex => _currentIndex;

  /// Currently loaded FileRecord.
  FileRecord? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : null;

  /// Underlying VideoPlayerController used for audio stream rendering.
  VideoPlayerController? get controller => _controller;

  /// Whether the audio player is initialized and ready to play.
  bool get isInitialized => _isInitialized;

  /// Whether audio is currently playing.
  bool get isPlaying => _isPlaying;

  /// Whether audio is currently buffering chunks.
  bool get isBuffering => _isBuffering;

  /// Current playback timestamp.
  Duration get position => _position;

  /// Total duration of the track.
  Duration get duration => _duration;

  /// Loaded/buffered duration segments directly from the player.
  List<DurationRange> get buffered => _buffered;

  /// Downloaded 19 MB chunk indices on disk.
  Set<int> get cachedChunks => _cachedChunks;

  /// Combined buffered duration ranges merging disk chunks with player buffer.
  List<DurationRange> get mergedBuffered => _mergedBuffered;

  /// Current audio volume between 0.0 and 1.0.
  double get volume => _volume;

  /// Current playback speed multiplier.
  double get playbackSpeed => _playbackSpeed;

  /// Active repeat mode.
  AudioRepeatMode get repeatMode => _repeatMode;

  /// Error message, if initialization or playback failed.
  String? get errorMessage => _errorMessage;

  /// Initializes the player with a [playlist] and begins streaming [initialIndex].
  Future<void> initialize(List<FileRecord> playlist, int initialIndex) async {
    _playlist = List.unmodifiable(playlist);
    _currentIndex = initialIndex.clamp(0, playlist.isEmpty ? 0 : playlist.length - 1);
    if (_playlist.isEmpty) {
      _isInitialized = false;
      notifyListeners();
      return;
    }
    await _loadTrack(_currentIndex);
  }

  /// Loads and starts streaming the track at [index].
  Future<void> _loadTrack(int index) async {
    final gen = ++_initGeneration;
    _registration?.dispose();
    _registration = null;

    if (index < 0 || index >= _playlist.length) return;
    _currentIndex = index;
    final track = _playlist[index];

    _errorMessage = null;
    _isInitialized = false;
    _isPlaying = false;
    _cachedChunks = const {};
    _mergedBuffered = const [];
    unawaited(_refreshCachedChunks(track.fileId));
    notifyListeners();

    try {
      await VideoStreamServer.instance.start();
      if (gen != _initGeneration) return;

      final reg = VideoStreamServer.instance.registerFile(track);
      if (gen != _initGeneration) {
        reg.dispose();
        return;
      }
      _registration = reg;

      final streamUrl = VideoStreamServer.instance.getStreamUrl(track.fileId, track.name);
      AppLogger.i('Initializing audio stream: $streamUrl', tag: 'AudioPlayerViewModel');

      final ctrl = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
      if (gen != _initGeneration) {
        ctrl.dispose();
        return;
      }

      final oldCtrl = _controller;
      _controller = ctrl;
      oldCtrl?.removeListener(_onControllerStateChanged);
      oldCtrl?.dispose();

      await ctrl.initialize();
      if (gen != _initGeneration) {
        ctrl.removeListener(_onControllerStateChanged);
        ctrl.dispose();
        return;
      }

      _isInitialized = true;
      _duration = ctrl.value.duration;
      _volume = ctrl.value.volume;
      await ctrl.setPlaybackSpeed(_playbackSpeed);

      ctrl.addListener(_onControllerStateChanged);
      _computeMergedBuffered();
      await ctrl.play();
      _isPlaying = true;
      unawaited(WakelockPlus.enable().catchError((_) {}));
      notifyListeners();
    } catch (e) {
      if (gen != _initGeneration) return;
      AppLogger.e('Failed to initialize audio track: $e', tag: 'AudioPlayerViewModel');
      _registration?.dispose();
      _registration = null;
      _errorMessage = 'Could not load audio: $e';
      notifyListeners();
    }
  }

  void _onControllerStateChanged() {
    if (_controller == null) return;
    final val = _controller!.value;

    final hasChanges = _isPlaying != val.isPlaying ||
        _isBuffering != val.isBuffering ||
        _position != val.position ||
        _duration != val.duration ||
        _buffered != val.buffered;

    if (hasChanges) {
      _isPlaying = val.isPlaying;
      _isBuffering = val.isBuffering;
      _position = val.position;
      _duration = val.duration;
      _buffered = val.buffered;
      _computeMergedBuffered();

      // Check for track completion
      if (_duration > Duration.zero &&
          _position >= _duration &&
          !val.isPlaying &&
          !_isBuffering) {
        _handleTrackEnded();
      }

      notifyListeners();
    }
  }

  void _handleTrackEnded() {
    switch (_repeatMode) {
      case AudioRepeatMode.one:
        seekTo(Duration.zero);
        play();
        break;
      case AudioRepeatMode.all:
        nextTrack();
        break;
      case AudioRepeatMode.off:
        if (_currentIndex < _playlist.length - 1) {
          nextTrack();
        } else {
          _isPlaying = false;
          unawaited(WakelockPlus.disable().catchError((_) {}));
        }
        break;
    }
  }

  /// Begins audio playback and enables wakelock.
  void play() {
    _controller?.play();
    _isPlaying = true;
    unawaited(WakelockPlus.enable().catchError((_) {}));
    notifyListeners();
  }

  /// Pauses audio playback and disengages screen wakelock.
  void pause() {
    _controller?.pause();
    _isPlaying = false;
    unawaited(WakelockPlus.disable().catchError((_) {}));
    notifyListeners();
  }

  /// Toggles between play and pause states.
  void togglePlay() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  /// Seeks to a specific [target] timestamp with boundary clamping.
  void seekTo(Duration target) {
    var clamped = target;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (_duration > Duration.zero && clamped > _duration) clamped = _duration;

    _position = clamped;
    _controller?.seekTo(clamped);
    notifyListeners();
  }

  /// Fast-forwards playback position by [delta] (defaults to 10 seconds).
  void skipForward([Duration delta = const Duration(seconds: 10)]) {
    seekTo(_position + delta);
  }

  /// Rewinds playback position by [delta] (defaults to 10 seconds).
  void skipBackward([Duration delta = const Duration(seconds: 10)]) {
    seekTo(_position - delta);
  }

  /// Skips to the next track in the playlist.
  Future<void> nextTrack() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex < _playlist.length - 1) {
      await _loadTrack(_currentIndex + 1);
    } else if (_repeatMode == AudioRepeatMode.all) {
      await _loadTrack(0);
    }
  }

  /// Skips to the previous track or restarts the current track if > 3 seconds in.
  Future<void> previousTrack() async {
    if (_playlist.isEmpty) return;
    if (_position.inSeconds > 3) {
      seekTo(Duration.zero);
      return;
    }
    if (_currentIndex > 0) {
      await _loadTrack(_currentIndex - 1);
    } else if (_repeatMode == AudioRepeatMode.all) {
      await _loadTrack(_playlist.length - 1);
    } else {
      seekTo(Duration.zero);
    }
  }

  /// Switches directly to track at [index].
  Future<void> selectTrack(int index) async {
    if (index >= 0 && index < _playlist.length && index != _currentIndex) {
      await _loadTrack(index);
    }
  }

  /// Adjusts volume between 0.0 and 1.0.
  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _controller?.setVolume(_volume);
    notifyListeners();
  }

  /// Sets the playback speed multiplier.
  Future<void> setSpeed(double speed) async {
    _playbackSpeed = speed;
    await _controller?.setPlaybackSpeed(speed);
    notifyListeners();
  }

  /// Cycles through repeat modes: off -> all -> one -> off.
  void toggleRepeat() {
    switch (_repeatMode) {
      case AudioRepeatMode.off:
        _repeatMode = AudioRepeatMode.all;
        break;
      case AudioRepeatMode.all:
        _repeatMode = AudioRepeatMode.one;
        break;
      case AudioRepeatMode.one:
        _repeatMode = AudioRepeatMode.off;
        break;
    }
    notifyListeners();
  }

  Future<void> _refreshCachedChunks(String fileId) async {
    try {
      final cached = await VideoChunkCacheManager.instance.getCachedChunkIndices(fileId);
      _cachedChunks = cached;
      _computeMergedBuffered();
      notifyListeners();
    } catch (_) {}
  }

  void _computeMergedBuffered() {
    if (_duration <= Duration.zero) {
      _mergedBuffered = _buffered;
      return;
    }

    final track = currentTrack;
    final totalChunks = track?.chunkCount ?? 1;
    if (totalChunks <= 0 || _cachedChunks.isEmpty) {
      _mergedBuffered = _buffered;
      return;
    }

    final msPerChunk = _duration.inMilliseconds / totalChunks;
    final ranges = <DurationRange>[..._buffered];

    for (final chunkIdx in _cachedChunks) {
      final start = Duration(milliseconds: (chunkIdx * msPerChunk).round());
      final end = Duration(milliseconds: ((chunkIdx + 1) * msPerChunk).round().clamp(0, _duration.inMilliseconds));
      ranges.add(DurationRange(start, end));
    }

    ranges.sort((a, b) => a.start.compareTo(b.start));

    final merged = <DurationRange>[];
    for (final r in ranges) {
      if (merged.isEmpty) {
        merged.add(r);
      } else {
        final last = merged.last;
        if (r.start <= last.end) {
          final newEnd = r.end > last.end ? r.end : last.end;
          merged[merged.length - 1] = DurationRange(last.start, newEnd);
        } else {
          merged.add(r);
        }
      }
    }
    _mergedBuffered = merged;
  }

  @override
  void dispose() {
    _registration?.dispose();
    _registration = null;
    _controller?.removeListener(_onControllerStateChanged);
    _controller?.dispose();
    _controller = null;
    unawaited(WakelockPlus.disable().catchError((_) {}));
    super.dispose();
  }

  // -- Test Helpers -----------------------------------------------------------

  /// Sets mock position for unit testing boundary conditions.
  @visibleForTesting
  void setMockPositionForTesting(Duration pos) {
    _position = pos;
    notifyListeners();
  }

  /// Sets mock duration for unit testing boundary conditions.
  @visibleForTesting
  void setMockDurationForTesting(Duration dur) {
    _duration = dur;
    notifyListeners();
  }

  /// Sets mock playlist for testing.
  @visibleForTesting
  void setMockPlaylistForTesting(List<FileRecord> list, [int initialIndex = 0]) {
    _playlist = List.unmodifiable(list);
    _currentIndex = initialIndex.clamp(0, list.isEmpty ? 0 : list.length - 1);
    _isInitialized = true;
    notifyListeners();
  }
}
