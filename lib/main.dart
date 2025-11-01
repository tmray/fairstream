import 'package:flutter/material.dart';
import 'widgets/now_playing_bar.dart';
import 'screens/home_screen.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'dart:io' show Platform, ProcessSignal;
import 'services/playback_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background audio (notifications / media controls)
  // just_audio_background and the underlying native just_audio plugin
  // are not available on all desktop targets by default (some plugin
  // implementations aren't registered for Linux). Initialize only on
  // platforms where it's supported.
  if (!(Platform.isLinux)) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.fairstream.channel.audio',
      androidNotificationChannelName: 'FairStream Audio',
      androidNotificationOngoing: true,
    );
  }

  // Configure the audio session for the app (allows system to manage audio focus)
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (e) {
    // Non-fatal: log and continue
    // On some platforms AudioSession may not be available or necessary
    debugPrint('AudioSession configuration failed: $e');
  }

  // Ensure we stop playback when the OS signals the process is terminating.
  // This helps with cleanup on app exit.
  try {
    ProcessSignal.sigint.watch().listen((_) {
      PlaybackManager.instance.stop();
    });
    ProcessSignal.sigterm.watch().listen((_) {
      PlaybackManager.instance.stop();
    });
    // SIGHUP is useful for terminal/daemon shutdowns on POSIX systems.
    ProcessSignal.sighup.watch().listen((_) {
      PlaybackManager.instance.stop();
    });
  } catch (e) {
    // Some platforms may not support all signals; ignore failures.
    debugPrint('Signal handlers not fully available: $e');
  }

  // ...existing code...

  runApp(const FairstreamApp());
}
class FairstreamApp extends StatefulWidget {
  const FairstreamApp({super.key});

  @override
  State<FairstreamApp> createState() => _FairstreamAppState();
}

class _FairstreamAppState extends State<FairstreamApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Ensure playback is stopped when the app state is disposed.
    // Use unawaited to avoid blocking dispose, but the stop method will kill mpv immediately
    PlaybackManager.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // For a music app, we want audio to continue playing in the background
    // The just_audio_background plugin handles media controls and notifications
    // So we don't pause when the app goes to background - music continues!
    // Users can pause using the notification controls or lock screen controls
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FairStreamApp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      builder: (context, child) {
        return Stack(
          children: [
            Padding(
              // Add padding at the bottom to account for playbar height
              padding: const EdgeInsets.only(bottom: kToolbarHeight),
              child: child ?? const SizedBox.shrink(),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: NowPlayingBar(player: PlaybackManager.instance.player),
            ),
          ],
        );
      },
    );
  }
}
