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
    final albums = await _store.getAllAlbums();
    final groups = <String, _ArtistGroup>{};

    for (final a in albums) {
      final key = _normalizeArtist(a.artist);
      if (key.isEmpty) continue;
      final group = groups.putIfAbsent(key, () => _ArtistGroup(displayName: a.artist, albums: []));
      group.albums.add(a);
      // Prefer a more "complete" display name if encountered later (longer non-empty)
      if (a.artist.trim().length > group.displayName.trim().length) {
        group.displayName = a.artist;
      }
    }

    // Sort artists alphabetically by display name
    for (final g in groups.values) {
      // Optional: sort albums with most recent (published) first, then title
      g.albums.sort((a, b) {
        final ad = a.published ?? '';
        final bd = b.published ?? '';
        final cmpDate = bd.compareTo(ad); // descending
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

  String _normalizeArtist(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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
