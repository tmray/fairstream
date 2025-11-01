import 'package:flutter/material.dart';
import '../services/album_store.dart';
import '../models/album.dart';
import 'artist_detail.dart';

class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  final _store = AlbumStore();
  final Map<String, _ArtistGroup> _groups = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Use cached artist index for quick grouping
  final index = await _store.getArtistIndexCached();
    // Load all albums once to hydrate album objects for counts/covers
    final albums = await _store.getAllAlbums();
    final byId = {for (final a in albums) a.id: a};

    final groups = <String, _ArtistGroup>{};
    index.forEach((key, entry) {
      final grp = groups.putIfAbsent(key, () => _ArtistGroup(displayName: entry.displayName, albums: []));
      for (final id in entry.albumIds) {
        final album = byId[id];
        if (album != null) grp.albums.add(album);
      }
      // Ensure display name stays the most complete
      for (final a in grp.albums) {
        if (a.artist.trim().length > grp.displayName.trim().length) {
          grp.displayName = a.artist;
        }
      }
    });

    // Sort albums within artists
    for (final g in groups.values) {
      g.albums.sort((a, b) {
        final ad = a.published ?? '';
        final bd = b.published ?? '';
        final cmpDate = bd.compareTo(ad);
        if (cmpDate != 0) return cmpDate;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }

    setState(() {
      _groups
        ..clear()
        ..addAll(groups);
      _loading = false;
    });
  }

  // Cached index handles normalization; keep for potential future use
  // String _normalizeArtist(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\\s+'), ' ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artists'),
        actions: [
          IconButton(
            tooltip: 'Fix artists',
            icon: const Icon(Icons.build),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(const SnackBar(content: Text('Repairing artist metadata...')));
              final updated = await _store.repairArtistMetadata();
              await _load();
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(SnackBar(content: Text(updated > 0 ? 'Fixed $updated album${updated == 1 ? '' : 's'}' : 'No fixes needed')));
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(child: Text('No artists yet'))
              : ListView.separated(
                  itemCount: _groups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final keys = _groups.keys.toList()..sort((a, b) => _groups[a]!.displayName.toLowerCase().compareTo(_groups[b]!.displayName.toLowerCase()));
                    final key = keys[index];
                    final group = _groups[key]!;
                    final cover = group.albums.firstWhere((a) => a.coverUrl != null, orElse: () => group.albums.first);

                    return ListTile(
                      leading: _ArtistAvatar(coverUrl: cover.coverUrl, theme: theme),
                      title: Text(group.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${group.albums.length} album${group.albums.length == 1 ? '' : 's'}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ArtistDetail(
                            artistKey: key,
                            displayName: group.displayName,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _ArtistGroup {
  _ArtistGroup({required this.displayName, required this.albums});
  String displayName;
  final List<Album> albums;
}

class _ArtistAvatar extends StatelessWidget {
  const _ArtistAvatar({required this.coverUrl, required this.theme});
  final String? coverUrl;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      backgroundImage: coverUrl != null ? NetworkImage(coverUrl!) : null,
      child: coverUrl == null
          ? Icon(Icons.person, color: theme.colorScheme.onSurfaceVariant)
          : null,
    );
  }
}
