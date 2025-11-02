import 'package:flutter/material.dart';
import '../services/album_store.dart';
import '../models/album.dart';
import '../services/playback_manager.dart';
import 'album_detail.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _store = AlbumStore();
  List<Album> _albums = [];

  @override
  void initState() { 
    super.initState(); 
    _load(); 
  }

  Future<void> _load() async { 
    _albums = await _store.getAllAlbums();
    setState(() {});
  }

  Future<void> _refreshMetadata() async {
    if (_albums.isEmpty) return;
    
    final updatedAlbums = List<Album>.from(_albums);
    bool hasUpdates = false;

    for (int i = 0; i < updatedAlbums.length; i++) {
      final album = updatedAlbums[i];
      // Always refresh metadata for all albums with tracks
      if (album.tracks.isNotEmpty) {
        await _store.refreshAlbumMetadata(album);
        updatedAlbums[i] = (await _store.getAlbumsForFeed(album.id))
            .firstWhere((a) => a.id == album.id, orElse: () => album);
        hasUpdates = true;
      }
    }

    if (hasUpdates) {
      setState(() {
        _albums = updatedAlbums;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Update album information',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(
                const SnackBar(content: Text('Updating album information...')),
              );
              await _refreshMetadata();
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                const SnackBar(content: Text('Album information updated')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.build),
            tooltip: 'Fix artists',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(
                const SnackBar(content: Text('Repairing artist metadata...')),
              );
              final updated = await _store.repairArtistMetadata();
              await _load();
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                SnackBar(content: Text(updated > 0 ? 'Fixed $updated album${updated == 1 ? '' : 's'}' : 'No fixes needed')),
              );
            },
          ),
        ],
      ),
      body: _albums.isEmpty 
        ? const Center(child: Text('No albums')) 
        : GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.75, // Adjusted for more vertical space
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
                              errorBuilder: (context, error, stack) => 
                                Container(
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
