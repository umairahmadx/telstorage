/*
 * File: audio_player_view_model.dart
 * Description: State management for AudioPlayerScreen coordinating playlist playback, streaming URL resolution, chunk buffer tracking, seeking, speed, and repeat modes.
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/models/lyric_line.dart';
import '../../../../../../core/services/lyrics_service.dart';
import '../../../../../../core/services/video_chunk_cache_manager.dart';
import '../../../../../../core/services/video_stream_server.dart';
import '../../../../../../core/utils/app_logger.dart';

/// Repeat modes for audio playlist playback.
enum AudioRepeatMode {
  off,
  all,
  one,
}

/// Manages audio playback lifecycle, playlist navigation, loopback proxy stream resolution,
/// chunk buffer merging, and playback speeds using media_kit Player.
class AudioPlayerViewModel extends ChangeNotifier {
  List<FileRecord> _playlist = const [];
  int _currentIndex = 0;
  Player? _player;

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

  List<LyricLine> _lyrics = const [];
  int _currentLyricIndex = -1;
  bool _isLoadingLyrics = false;
  Duration _lyricsOffset = Duration.zero;
  bool _isLyricsViewActive = false;

  StreamRegistration? _registration;
  int _initGeneration = 0;
  final List<StreamSubscription> _subscriptions = [];

  List<FileRecord> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  FileRecord? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length) ? _playlist[_currentIndex] : null;
  Player? get player => _player;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  Duration get position => _position;
  Duration get duration => _duration;
  List<DurationRange> get buffered => _buffered;
  Set<int> get cachedChunks => _cachedChunks;
  List<DurationRange> get mergedBuffered => _mergedBuffered;
  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;
  AudioRepeatMode get repeatMode => _repeatMode;
  String? get errorMessage => _errorMessage;

  List<LyricLine> get lyrics => _lyrics;
  int get currentLyricIndex => _currentLyricIndex;
  bool get isLoadingLyrics => _isLoadingLyrics;
  Duration get lyricsOffset => _lyricsOffset;
  bool get isLyricsViewActive => _isLyricsViewActive;

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
    _lyrics = const [];
    _currentLyricIndex = -1;
    _lyricsOffset = Duration.zero;
    _isLoadingLyrics = true;
    unawaited(_refreshCachedChunks(track.fileId));
    unawaited(loadLyricsForCurrentTrack());
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

      _cleanupPlayer();

      final p = Player(
        configuration: const PlayerConfiguration(
          osc: false,
          logLevel: MPVLogLevel.warn,
        ),
      );
      _player = p;

      _attachPlayerListeners();

      await p.setRate(_playbackSpeed);
      await p.open(Media(streamUrl), play: true);
      if (gen != _initGeneration) {
        _cleanupPlayer();
        return;
      }

      _isInitialized = true;
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

  void _attachPlayerListeners() {
    final p = _player;
    if (p == null) return;

    _subscriptions.add(p.stream.position.listen((pos) {
      _position = pos;
      _updateCurrentLyric();
      notifyListeners();
    }));

    _subscriptions.add(p.stream.duration.listen((dur) {
      _duration = dur;
      _computeMergedBuffered();
      notifyListeners();
    }));

    _subscriptions.add(p.stream.playing.listen((playing) {
      _isPlaying = playing;
      if (playing) {
        unawaited(WakelockPlus.enable().catchError((_) {}));
      } else {
        unawaited(WakelockPlus.disable().catchError((_) {}));
      }
      notifyListeners();
    }));

    _subscriptions.add(p.stream.buffering.listen((buffering) {
      _isBuffering = buffering;
      notifyListeners();
    }));

    _subscriptions.add(p.stream.buffer.listen((b) {
      _buffered = [DurationRange(Duration.zero, b)];
      _computeMergedBuffered();
      notifyListeners();
    }));

    _subscriptions.add(p.stream.completed.listen((completed) {
      if (completed) {
        _handleTrackEnded();
      }
    }));
  }

  void _handleTrackEnded() {
    if (_repeatMode == AudioRepeatMode.one) {
      seekTo(Duration.zero);
      play();
    } else if (_repeatMode == AudioRepeatMode.all || _currentIndex < _playlist.length - 1) {
      nextTrack();
    } else {
      _isPlaying = false;
      unawaited(WakelockPlus.disable().catchError((_) {}));
    }
  }

  /// Begins audio playback.
  void play() {
    _player?.play();
    _isPlaying = true;
    unawaited(WakelockPlus.enable().catchError((_) {}));
    notifyListeners();
  }

  /// Pauses audio playback.
  void pause() {
    _player?.pause();
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
    _player?.seek(clamped);
    notifyListeners();
  }

  /// Fast-forwards playback position by [delta] (defaults to 10 seconds).
  void skipForward([Duration delta = const Duration(seconds: 10)]) => seekTo(_position + delta);

  /// Rewinds playback position by [delta] (defaults to 10 seconds).
  void skipBackward([Duration delta = const Duration(seconds: 10)]) => seekTo(_position - delta);

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
    _player?.setVolume(_volume * 100.0);
    notifyListeners();
  }

  /// Sets the playback speed multiplier.
  Future<void> setSpeed(double speed) async {
    _playbackSpeed = speed;
    await _player?.setRate(speed);
    notifyListeners();
  }

  /// Cycles through repeat modes: off -> all -> one -> off.
  void toggleRepeat() {
    _repeatMode = switch (_repeatMode) {
      AudioRepeatMode.off => AudioRepeatMode.all,
      AudioRepeatMode.all => AudioRepeatMode.one,
      AudioRepeatMode.one => AudioRepeatMode.off,
    };
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

  void _cleanupPlayer() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _player?.dispose();
    _player = null;
  }

  /// Toggles visibility of the synchronized lyrics view.
  void toggleLyricsView() {
    _isLyricsViewActive = !_isLyricsViewActive;
    notifyListeners();
  }

  /// Automatically searches and loads lyrics for the currently active track.
  Future<void> loadLyricsForCurrentTrack() async {
    final track = currentTrack;
    if (track == null) return;
    _isLoadingLyrics = true;
    notifyListeners();

    try {
      final lines = await LyricsService.instance.fetchLyrics(
        filename: track.name,
        duration: _duration,
        fileId: track.fileId,
      );
      if (currentTrack?.fileId == track.fileId) {
        _lyrics = lines;
        _isLoadingLyrics = false;
        _updateCurrentLyric();
        notifyListeners();
      }
    } catch (_) {
      if (currentTrack?.fileId == track.fileId) {
        _isLoadingLyrics = false;
        notifyListeners();
      }
    }
  }

  /// Adjusts timing offset for lyrics synchronization.
  void adjustLyricsOffset(Duration delta) {
    _lyricsOffset += delta;
    _updateCurrentLyric();
    notifyListeners();
  }

  /// Resets lyrics timing offset to zero.
  void resetLyricsOffset() {
    _lyricsOffset = Duration.zero;
    _updateCurrentLyric();
    notifyListeners();
  }

  /// Overrides the current lyrics list directly.
  void setLyrics(List<LyricLine> newLyrics) {
    _lyrics = newLyrics;
    _updateCurrentLyric();
    notifyListeners();
  }

  /// Seeks audio playback directly to the timestamp of [index] lyric line.
  void seekToLyric(int index) {
    if (index >= 0 && index < _lyrics.length) {
      var target = _lyrics[index].timestamp - _lyricsOffset;
      if (target < Duration.zero) target = Duration.zero;
      seekTo(target);
    }
  }

  /// Prompts user to select a local .lrc file for the current track.
  Future<void> pickLocalLyrics() async {
    final track = currentTrack;
    final lines = await LyricsService.instance.pickLocalLyricsFile(
      cacheKey: track?.fileId,
    );
    if (lines != null && lines.isNotEmpty) {
      setLyrics(lines);
    }
  }

  void _updateCurrentLyric() {
    if (_lyrics.isEmpty) {
      _currentLyricIndex = -1;
      return;
    }
    final effective = _position + _lyricsOffset;
    int idx = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      if (_lyrics[i].timestamp <= effective) {
        idx = i;
      } else {
        break;
      }
    }
    _currentLyricIndex = idx;
  }

  @override
  void dispose() {
    _registration?.dispose();
    _registration = null;
    _cleanupPlayer();
    unawaited(WakelockPlus.disable().catchError((_) {}));
    super.dispose();
  }

  // -- Test Helpers -----------------------------------------------------------

  @visibleForTesting
  void setMockPositionForTesting(Duration pos) {
    _position = pos;
    _updateCurrentLyric();
    notifyListeners();
  }

  @visibleForTesting
  void setMockDurationForTesting(Duration dur) {
    _duration = dur;
    notifyListeners();
  }

  @visibleForTesting
  void setMockPlaylistForTesting(List<FileRecord> list, [int initialIndex = 0]) {
    _playlist = List.unmodifiable(list);
    _currentIndex = initialIndex.clamp(0, list.isEmpty ? 0 : list.length - 1);
    _isInitialized = true;
    notifyListeners();
  }
}
