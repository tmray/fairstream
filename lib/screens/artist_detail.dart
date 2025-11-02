import 'package:flutter/material.dart';
import '../services/album_store.dart';
import '../models/album.dart';
import '../services/playback_manager.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _albums.isEmpty
              ? const Center(child: Text('No albums for this artist'))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _albums.length,
                  itemBuilder: (context, index) {
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
                ),
    );
  }
}
