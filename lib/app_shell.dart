import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'widgets/now_playing_bar.dart';
import 'services/playback_manager.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const HomeScreen(),
        // Positioned playbar at the bottom, always visible
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: NowPlayingBar(player: PlaybackManager.instance.player),
        ),
      ],
    );
  }
}
