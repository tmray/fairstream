import 'package:flutter/material.dart';
import '../services/album_store.dart';
import '../models/album.dart';
import '../services/playback_manager.dart';
import '../services/feed_metadata.dart';
import 'package:url_launcher/url_launcher.dart';
import 'album_detail.dart';

class ArtistDetail extends StatefulWidget {
  const ArtistDetail({super.key, required this.artistKey, required this.displayName});

  final String artistKey; // normalized key
  final String displayName;

  @override
  State<ArtistDetail> createState() => _ArtistDetailState();
}

class _ArtistDetailState extends State<ArtistDetail> {
  final _store = AlbumStore();
  List<Album> _albums = [];
  bool _loading = true;
  String? _artistDescription;
  String? _artistImageUrl;
  String? _artistLink;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _normalizeArtist(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _load() async {
    final all = await _store.getAllAlbums();
    final key = widget.artistKey;
    final filtered = all.where((a) => _normalizeArtist(a.artist) == key).toList();
    filtered.sort((a, b) {
      final ad = a.published ?? '';
      final bd = b.published ?? '';
      final cmpDate = bd.compareTo(ad); // descending
      if (cmpDate != 0) return cmpDate;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    setState(() {
      _albums = filtered;
      _loading = false;
    });

    // Kick off artist/channel metadata fetch once albums are available
    _loadArtistChannelMeta();
  }

  Future<void> _loadArtistChannelMeta() async {
    if (_albums.isEmpty) return;
    // Find first track URL to infer the site's base URL
    String? anyUrl;
    for (final a in _albums) {
      if (a.tracks.isNotEmpty) {
        anyUrl = a.tracks.first.url;
        break;
      }
    }
    if (anyUrl == null) return;
    final service = FeedMetadataService();
    final meta = await service.findArtistChannelFromUrl(anyUrl);
    if (!mounted) return;
    setState(() {
      _artistDescription = meta?.description;
      _artistImageUrl = meta?.imageUrl;
      _artistLink = meta?.link;
    });
  }

  Future<void> _openArtistLink() async {
    final link = _artistLink;
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName),
        actions: [
          if (_artistLink != null && _artistLink!.isNotEmpty)
            IconButton(
              tooltip: 'View on web',
              icon: const Icon(Icons.open_in_new),
              onPressed: _openArtistLink,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _albums.isEmpty
              ? const Center(child: Text('No albums for this artist'))
              : CustomScrollView(
                  slivers: [
                    // Header with artist image and description (if available)
                    SliverToBoxAdapter(
                      child: (_artistDescription == null && _artistImageUrl == null)
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_artistImageUrl != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        _artistImageUrl!,
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stack) => Container(
                                          width: 64,
                                          height: 64,
                                          color: theme.colorScheme.surfaceContainerHighest,
                                          child: Icon(
                                            Icons.person,
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.person,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _artistDescription ?? '',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final album = _albums[index];
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AlbumDetail(
                                      album: album,
                                      playback: PlaybackManager.instance,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    AspectRatio(
                                      aspectRatio: 1,
                                      child: album.coverUrl != null
                                          ? Image.network(
                                              album.coverUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stack) => Container(
                                                color: theme.colorScheme.surfaceContainerHighest,
                                                child: Center(
                                                  child: Icon(
                                                    Icons.album,
                                                    size: 48,
                                                    color: theme.colorScheme.onSurface,
                                                  ),
                                                ),
                                              ),
                                            )
                                          : Container(
                                              color: theme.colorScheme.surfaceContainerHighest,
                                              child: Center(
                                                child: Icon(
                                                  Icons.album,
                                                  size: 48,
                                                  color: theme.colorScheme.onSurface,
                                                ),
                                              ),
                                            ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                album.title,
                                                style: theme.textTheme.titleMedium,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Flexible(
                                              child: Text(
                                                album.artist,
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  color: theme.colorScheme.onSurface,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _albums.length,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
