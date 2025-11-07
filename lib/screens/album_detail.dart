import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_html/flutter_html.dart';
import '../models/album.dart';
import '../services/playback_manager.dart';
import '../widgets/playing_indicator.dart';
import 'artist_detail.dart';
import '../services/feed_metadata.dart';
import '../services/album_store.dart';

class AlbumDetail extends StatefulWidget {
  final Album album;
  final PlaybackManager playback;
  const AlbumDetail({super.key, required this.album, required this.playback});

  @override
  State<AlbumDetail> createState() => _AlbumDetailState();
}

class _AlbumDetailState extends State<AlbumDetail> {
  Album? _hydratedAlbum;
  // bool _loading = false;
  final ScrollController _moreByController = ScrollController();

  @override
  void initState() {
    super.initState();
    _hydrateMetadata();
  }

  Future<void> _hydrateMetadata() async {
  // setState(() => _loading = true);
    // Try to fetch richer metadata for this album
  final metaService = _getMetadataService();
  final meta = await metaService.findMetadataForAlbum(widget.album.id);
    if (!mounted) return;
    // Fallback cover heuristic: if metadata lacks an image or current cover looks like a banner,
    // derive album cover as https://host/slug/cover_480.jpg from album id or first track URL.
    String? fallbackCover() {
      Uri? u;
      try {
        u = Uri.parse(widget.album.id.split('#').first);
      } catch (_) {}
      if (u == null || u.host.isEmpty || u.pathSegments.isEmpty || u.pathSegments.first == 'playlist.m3u') {
        if (widget.album.tracks.isNotEmpty) {
          try {
            final t = Uri.parse(widget.album.tracks.first.url);
            if (t.host.isNotEmpty && t.pathSegments.isNotEmpty) {
              u = Uri(scheme: t.scheme, host: t.host, pathSegments: [t.pathSegments.first, 'cover_480.jpg']);
            }
          } catch (_) {}
        }
      } else {
        u = Uri(scheme: u.scheme, host: u.host, pathSegments: [u.pathSegments.first, 'cover_480.jpg']);
      }
      return u?.toString();
    }

  final pickedCover = (meta?.imageUrl?.isNotEmpty == true)
    ? meta!.imageUrl
    : (fallbackCover() ?? widget.album.coverUrl);

    setState(() {
      _hydratedAlbum = Album(
        id: widget.album.id,
        title: widget.album.title, // Keep M3U album title
        artist: widget.album.artist, // Keep M3U artist
        coverUrl: pickedCover,
        tracks: widget.album.tracks,
        description: (meta != null && (meta.description?.isNotEmpty == true)) ? meta.description : widget.album.description,
        published: (meta != null && (meta.published?.isNotEmpty == true)) ? meta.published : widget.album.published,
      );
    });
  // setState(() => _loading = false);
  }

  FeedMetadataService _getMetadataService() {
    return FeedMetadataService();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final album = _hydratedAlbum ?? widget.album;
    return Scaffold(
      appBar: AppBar(
        title: Text(album.title),
        actions: [
          IconButton(
            tooltip: 'Fix track titles',
            icon: const Icon(Icons.format_list_bulleted),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final store = AlbumStore();
              final ok = await store.repairTrackTitlesFromM3U(album);
              if (!mounted) return;
              if (ok) {
                final refreshed = await AlbumStore().getAllAlbums();
                final now = refreshed.firstWhere((a) => a.id == album.id, orElse: () => album);
                setState(() {
                  _hydratedAlbum = now;
                });
                messenger.showSnackBar(const SnackBar(content: Text('Track titles repaired from M3U')));
              } else {
                messenger.showSnackBar(const SnackBar(content: Text('No track title changes found')));
              }
            },
          ),
          IconButton(
            tooltip: 'Fix cover',
            icon: const Icon(Icons.image_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final store = AlbumStore();
              final ok = await store.repairCoverForAlbum(album);
              if (!mounted) return;
              if (ok) {
                // Rehydrate local state from storage
                // Reload from storage to pick up updated cover
                final refreshed = await AlbumStore().getAllAlbums();
                final now = refreshed.firstWhere((a) => a.id == album.id, orElse: () => album);
                setState(() {
                  _hydratedAlbum = now;
                });
                messenger.showSnackBar(const SnackBar(content: Text('Cover updated from M3U')));
              } else {
                messenger.showSnackBar(const SnackBar(content: Text('No cover change needed')));
              }
            },
          ),
        ],
      ),
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
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () {
                  final key = album.artist.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ArtistDetail(
                        artistKey: key,
                        displayName: album.artist,
                      ),
                    ),
                  );
                },
                child: Text(
                  album.artist,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
              if (album.description != null) ...[
                const SizedBox(height: 8),
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
              valueListenable: widget.playback.currentTitle,
              builder: (context, currentTitle, _) {
                final isPlaying = currentTitle == t.title;
                return ValueListenableBuilder<bool>(
                  valueListenable: widget.playback.isPlaying,
                  builder: (context, playing, _) {
                    return ListTile(
                      leading: IconButton(
                        icon: (isPlaying && playing)
                            ? const PlayingIndicator()
                            : const Icon(Icons.play_arrow),
                        onPressed: () => widget.playback.playQueue(
                          album.tracks, 
                          i,
                          albumArtwork: album.coverUrl,
                        ),
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
        const SizedBox(height: 8),
        // More by this artist
        FutureBuilder<List<Album>>(
          future: AlbumStore().getAllAlbums(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final all = snapshot.data!;
            final artistKey = album.artist.trim().toLowerCase();
            final others = all
                .where((a) => a.id != album.id && a.artist.trim().toLowerCase() == artistKey)
                .toList();
            if (others.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    'More by ${album.artist}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                SizedBox(
                  height: 170,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                      scrollbars: true,
                    ),
                    child: Scrollbar(
                      controller: _moreByController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _moreByController,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        scrollDirection: Axis.horizontal,
                        itemCount: others.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final a = others[index];
                          return InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AlbumDetail(album: a, playback: widget.playback),
                                ),
                              );
                            },
                            child: SizedBox(
                              width: 120,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AspectRatio(
                                    aspectRatio: 1,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: (a.coverUrl != null && a.coverUrl!.isNotEmpty)
                                          ? Image.network(
                                              a.coverUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stack) => Container(
                                                color: theme.colorScheme.surfaceContainerHighest,
                                                child: Icon(
                                                  Icons.album,
                                                  color: theme.colorScheme.onSurface,
                                                ),
                                              ),
                                            )
                                          : Container(
                                              color: theme.colorScheme.surfaceContainerHighest,
                                              child: Icon(
                                                Icons.album,
                                                color: theme.colorScheme.onSurface,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    a.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: kToolbarHeight),
              ],
            );
          },
        ),
          ],
        ),
      ),
    );
  }
}
