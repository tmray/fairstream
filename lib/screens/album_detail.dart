import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../models/album.dart';
import '../services/playback_manager.dart';
import '../widgets/playing_indicator.dart';

class AlbumDetail extends StatelessWidget {
  final Album album;
  final PlaybackManager playback;
  const AlbumDetail({super.key, required this.album, required this.playback});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(album.title)),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (album.coverUrl != null)
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        album.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => 
                          Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Center(child: Icon(
                              Icons.album,
                              size: 48,
                              color: theme.colorScheme.onSurface,
                            )),
                          ),
                      ),
                    ),
                  ),
                ),
              ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                album.artist,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
              if (album.description != null) ...[
                const SizedBox(height: 8),
                // Use a Container to avoid layout issues with Html widget
                SizedBox(
                  width: double.infinity,
                  child: Html(
                    data: album.description!,
                    style: {
                      "body": Style(
                        color: theme.colorScheme.onSurface,
                        fontSize: FontSize(theme.textTheme.bodyMedium?.fontSize ?? 16),
                        fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                        margin: Margins.zero,
                        padding: HtmlPaddings.zero,
                      ),
                    },
                  ),
                ),
              ],
              if (album.published != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Published: ${album.published}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: kToolbarHeight + 16),
          itemCount: album.tracks.length,
          itemBuilder: (c, i) {
            final t = album.tracks[i];
            return ValueListenableBuilder<String?>(
              valueListenable: playback.currentTitle,
              builder: (context, currentTitle, _) {
                final isPlaying = currentTitle == t.title;
                return ValueListenableBuilder<bool>(
                  valueListenable: playback.isPlaying,
                  builder: (context, playing, _) {
                    return ListTile(
                      leading: IconButton(
                        icon: (isPlaying && playing)
                            ? const PlayingIndicator()
                            : const Icon(Icons.play_arrow),
                        onPressed: () => playback.playUrl(t.url, title: t.title),
                      ),
                      title: Row(
                        children: [
                          Text(
                            '${i + 1}. ',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              t.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
          ],
        ),
      ),
    );
  }
}
