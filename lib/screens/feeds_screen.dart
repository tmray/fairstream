import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/feed_parser.dart';
import '../utils/dev_config.dart';
import '../services/subscription_manager.dart';
import '../models/feed_source.dart';
import '../services/album_store.dart';
import 'test_listening_time.dart';

class FeedsScreen extends StatefulWidget {
  const FeedsScreen({super.key});

  @override
  State<FeedsScreen> createState() => _FeedsScreenState();
}

class _FeedsScreenState extends State<FeedsScreen> {
  final _parser = FeedParser();
  final _subs = SubscriptionManager();
  List<FeedSource> _feeds = [];
  bool _useDevProxy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadDevToggle();
  }

  Future<void> _loadDevToggle() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool('useDevCorsProxy') ?? false;
    setState(() {
      _useDevProxy = v;
      DevConfig.useDevCorsProxy = v;
    });
  }

  Future<void> _setDevToggle(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useDevCorsProxy', v);
    setState(() {
      _useDevProxy = v;
      DevConfig.useDevCorsProxy = v;
    });
  }

  Future<void> _load() async {
    final list = await _subs.load();
    setState(() => _feeds = list);
  }

  Future<void> _add() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text('Add M3U Playlist URL'),
        content: TextField(
          controller: ctrl, 
          decoration: const InputDecoration(hintText: 'https://...playlist.m3u')
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c,false), 
            child: const Text('Cancel')
          ), 
          TextButton(
            onPressed: () => Navigator.pop(c,true), 
            child: const Text('Add')
          )
        ],
      )
    );

    if (ok != true) return;
    final url = ctrl.text.trim();
    
    try {
      final albums = await _parser.parseFeed(url);
      final store = AlbumStore();
      
      int addedCount = 0;
      int skippedCount = 0;
      
      for (final album in albums) {
        // Check if album already exists before creating feed (canonical check)
        final exists = await store.albumExistsCanonical(album);
        if (exists) {
          skippedCount++;
          continue;
        }
        
  final feedId = '${DateTime.now().millisecondsSinceEpoch}_${album.title}';
        final feed = FeedSource(
          id: feedId,
          url: url,
          name: album.title,
          imageUrl: album.coverUrl,
          addedAt: DateTime.now()
        );
        
        _feeds.add(feed);
        await store.saveAlbum(feedId, album);
        addedCount++;
      }
      
      await _subs.save(_feeds);
      if (!mounted) return;
      setState(() {});
      
      // Show feedback about what was added/skipped
      if (!mounted) return;
      final message = addedCount > 0 
        ? 'Added $addedCount album${addedCount > 1 ? 's' : ''}${skippedCount > 0 ? ' ($skippedCount duplicate${skippedCount > 1 ? 's' : ''} skipped)' : ''}'
        : 'All albums already exist';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error parsing feed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import'),
        actions: [
          IconButton(
            icon: const Icon(Icons.science),
            tooltip: 'Test Listening Time',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TestListeningTime()),
              );
            },
          ),
          Row(children: [
            const Text('Dev proxy'),
            Switch(
              value: _useDevProxy, 
              onChanged: (v) => _setDevToggle(v)
            ),
          ])
        ],
      ),
      body: ListView.builder(
        itemCount: _feeds.length, 
        itemBuilder: (context, index) {
          final feed = _feeds[index];
          return ListTile(
            leading: feed.imageUrl != null 
              ? Image.network(
                  feed.imageUrl!,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.music_note),
                )
              : const Icon(Icons.music_note),
            title: Text(feed.name),
            subtitle: Text(feed.url),
          );
        }
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
    );
  }
}
