import 'dart:async';
import 'package:flutter/material.dart';
import '../services/album_store.dart';
import '../models/album.dart';
import 'artist_detail.dart';

class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => ArtistsScreenState();
}

class ArtistsScreenState extends State<ArtistsScreen> with WidgetsBindingObserver {
  final _store = AlbumStore();
  final Map<String, _ArtistGroup> _groups = {};
  bool _loading = true;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  static const _debounceDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      reload();
    }
  }

  /// Called when this widget is reactivated (e.g., when navigating back to this tab)
  @override
  void activate() {
    super.activate();
    reload();
  }

  /// Public method to reload artists data
  Future<void> reload() async {
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
              await reload();
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(SnackBar(content: Text(updated > 0 ? 'Fixed $updated album${updated == 1 ? '' : 's'}' : 'No fixes needed')));
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search artists',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _debounce?.cancel();
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(_debounceDuration, () {
                        if (!mounted) return;
                        setState(() => _query = v.trim());
                      });
                    },
                  ),
                ),
                Expanded(
                  child: _groups.isEmpty
                      ? const Center(child: Text('No artists yet'))
                      : Builder(
                          builder: (context) {
                            final queryLower = _query.trim().toLowerCase();
                            final keys = _groups.keys.toList()
                              ..sort((a, b) => _groups[a]!.displayName
                                  .toLowerCase()
                                  .compareTo(_groups[b]!.displayName.toLowerCase()));
                            final filteredKeys = queryLower.isEmpty
                                ? keys
                                : keys.where((k) {
                                    final name = _groups[k]!.displayName.toLowerCase();
                                    return name.contains(queryLower) || k.contains(queryLower);
                                  }).toList();

                            if (filteredKeys.isEmpty) {
                              return const Center(child: Text('No matches'));
                            }

                            return ListView.separated(
                              itemCount: filteredKeys.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final key = filteredKeys[index];
                                final group = _groups[key]!;
                                final cover = group.albums.firstWhere(
                                  (a) => a.coverUrl != null,
                                  orElse: () => group.albums.first,
                                );
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
                            );
                          },
                        ),
                ),
              ],
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
