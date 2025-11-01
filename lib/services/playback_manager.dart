import 'dart:async';
import 'dart:io' show Platform, Process, ProcessSignal, ProcessStartMode, File, Directory;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_background/just_audio_background.dart';

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
  int? _linuxPid;
  // PID file used to track a possibly-orphaned mpv process between runs.
  File get _pidFile => File('${Directory.systemTemp.path}/fairstream_mpv.pid');
  // Expose simple state notifiers so UI can reflect playback even when using
  // the external mpv fallback.
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<String?> currentTitle = ValueNotifier<String?>(null);
  final ValueNotifier<String?> currentArtist = ValueNotifier<String?>(null);
  // Progress tracking
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration?> duration = ValueNotifier<Duration?>(null);
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  Timer? _posTimer; // Linux fallback approximate timer

  Future<void> playUrl(String url, {String? title, int? durationSeconds}) async {
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
        // Kill any previous process
        await stop();
        // reset progress
        position.value = Duration.zero;
        duration.value = durationSeconds != null && durationSeconds > 0
            ? Duration(seconds: durationSeconds)
            : null;
        // start mpv and mark playing.
        // Use a detached process only during development (when running under
        // flutter tooling) so the player doesn't get killed by tooling
        // reconnects; in release/profile builds start mpv attached so that it
        // exits with the app process.
        final mode = kDebugMode ? ProcessStartMode.detached : ProcessStartMode.normal;
        _linuxProcess = await Process.start(
          'mpv',
          ['--no-video', '--really-quiet', url],
          mode: mode,
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
        isPlaying.value = true;
        // Start a lightweight timer to approximate progress when duration is known
        _posTimer?.cancel();
        if (duration.value != null) {
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
        // For detached processes, exitCode may not be meaningful in the same
        // way; attempt to observe it when available but don't rely on it.
        try {
          _linuxProcess?.exitCode.then((code) async {
            debugPrint('mpv exited with $code');
            isPlaying.value = false;
            currentTitle.value = null;
            _linuxProcess = null;
            _linuxPid = null;
            _posTimer?.cancel();
            position.value = Duration.zero;
            duration.value = null;
            try {
              if (await _pidFile.exists()) await _pidFile.delete();
            } catch (_) {}
          });
        } catch (_) {}
        _lastUrl = url;
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
      await _posSub?.cancel();
      await _durSub?.cancel();
      _playingSub = _player!.playingStream.listen((playing) {
        isPlaying.value = playing;
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
  _lastUrl = url;
      await _player!.play();
    } catch (e, st) {
      debugPrint('Playback error: $e\n$st');
      rethrow;
    }
  }

  Future<void> stop() async {
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
      currentTitle.value = null;
      currentArtist.value = null;
      _posTimer?.cancel();
      position.value = Duration.zero;
      duration.value = null;
      return;
    }
    isPlaying.value = false;
    currentTitle.value = null;
    currentArtist.value = null;
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
        // ignore
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
    isPlaying.value = true;
    return _player?.play();
  }

  /// Resume the last-played URL if available.
  Future<void> playLast() async {
    if (_lastUrl == null) return Future.value();
    return playUrl(_lastUrl!);
  }

  /// Dispose any subscriptions/notifiers if needed by callers.
  void dispose() {
    _playingSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _posTimer?.cancel();
    isPlaying.dispose();
    currentTitle.dispose();
    currentArtist.dispose();
    position.dispose();
    duration.dispose();
  }

  Future<void> seek(Duration pos) => _player?.seek(pos) ?? Future.value();
}
