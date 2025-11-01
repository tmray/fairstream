import 'package:flutter/material.dart';
import '../services/playback_manager.dart';

class NowPlayingBar extends StatefulWidget {
  final dynamic player; // kept for compatibility; not required
  const NowPlayingBar({super.key, this.player});

  @override
  State<NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<NowPlayingBar> {
  final PlaybackManager _mgr = PlaybackManager.instance;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _mgr.isPlaying,
      builder: (context, playing, _) {
        final theme = Theme.of(context);
        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(children: [
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String?>(
                valueListenable: _mgr.currentTitle,
                builder: (context, title, __) {
                  final text = title ?? (playing ? 'Playing' : 'Stopped');
                  return ValueListenableBuilder<String?>(
                    valueListenable: _mgr.currentArtist,
                    builder: (context, artist, __) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (playing && title != null && artist != null)
                            Text(
                              artist,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            IconButton(
              icon: Icon(
                playing ? Icons.pause : Icons.play_arrow,
                color: theme.colorScheme.onSurface,
              ),
              onPressed: () {
                if (playing) {
                  _mgr.pause();
                } else {
                  // If we have a current title (meaning a track was set), try
                  // to resume; otherwise attempt to start the last URL.
                  if (_mgr.currentTitle.value != null) {
                    _mgr.resume();
                  } else {
                    _mgr.playLast();
                  }
                }
              },
            ),
            IconButton(
              icon: Icon(
                Icons.stop,
                color: theme.colorScheme.onSurface.withValues(alpha: playing ? 1.0 : 0.5),
              ),
              onPressed: playing ? () => _mgr.stop() : null,
            ),
            const SizedBox(width: 8),
          ]),
        );
      },
    );
  }
}
