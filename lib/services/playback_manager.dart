import 'dart:async';
import 'dart:io' show Platform, Process, ProcessSignal, ProcessStartMode, File, Directory;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'listening_tracker.dart';

class PlaybackManager {
  PlaybackManager._internal() {
    _init();
  }
  static final PlaybackManager instance = PlaybackManager._internal();

  Future<void> _init() async {
    // On startup try to remove any stale mpv PID left by a prior run.
    try {
      if (await _pidFile.exists()) {
        final contents = await _pidFile.readAsString();
        final pid = int.tryParse(contents.trim());
        if (pid != null) {
          try {
            Process.killPid(pid, ProcessSignal.sigkill);
          } catch (_) {}
        }
        try {
          await _pidFile.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  AudioPlayer? _player;
  AudioPlayer? get player => _player;
  Process? _linuxProcess;
  String? _lastUrl;
  int? _lastDurationSeconds;
  int? _linuxPid;
  // PID file used to track a possibly-orphaned mpv process between runs.
  File get _pidFile => File('${Directory.systemTemp.path}/fairstream_mpv.pid');
  // Expose simple state notifiers so UI can reflect playback even when using
  // the external mpv fallback.
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<String?> currentTitle = ValueNotifier<String?>(null);
  final ValueNotifier<String?> currentArtist = ValueNotifier<String?>(null);
  final ValueNotifier<String?> currentArtwork = ValueNotifier<String?>(null);
  // Progress tracking
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration?> duration = ValueNotifier<Duration?>(null);
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  Timer? _posTimer; // Linux fallback approximate timer
  StreamSubscription<ProcessingState>? _procSub;

  // Listening time tracking
  final _listeningTracker = ListeningTracker();
  Timer? _trackingTimer;
  DateTime? _trackingStartTime;
  String? _trackingArtist;

  // Simple in-memory queue of tracks for album playback
  List<Track> _queue = <Track>[];
  int _currentIndex = -1;
  bool _userInitiatedStop = false;
  bool _isHandlingCompletion = false;
  // Serialize track switches to avoid overlapping starts
  Completer<void>? _switchCompleter;

  String? _currentAlbumArtwork;
  
  void setAlbumArtwork(String? artworkUrl) {
    _currentAlbumArtwork = artworkUrl;
  }

  Future<void> playQueue(List<Track> tracks, int startIndex, {String? albumArtwork}) async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) return;
    _queue = List<Track>.from(tracks);
    _currentIndex = startIndex;
    _currentAlbumArtwork = albumArtwork;
    final t = _queue[_currentIndex];
    await playUrl(t.url, title: t.title, durationSeconds: t.durationSeconds);
  }

  Future<void> next() async {
    debugPrint('next() called - current: $_currentIndex, queue: ${_queue.length}');
    if (_currentIndex >= 0 && _currentIndex + 1 < _queue.length) {
      _currentIndex++;
      final t = _queue[_currentIndex];
      debugPrint('Playing track $_currentIndex: ${t.title}');
      await playUrl(t.url, title: t.title, durationSeconds: t.durationSeconds);
    }
  }

  Future<void> previous() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      final t = _queue[_currentIndex];
      await playUrl(t.url, title: t.title, durationSeconds: t.durationSeconds);
    }
  }

  Future<void> _handleCompleted() async {
    // Prevent double-triggering from both timer and process exit
    if (_isHandlingCompletion) {
      debugPrint('Already handling completion, skipping... (flag already set)');
      return;
    }
    _isHandlingCompletion = true;
    
    debugPrint('=== Track completed. Current index: $_currentIndex, Queue length: ${_queue.length} ===');
    
    // Small delay to let any duplicate calls get blocked by the flag
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Auto-advance if more tracks are queued
    if (_currentIndex >= 0 && _currentIndex + 1 < _queue.length) {
      debugPrint('Auto-advancing from track $_currentIndex to ${_currentIndex + 1}');
      await next();
    } else {
      // End of queue
      debugPrint('End of queue reached');
      isPlaying.value = false;
      _posTimer?.cancel();
      position.value = Duration.zero;
      duration.value = null;
    }
    
    // Keep flag set for a bit longer to prevent any lingering triggers
    await Future.delayed(const Duration(milliseconds: 100));
    _isHandlingCompletion = false;
    debugPrint('=== Completion handling finished ===');
  }

  Future<void> _stopInternal() async {
    // Internal stop that doesn't set _userInitiatedStop flag
    if (Platform.isLinux) {
      try {
        if (_linuxProcess != null) {
          try {
            _linuxProcess?.kill(ProcessSignal.sigkill);
          } catch (_) {}
        }
        if (_linuxPid != null) {
          try {
            Process.killPid(_linuxPid!, ProcessSignal.sigkill);
          } catch (_) {}
          _linuxPid = null;
        }
        try {
          if (await _pidFile.exists()) await _pidFile.delete();
        } catch (_) {}
      } catch (_) {}
      _linuxProcess = null;
      isPlaying.value = false;
      _posTimer?.cancel();
      position.value = Duration.zero;
      duration.value = null;
      return;
    }
    isPlaying.value = false;
    position.value = Duration.zero;
    duration.value = null;
    await _player?.stop();
  }

  Future<void> playUrl(String url, {String? title, int? durationSeconds}) async {
    // Wait for any in-progress switch to complete
    while (_switchCompleter != null) {
      try {
        await _switchCompleter!.future;
      } catch (_) {
        break;
      }
    }
    // Create a new switch scope
    _switchCompleter = Completer<void>();
    // Set flag to prevent the kill of the previous process from triggering completion
    _isHandlingCompletion = true;
    debugPrint('playUrl() called - blocking completion handler during track switch');
    
    // Extract artist from URL filename (part before the dash)
    final filename = Uri.decodeComponent(url.split('/').last);
    String? artist;
    if (filename.contains('–')) {
      // Extract text before en-dash and after track number
      final beforeDash = filename.split('–').first.trim();
      // Remove leading track number (e.g., "01 " or "1 ")
      artist = beforeDash.replaceFirst(RegExp(r'^\d+\s+'), '').trim();
    } else if (filename.contains('-')) {
      final beforeDash = filename.split('-').first.trim();
      artist = beforeDash.replaceFirst(RegExp(r'^\d+\s+'), '').trim();
    }
    
    // If running on Linux desktop, use a lightweight external player as a
    // fallback (mpv) to avoid depending on a native just_audio plugin that
    // may not be registered. This keeps playback working during development.
    if (Platform.isLinux) {
      try {
        // Kill any previous process (internal, don't flag as user stop)
        await _stopInternal();
        // Give the OS a brief moment to reap the prior process, if any
        await Future.delayed(const Duration(milliseconds: 50));
        // reset progress
        position.value = Duration.zero;
        duration.value = durationSeconds != null && durationSeconds > 0
            ? Duration(seconds: durationSeconds)
            : null;
        // start mpv and mark playing.
        // Always use normal mode (not detached) so we can properly track when
        // mpv finishes playing. This allows auto-advance to work correctly.
        _linuxProcess = await Process.start(
          'mpv',
          ['--no-video', '--really-quiet', url],
          mode: ProcessStartMode.normal,
        );
        _linuxPid = _linuxProcess?.pid;
        // Record PID to disk so subsequent app runs can clean up or reuse.
        try {
          if (_linuxPid != null) {
            await _pidFile.writeAsString(_linuxPid.toString());
          }
        } catch (_) {}
        currentTitle.value = title ?? url.split('/').last;
        currentArtist.value = artist;
        currentArtwork.value = _currentAlbumArtwork;
        isPlaying.value = true;
        _lastUrl = url;
        _lastDurationSeconds = durationSeconds;
        
        // Start tracking listening time for this artist
        _startListeningTracking(artist);
        
        // Now that new track is started, allow completion handling for this track
        _isHandlingCompletion = false;
        debugPrint('New track started - re-enabling completion handler');
        
        // Start a lightweight timer to approximate progress when duration is known
        _posTimer?.cancel();
        if (duration.value != null) {
          _posTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
            if (duration.value == null) {
              t.cancel();
              return;
            }
            final d = duration.value!;
            final nextMs = position.value.inMilliseconds + 200;
            if (nextMs >= d.inMilliseconds) {
              position.value = d;
              t.cancel();
              // When we reach the end, trigger auto-advance
              debugPrint('[TIMER] Progress timer reached end of track');
              Future.microtask(() => _handleCompleted());
            } else {
              position.value = Duration(milliseconds: nextMs);
            }
          });
        }
        // Monitor mpv process exit - works in both detached and normal mode
        // In detached mode, this may not fire reliably, so we rely on the timer
        // completion as the primary mechanism
        _linuxProcess?.exitCode.then((code) async {
          debugPrint('[MPV EXIT] Process exited with code $code');
          _linuxProcess = null;
          _linuxPid = null;
          _posTimer?.cancel();
          // If the user pressed stop, don't auto-advance
          if (_userInitiatedStop) {
            debugPrint('[MPV EXIT] User initiated stop, not advancing');
            _userInitiatedStop = false;
            isPlaying.value = false;
            position.value = Duration.zero;
            duration.value = null;
          } else {
            // Treat as natural completion - but only if timer hasn't handled it
            debugPrint('[MPV EXIT] Triggering completion handler');
            await _handleCompleted();
          }
          try {
            if (await _pidFile.exists()) await _pidFile.delete();
          } catch (_) {}
        }).catchError((e) {
          debugPrint('Error monitoring mpv exit: $e');
        });
        // Complete switch scope for linux path
        _switchCompleter?.complete();
        _switchCompleter = null;
        return;
      } catch (e) {
        debugPrint('Linux fallback player failed: $e');
        // Fall through to try just_audio approach
      }
    }

    try {
      // Ensure audio session is configured for playback
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
      } catch (e) {
        // Non-fatal; continue
        debugPrint('AudioSession configure failed: $e');
      }

      // Use MediaItem tag so just_audio_background can show media controls/metadata
      final mediaItem = MediaItem(
        id: url,
        album: '',
        title: title ?? url.split('/').last,
        artist: artist,
        extras: {},
      );

      // Lazy-create the platform AudioPlayer only on supported platforms
      _player ??= AudioPlayer();
      // Cancel any previous playing subscription
      await _playingSub?.cancel();
      await _procSub?.cancel();
      await _posSub?.cancel();
      await _durSub?.cancel();
      _playingSub = _player!.playingStream.listen((playing) {
        isPlaying.value = playing;
      });
      _procSub = _player!.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          _handleCompleted();
        }
      });
      _posSub = _player!.positionStream.listen((p) {
        position.value = p;
      });
      _durSub = _player!.durationStream.listen((d) {
        duration.value = d;
      });

      final source = AudioSource.uri(Uri.parse(url), tag: mediaItem);
      await _player!.setAudioSource(source);
  currentTitle.value = mediaItem.title;
  currentArtist.value = artist;
  currentArtwork.value = _currentAlbumArtwork;
  _lastUrl = url;
  _lastDurationSeconds = durationSeconds;
  
  // Start tracking listening time for this artist
  _startListeningTracking(artist);
  
  // Stop any current just_audio playback explicitly before starting
  try { await _player!.stop(); } catch (_) {}
  await _player!.play();
      
      // Now that new track is started, allow completion handling for this track
      _isHandlingCompletion = false;
      debugPrint('New track started (just_audio) - re-enabling completion handler');
      // Complete switch scope for just_audio path
      _switchCompleter?.complete();
      _switchCompleter = null;
    } catch (e, st) {
      debugPrint('Playback error: $e\n$st');
      _switchCompleter?.completeError(e);
      _switchCompleter = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    _userInitiatedStop = true;
    _stopListeningTracking(); // Record final listening segment
    
    if (Platform.isLinux) {
      try {
        // Try direct Process.kill first
        if (_linuxProcess != null) {
          try {
            _linuxProcess?.kill(ProcessSignal.sigkill);
          } catch (_) {}
        }
        // PID-based fallback: attempt to kill by PID if we recorded one
        if (_linuxPid != null) {
          try {
            Process.killPid(_linuxPid!, ProcessSignal.sigkill);
          } catch (_) {}
          _linuxPid = null;
        }
        // Remove PID file if present
        try {
          if (await _pidFile.exists()) await _pidFile.delete();
        } catch (_) {}
      } catch (_) {}
      _linuxProcess = null;
      isPlaying.value = false;
      _posTimer?.cancel();
      position.value = Duration.zero;
      duration.value = null;
      return;
    }
    isPlaying.value = false;
    position.value = Duration.zero;
    duration.value = null;
    return _player?.stop();
  }

  Future<void> pause() async {
    if (Platform.isLinux) {
      // Attempt to suspend the external process. Try Process object first,
      // then fall back to PID-based signaling if needed.
      try {
        if (_linuxProcess != null) {
          try {
            _linuxProcess?.kill(ProcessSignal.sigstop);
          } catch (_) {}
        } else if (_linuxPid != null) {
          try {
            Process.killPid(_linuxPid!, ProcessSignal.sigstop);
          } catch (_) {}
        }
      } catch (_) {}
      isPlaying.value = false;
      _posTimer?.cancel();
      return;
    }
    isPlaying.value = false;
    return _player?.pause();
  }

  /// Resume playback for the external mpv fallback (SIGCONT) or the native player.
  Future<void> resume() async {
    if (Platform.isLinux) {
      // If we still have a process, send SIGCONT; otherwise restart last URL
      if (_linuxProcess != null || _linuxPid != null) {
        try {
          if (_linuxProcess != null) {
            try {
              _linuxProcess?.kill(ProcessSignal.sigcont);
            } catch (_) {}
          } else if (_linuxPid != null) {
            try {
              Process.killPid(_linuxPid!, ProcessSignal.sigcont);
            } catch (_) {}
          }
          isPlaying.value = true;
        } catch (_) {
          // ignore and fall back to restart
        }
        // restart timer if we have a duration
        if (duration.value != null) {
          _posTimer?.cancel();
          _posTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
            final d = duration.value!;
            final nextMs = position.value.inMilliseconds + 200;
            if (nextMs >= d.inMilliseconds) {
              position.value = d;
              t.cancel();
            } else {
              position.value = Duration(milliseconds: nextMs);
            }
          });
        }
        return;
      }
      // No process to resume: restart last known URL from beginning
      if (_lastUrl != null) {
        return playUrl(_lastUrl!, title: currentTitle.value, durationSeconds: _lastDurationSeconds);
      }
      return;
    }
    // Non-Linux (just_audio)
    if (_player == null) {
      if (_lastUrl != null) {
        return playUrl(_lastUrl!, title: currentTitle.value, durationSeconds: _lastDurationSeconds);
      }
      return;
    }
    final state = _player!.processingState;
    // If player is idle/completed (after stop), set source again by replaying last URL
    if (state == ProcessingState.idle || state == ProcessingState.completed) {
      if (_lastUrl != null) {
        return playUrl(_lastUrl!, title: currentTitle.value, durationSeconds: _lastDurationSeconds);
      }
      return;
    }
    isPlaying.value = true;
    return _player?.play();
  }

  /// Resume the last-played URL if available.
  Future<void> playLast() async {
    if (_lastUrl == null) return Future.value();
    return playUrl(_lastUrl!);
  }

  /// Start tracking listening time for the current artist
  void _startListeningTracking(String? artist) {
    if (artist == null || artist.trim().isEmpty) return;
    
    _stopListeningTracking(); // Stop any previous tracking
    
    _trackingArtist = artist;
    _trackingStartTime = DateTime.now();
    
    // Record listening time every 30 seconds
    _trackingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _recordListeningSegment();
    });
  }

  /// Stop tracking and record final segment
  void _stopListeningTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    
    // Record any remaining time
    _recordListeningSegment();
    
    _trackingArtist = null;
    _trackingStartTime = null;
  }

  /// Record the accumulated listening time since last checkpoint
  void _recordListeningSegment() {
    if (_trackingArtist == null || _trackingStartTime == null) return;
    
    final now = DateTime.now();
    final elapsed = now.difference(_trackingStartTime!).inSeconds;
    
    if (elapsed > 0) {
      _listeningTracker.recordListeningTime(_trackingArtist!, elapsed);
      _trackingStartTime = now; // Reset checkpoint
    }
  }

  /// Dispose any subscriptions/notifiers if needed by callers.
  void dispose() {
    _stopListeningTracking();
    _playingSub?.cancel();
    _procSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _posTimer?.cancel();
    isPlaying.dispose();
    currentTitle.dispose();
    currentArtist.dispose();
    currentArtwork.dispose();
    position.dispose();
    duration.dispose();
  }

  Future<void> seek(Duration pos) => _player?.seek(pos) ?? Future.value();
}
