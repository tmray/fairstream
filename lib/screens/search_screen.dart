import 'dart:async';
import 'package:flutter/material.dart';
import '../services/album_store.dart';
import '../services/search_history.dart';
import '../models/album.dart';
import 'artist_detail.dart';
import 'album_detail.dart';
import '../services/playback_manager.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _store = AlbumStore();
  final _history = SearchHistory();
  final _controller = TextEditingController();
  Timer? _debounce;
  static const _debounceDuration = Duration(milliseconds: 300);

  bool _loading = false;
  String _query = '';
  Map<String, ArtistIndexEntry> _artistIndex = const {};
  List<Album> _albums = const [];
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _primeIndex();
  }

  Future<void> _primeIndex() async {
    setState(() => _loading = true);
    // Load cached artist index and all albums (for album matches and hydration)
    final idx = await _store.getArtistIndexCached();
    final albums = await _store.getAllAlbums();
    final recents = await _history.getRecent();
    if (!mounted) return;
    setState(() {
      _artistIndex = idx;
      _albums = albums;
      _recent = recents;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _buildResults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          IconButton(
            tooltip: 'Clear recent searches',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              await _history.clear();
              if (!mounted) return;
              setState(() => _recent = const []);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search artists and albums',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _debounce?.cancel();
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onSubmitted: (v) async {
                final q = v.trim();
                setState(() => _query = q);
                await _history.add(q);
                final rec = await _history.getRecent();
                if (!mounted) return;
                setState(() => _recent = rec);
              },
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(_debounceDuration, () {
                  if (!mounted) return;
                  setState(() => _query = v.trim());
                });
              },
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _query.isEmpty
                ? (_recent.isEmpty
                    ? const Center(child: Text('Type to search'))
                    : ListView.builder(
                        itemCount: _recent.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return ListTile(
                              dense: true,
                              title: Text('Recent searches', style: theme.textTheme.labelLarge),
                            );
                          }
                          final q = _recent[index - 1];
                          return ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () async {
                                await _history.remove(q);
                                final rec = await _history.getRecent();
                                if (!mounted) return;
                                setState(() => _recent = rec);
                              },
                            ),
                            onTap: () {
                              _controller.text = q;
                              setState(() => _query = q);
                            },
                          );
                        },
                      ))
                : results.isEmpty
                    ? const Center(child: Text('No matches'))
                    : ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = results[index];
                          if (item is _Header) {
                            return ListTile(
                              dense: true,
                              title: Text(item.title, style: theme.textTheme.labelLarge),
                            );
                          } else if (item is _ArtistItem) {
                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person)),
                              title: Text(item.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${item.albumCount} album${item.albumCount == 1 ? '' : 's'}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ArtistDetail(
                                    artistKey: item.key,
                                    displayName: item.displayName,
                                  ),
                                ),
                              ),
                            );
                          } else if (item is _AlbumItem) {
                            return ListTile(
                              leading: item.coverUrl != null
                                  ? CircleAvatar(backgroundImage: NetworkImage(item.coverUrl!))
                                  : const CircleAvatar(child: Icon(Icons.album)),
                              title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(item.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AlbumDetail(
                                    album: item.album,
                                    playback: PlaybackManager.instance,
                                  ),
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
          ),
        ],
      ),
    );
  }

  List<Object> _buildResults() {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];

    // Artists matches
    final artistKeys = _artistIndex.keys.where((k) {
      final e = _artistIndex[k]!;
      return k.contains(q) || e.displayName.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => _artistIndex[a]!.displayName.toLowerCase().compareTo(_artistIndex[b]!.displayName.toLowerCase()));

    final artistItems = <_ArtistItem>[];
    for (final k in artistKeys.take(25)) { // cap to 25 quick-jump items
      final e = _artistIndex[k]!;
      artistItems.add(_ArtistItem(key: k, displayName: e.displayName, albumCount: e.albumIds.length));
    }

    // Album matches
    final albumMatches = _albums.where((a) {
      return a.title.toLowerCase().contains(q) || a.artist.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        final ta = a.title.toLowerCase();
        final tb = b.title.toLowerCase();
        final cmp = ta.compareTo(tb);
        if (cmp != 0) return cmp;
        return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      });

    final albumItems = <_AlbumItem>[];
    for (final a in albumMatches.take(50)) { // cap results for smoothness
      albumItems.add(_AlbumItem(
        album: a,
        title: a.title,
        artist: a.artist,
        coverUrl: a.coverUrl,
      ));
    }

    final out = <Object>[];
    if (artistItems.isNotEmpty) {
      out.add(const _Header('Artists'));
      out.addAll(artistItems);
    }
    if (albumItems.isNotEmpty) {
      out.add(const _Header('Albums'));
      out.addAll(albumItems);
    }
    return out;
  }
}

class _Header {
  const _Header(this.title);
  final String title;
}

class _ArtistItem {
  const _ArtistItem({required this.key, required this.displayName, required this.albumCount});
  final String key;
  final String displayName;
  final int albumCount;
}

class _AlbumItem {
  const _AlbumItem({required this.album, required this.title, required this.artist, this.coverUrl});
  final Album album;
  final String title;
  final String artist;
  final String? coverUrl;
}
