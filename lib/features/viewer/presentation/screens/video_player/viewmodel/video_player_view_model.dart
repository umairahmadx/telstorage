/*
 * File: video_player_view_model.dart
 * Description: State management for VideoPlayerScreen coordinating playback state, seeking, buffering ranges, wakelock, and control visibility.
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/services/video_stream_server.dart';
import '../../../../../../core/utils/app_logger.dart';

/// Manages playback lifecycle, streaming URL resolution, seek commands,
/// and interactive toolbar auto-hiding for video playback.
class VideoPlayerViewModel extends ChangeNotifier {
  FileRecord? _currentFile;
  VideoPlayerController? _controller;

  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<DurationRange> _buffered = const [];
  double _volume = 1.0;
  bool _areControlsVisible = true;
  String? _errorMessage;

  Timer? _hideControlsTimer;

  /// Currently loaded FileRecord.
  FileRecord? get currentFile => _currentFile;

  /// Underlying VideoPlayerController.
  VideoPlayerController? get controller => _controller;

  /// Whether the player is ready to render video frames.
  bool get isInitialized => _isInitialized;

  /// Whether video is currently playing.
  bool get isPlaying => _isPlaying;

  /// Whether video is currently waiting on chunk buffering.
  bool get isBuffering => _isBuffering;

  /// Current playback timestamp.
  Duration get position => _position;

  /// Total duration of the video.
  Duration get duration => _duration;

  /// List of loaded/buffered duration segments.
  List<DurationRange> get buffered => _buffered;

  /// Current audio volume between 0.0 and 1.0.
  double get volume => _volume;

  /// Whether playback controls and navigation bars are visible.
  bool get areControlsVisible => _areControlsVisible;

  /// Active error message, if playback initialization failed.
  String? get errorMessage => _errorMessage;

  StreamRegistration? _registration;
  int _initGeneration = 0;

  /// Initializes the video controller with the proxy loopback stream URL for [file].
  Future<void> initialize(FileRecord file) async {
    final gen = ++_initGeneration;
    _registration?.dispose();
    _registration = null;

    _currentFile = file;
    _errorMessage = null;
    _isInitialized = false;
    _isPlaying = false;
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
      AppLogger.i('Initializing video stream: $streamUrl', tag: 'VideoPlayerViewModel');

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

      ctrl.addListener(_onControllerStateChanged);
      startAutoHideTimer();
      notifyListeners();
    } catch (e) {
      if (gen != _initGeneration) return;
      AppLogger.e('Failed to initialize video player: $e', tag: 'VideoPlayerViewModel');
      _registration?.dispose();
      _registration = null;
      _currentFile = null;
      _errorMessage = 'Could not load video: $e';
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
      notifyListeners();
    }
  }

  /// Begins video playback and engages wakelock to prevent screen sleep.
  void play() {
    _controller?.play();
    _isPlaying = true;
    unawaited(WakelockPlus.enable().catchError((_) {}));
    startAutoHideTimer();
    notifyListeners();
  }

  /// Pauses video playback and disengages screen wakelock.
  void pause() {
    _controller?.pause();
    _isPlaying = false;
    unawaited(WakelockPlus.disable().catchError((_) {}));
    showControlsTemporarily();
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

  /// Seeks to a specific [target] playback duration with boundary clamping.
  void seekTo(Duration target) {
    var clamped = target;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (_duration > Duration.zero && clamped > _duration) clamped = _duration;

    _position = clamped;
    _controller?.seekTo(clamped);
    showControlsTemporarily();
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

  /// Updates audio volume (clamped between 0.0 and 1.0).
  void setVolume(double vol) {
    _volume = vol.clamp(0.0, 1.0);
    _controller?.setVolume(_volume);
    notifyListeners();
  }

  /// Toggles interactive control visibility.
  void toggleControls() {
    if (_areControlsVisible) {
      hideControls();
    } else {
      showControlsTemporarily();
    }
  }

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

  /// Sets mock duration for unit tests.
  void setMockDurationForTesting(Duration d) {
    _duration = d;
  }

  /// Sets mock position for unit tests.
  void setMockPositionForTesting(Duration p) {
    _position = p;
  }

  @override
  void dispose() {
    _initGeneration++;
    _hideControlsTimer?.cancel();
    unawaited(WakelockPlus.disable().catchError((_) {}));
    _registration?.dispose();
    _registration = null;
    _currentFile = null;
    if (_controller != null) {
      _controller!.removeListener(_onControllerStateChanged);
      _controller!.dispose();
      _controller = null;
    }
    super.dispose();
  }
}
