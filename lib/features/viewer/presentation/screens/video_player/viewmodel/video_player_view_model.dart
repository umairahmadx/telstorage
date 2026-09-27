/*
 * File: video_player_view_model.dart
 * Description: State management for VideoPlayerScreen coordinating media_kit playback, tracks, speed, subtitles, seeking, and control visibility.
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/services/video_stream_server.dart';
import '../../../../../../core/utils/app_logger.dart';
import 'video_buffer_sync_controller.dart';
import 'video_drag_scrubber.dart';

/// Manages media_kit playback lifecycle, streaming resolution, audio/subtitle tracks, speed, and viewport scrub state.
class VideoPlayerViewModel extends ChangeNotifier {
  FileRecord? _currentFile;
  Player? _player;
  VideoController? _videoController;

  bool _isInitialized = false, _isPlaying = false, _isBuffering = false;
  bool _forceSoftwareDecoding = false;
  Duration _position = Duration.zero, _duration = Duration.zero;
  List<DurationRange> _buffered = const [];
  double _volume = 1.0, _playbackSpeed = 1.0;
  int? _videoWidth, _videoHeight;
  bool _areControlsVisible = true;
  String? _errorMessage;

  final _bufferSync = VideoBufferSyncController();

  List<AudioTrack> _audioTracks = const [];
  AudioTrack? _selectedAudioTrack;
  List<SubtitleTrack> _subtitleTracks = const [];
  SubtitleTrack? _selectedSubtitleTrack;
  Duration _subtitleDelay = Duration.zero;

  final _scrubber = VideoDragScrubber();

  Timer? _hideControlsTimer;
  final List<StreamSubscription> _subscriptions = [];

  FileRecord? get currentFile => _currentFile;
  Player? get player => _player;
  VideoController? get videoController => _videoController;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  Duration get position => _position;
  Duration get duration => _duration;
  List<DurationRange> get buffered => _buffered;
  Set<int> get cachedChunks => _bufferSync.cachedChunks;
  int get totalChunks => _currentFile?.chunkCount ?? 1;
  double get cachedMb => _bufferSync.computeCachedMb(_currentFile?.sizeMb);
  double get totalMb => _currentFile?.sizeMb ?? 0.0;
  List<DurationRange> get mergedBuffered => _bufferSync.mergedBuffered;
  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;
  int? get videoWidth => _videoWidth;
  int? get videoHeight => _videoHeight;
  double? get naturalAspectRatio =>
      (_videoWidth != null && _videoHeight != null && _videoHeight! > 0)
          ? (_videoWidth! / _videoHeight!)
          : null;
  bool get areControlsVisible => _areControlsVisible;
  String? get errorMessage => _errorMessage;

  List<AudioTrack> get audioTracks => _audioTracks;
  AudioTrack? get selectedAudioTrack => _selectedAudioTrack;
  List<SubtitleTrack> get subtitleTracks => _subtitleTracks;
  SubtitleTrack? get selectedSubtitleTrack => _selectedSubtitleTrack;
  Duration get subtitleDelay => _subtitleDelay;

  bool get isDragging => _scrubber.isDragging;
  Duration get dragTarget => _scrubber.dragTarget;
  Duration get dragDelta => _scrubber.dragDelta;
  bool get isSoftwareDecoding => _forceSoftwareDecoding;

  StreamRegistration? _registration;
  int _initGeneration = 0;

  /// Initializes the video controller with the proxy loopback stream URL for [file].
  Future<void> initialize(
    FileRecord file, {
    bool preserveSoftwareDecoding = false,
    Duration? resumePosition,
  }) async {
    final gen = ++_initGeneration;
    _registration?.dispose();
    _registration = null;

    if (!preserveSoftwareDecoding) {
      _forceSoftwareDecoding = false;
    }
    _currentFile = file;
    _errorMessage = null;
    _isInitialized = false;
    _isPlaying = false;
    _bufferSync.reset();
    _bufferSync.attach(
      fileId: file.fileId,
      totalChunks: file.chunkCount,
      onUpdateCallback: () {
        _bufferSync.compute(_duration, _buffered);
        notifyListeners();
      },
    );
    unawaited(_bufferSync.refresh(file.fileId, _duration, _buffered).then((_) => notifyListeners()));
    notifyListeners();

    try {
      await VideoStreamServer.instance.start();
      if (gen != _initGeneration) return;

      final reg = VideoStreamServer.instance.registerFile(file);
      if (gen != _initGeneration) {
        reg.dispose();
        return;
      }
      _registration = reg;

      final streamUrl = VideoStreamServer.instance.getStreamUrl(file.fileId, file.name);
      AppLogger.i('Initializing video stream: $streamUrl (softwareFallback: $_forceSoftwareDecoding)', tag: 'VideoPlayerViewModel');

      _cleanupPlayer();

      final p = Player(
        configuration: const PlayerConfiguration(
          osc: false,
          logLevel: MPVLogLevel.warn,
        ),
      );
      try {
        final platform = (p.platform as dynamic);
        await platform?.setProperty('network-timeout', '60');
        await platform?.setProperty('demuxer-lavf-o', 'timeout=60000000');
        await platform?.setProperty('cache-on-disk', 'no');
      } catch (_) {}
      final vc = VideoController(
        p,
        configuration: VideoControllerConfiguration(
          hwdec: _forceSoftwareDecoding ? 'no' : null,
          enableHardwareAcceleration: !_forceSoftwareDecoding,
        ),
      );
      _player = p;
      _videoController = vc;
      _attachPlayerListeners();
      notifyListeners();

      await p.open(Media(streamUrl), play: true);
      if (gen != _initGeneration) {
        _cleanupPlayer();
        return;
      }

      _isInitialized = true;
      if (resumePosition != null && resumePosition > Duration.zero) {
        seekTo(resumePosition);
      }
      startAutoHideTimer();
      notifyListeners();
    } catch (e, st) {
      if (gen != _initGeneration) return;
      if (!_forceSoftwareDecoding && isHardwareDecodeError(e.toString()) && _currentFile != null) {
        AppLogger.w('Hardware initialization error ($e). Retrying with software decoding...', tag: 'VideoPlayerViewModel');
        _forceSoftwareDecoding = true;
        unawaited(initialize(_currentFile!, preserveSoftwareDecoding: true, resumePosition: resumePosition));
        return;
      }
      AppLogger.e('Failed to initialize video player: $e', tag: 'VideoPlayerViewModel', error: e, stackTrace: st);
      _registration?.dispose();
      _registration = null;
      _currentFile = null;
      _errorMessage = 'Could not load video: $e';
      notifyListeners();
    }
  }

  void _attachPlayerListeners() {
    final p = _player;
    if (p == null) return;

    _subscriptions.add(p.stream.position.listen((pos) {
      _position = pos;
      notifyListeners();
    }));

    _subscriptions.add(p.stream.duration.listen((dur) {
      _duration = dur;
      _bufferSync.compute(_duration, _buffered);
      notifyListeners();
    }));

    _subscriptions.add(p.stream.playing.listen((playing) {
      _isPlaying = playing;
      if (playing) {
        unawaited(WakelockPlus.enable().catchError((_) {}));
        startAutoHideTimer();
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
      _bufferSync.compute(_duration, _buffered);
      notifyListeners();
    }));

    _subscriptions.add(p.stream.tracks.listen((tracks) {
      _audioTracks = tracks.audio;
      _subtitleTracks = tracks.subtitle;
      notifyListeners();
    }));

    _subscriptions.add(p.stream.track.listen((track) {
      _selectedAudioTrack = track.audio;
      _selectedSubtitleTrack = track.subtitle;
      notifyListeners();
    }));

    _subscriptions.add(p.stream.rate.listen((rate) {
      _playbackSpeed = rate;
      notifyListeners();
    }));

    _subscriptions.add(p.stream.volume.listen((vol) {
      _volume = vol / 100.0;
      notifyListeners();
    }));

    _subscriptions.add(p.stream.width.listen((w) {
      _videoWidth = w;
      notifyListeners();
    }));

    _subscriptions.add(p.stream.height.listen((h) {
      _videoHeight = h;
      notifyListeners();
    }));

    _subscriptions.add(p.stream.log.listen((event) {
      if (event.level == 'warn' || event.level == 'error') {
        final isBenign = event.text.contains('native_window are NULL') ||
            event.text.contains('plaintext playlist') ||
            event.text.contains('file cache');
        if (isBenign) {
          AppLogger.d('[mpv ${event.level}] [${event.prefix}] ${event.text}', tag: 'MediaKit');
        } else {
          AppLogger.w('[mpv ${event.level}] [${event.prefix}] ${event.text}', tag: 'MediaKit');
        }
      }
    }));

    _subscriptions.add(p.stream.error.listen((err) {
      if (err.isNotEmpty) {
        if (!_forceSoftwareDecoding && isHardwareDecodeError(err) && _currentFile != null) {
          AppLogger.w('Hardware decoding error encountered: "$err". Falling back to software decoding (hwdec: no)...', tag: 'VideoPlayerViewModel');
          _forceSoftwareDecoding = true;
          final savedPos = _position;
          unawaited(initialize(_currentFile!, preserveSoftwareDecoding: true, resumePosition: savedPos));
          return;
        }
        _errorMessage = err;
        AppLogger.e('MediaKit Player Error: $err', tag: 'VideoPlayerViewModel');
        notifyListeners();
      }
    }));
  }

  /// Begins video playback.
  void play() {
    _player?.play();
    _isPlaying = true;
    unawaited(WakelockPlus.enable().catchError((_) {}));
    startAutoHideTimer();
    notifyListeners();
  }

  /// Pauses video playback.
  void pause() {
    _player?.pause();
    _isPlaying = false;
    unawaited(WakelockPlus.disable().catchError((_) {}));
    showControlsTemporarily();
    notifyListeners();
  }

  /// Toggles between play and pause states.
  void togglePlay() => _isPlaying ? pause() : play();

  /// Seeks to a specific [target] playback duration with boundary clamping.
  void seekTo(Duration target) {
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration ? _duration : target);
    _position = clamped;
    _player?.seek(clamped);
    showControlsTemporarily();
    notifyListeners();
  }

  /// Fast-forwards playback position by [delta] (defaults to 10 seconds).
  void skipForward([Duration delta = const Duration(seconds: 10)]) => seekTo(_position + delta);

  /// Rewinds playback position by [delta] (defaults to 10 seconds).
  void skipBackward([Duration delta = const Duration(seconds: 10)]) => seekTo(_position - delta);

  /// Updates audio volume (clamped between 0.0 and 1.0).
  void setVolume(double vol) {
    _volume = vol.clamp(0.0, 1.0);
    _player?.setVolume(_volume * 100.0);
    notifyListeners();
  }

  /// Updates playback rate (e.g. 0.5x to 2.0x).
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    await _player?.setRate(speed);
    notifyListeners();
  }

  /// Changes the active audio track.
  Future<void> setAudioTrack(AudioTrack track) async {
    _selectedAudioTrack = track;
    await _player?.setAudioTrack(track);
    notifyListeners();
  }

  /// Changes the active subtitle track.
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    _selectedSubtitleTrack = track;
    await _player?.setSubtitleTrack(track);
    notifyListeners();
  }

  /// Loads an external subtitle file into media_kit player.
  Future<void> loadExternalSubtitle(String filePath, {String? title}) async {
    final trackName = title ?? filePath.split(Platform.pathSeparator).last;
    final isUri = filePath.startsWith('file://') || filePath.startsWith('http');
    final fileUri = isUri ? filePath : Uri.file(filePath).toString();
    final track = SubtitleTrack.uri(fileUri, title: trackName);
    await setSubtitleTrack(track);
  }

  /// Adjusts subtitle synchronization delay (+/- duration offset).
  Future<void> adjustSubtitleDelay(Duration delta) async {
    _subtitleDelay += delta;
    if (_player != null) {
      try {
        final seconds = _subtitleDelay.inMilliseconds / 1000.0;
        await (_player!.platform as dynamic)?.setProperty('sub-delay', seconds.toString());
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Initiates viewport horizontal drag scrubbing.
  void onDragStart() {
    _scrubber.start(_position);
    notifyListeners();
  }

  /// Updates viewport drag scrubbing with responsive sensitivity.
  void onDragUpdate(double deltaPixels, double totalWidth) {
    if (_scrubber.update(deltaPixels, totalWidth, _duration)) {
      notifyListeners();
    }
  }

  /// Concludes viewport drag scrubbing and seeks to target position.
  void onDragEnd() {
    if (_scrubber.isDragging) {
      final target = _scrubber.end();
      seekTo(target);
      notifyListeners();
    }
  }

  /// Manually triggers fallback to software decoding for the current video.
  Future<void> fallbackToSoftwareDecoding() async {
    if (_currentFile == null) return;
    _forceSoftwareDecoding = true;
    final savedPos = _position;
    await initialize(_currentFile!, preserveSoftwareDecoding: true, resumePosition: savedPos);
  }

  /// Checks if [errorText] represents a hardware acceleration or codec binding error.
  static bool isHardwareDecodeError(String errorText) {
    final lower = errorText.toLowerCase();
    return lower.contains('mediacodec') ||
        lower.contains('decoder') ||
        lower.contains('hwdec') ||
        lower.contains('surface') ||
        lower.contains('hardware acceleration') ||
        lower.contains('omx') ||
        lower.contains('codec init failed');
  }

  /// Toggles interactive control visibility.
  void toggleControls() => _areControlsVisible ? hideControls() : showControlsTemporarily();

  /// Immediately hides playback controls.
  void hideControls() {
    _hideControlsTimer?.cancel();
    _areControlsVisible = false;
    notifyListeners();
  }

  /// Reveals controls and resets the 3-second auto-hide countdown.
  void showControlsTemporarily() {
    _areControlsVisible = true;
    startAutoHideTimer();
    notifyListeners();
  }

  /// Initiates or restarts the 3-second timer to auto-hide controls.
  void startAutoHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (_isPlaying) {
        _areControlsVisible = false;
        notifyListeners();
      }
    });
  }

  /// Sets mock in-flight prefetch progress for unit testing.
  void setMockInFlightProgressForTesting({required Map<int, double> fractions, required int bytes}) {
    _bufferSync.setMockInFlightProgress(fractions: fractions, bytes: bytes);
    _bufferSync.compute(_duration, _buffered);
    notifyListeners();
  }

  /// Sets mock cached chunks for unit tests.
  void setMockCachedChunksForTesting(Set<int> chunks) {
    _bufferSync.setMockCachedChunks(chunks);
    _bufferSync.compute(_duration, _buffered);
    notifyListeners();
  }

  /// Sets mock duration for unit tests.
  void setMockDurationForTesting(Duration d) {
    _duration = d;
    _bufferSync.compute(_duration, _buffered);
    notifyListeners();
  }

  /// Sets mock position for unit tests.
  void setMockPositionForTesting(Duration p) => _position = p;

  /// Sets mock video dimensions for unit tests.
  void setMockDimensionsForTesting(int w, int h) {
    _videoWidth = w;
    _videoHeight = h;
  }

  /// Sets mock player and controller for unit tests.
  void setPlayerForTesting(Player p, VideoController vc) {
    _player = p;
    _videoController = vc;
    _isInitialized = true;
    _attachPlayerListeners();
  }

  void _cleanupPlayer() {
    for (final s in _subscriptions) { s.cancel(); }
    _subscriptions.clear();
    _player?.dispose();
    _player = null;
    _videoController = null;
  }

  @override
  void dispose() {
    _initGeneration++;
    _hideControlsTimer?.cancel();
    unawaited(WakelockPlus.disable().catchError((_) {}));
    _bufferSync.dispose();
    _registration?.dispose();
    _registration = null;
    _currentFile = null;
    _cleanupPlayer();
    super.dispose();
  }
}
