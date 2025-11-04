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
        return Stack(
          children: [
            // Main bar background/content
            Container(
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
            const SizedBox(width: 8),
            // Album artwork thumbnail
            ValueListenableBuilder<String?>(
              valueListenable: _mgr.currentArtwork,
              builder: (context, artworkUrl, _) {
                return Container(
                  width: 48,
                  height: 48,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: artworkUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            artworkUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => Icon(
                              Icons.album,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : Icon(
                          Icons.album,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                );
              },
            ),
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
                          if (title != null && artist != null)
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
            ),
            // Progress bar at the very top of the play bar (drawn above)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<Duration?>(
                valueListenable: _mgr.duration,
                builder: (context, total, __) {
                  // If duration unknown but playing, show indeterminate bar
                  if ((total == null || total.inMilliseconds <= 0) && playing) {
                    return LinearProgressIndicator(
                      value: null,
                      minHeight: 3,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    );
                  }
                  if (total == null || total.inMilliseconds <= 0) {
                    return const SizedBox.shrink();
                  }
                  return ValueListenableBuilder<Duration>(
                    valueListenable: _mgr.position,
                    builder: (context, pos, ___) {
                      final denom = total.inMilliseconds == 0 ? 1 : total.inMilliseconds;
                      final frac = (pos.inMilliseconds / denom).clamp(0.0, 1.0);
                      return LinearProgressIndicator(
                        value: frac.isNaN ? 0.0 : frac,
                        minHeight: 3,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.primary,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
