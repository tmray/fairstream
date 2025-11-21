import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/feed_parser.dart';
import '../utils/dev_config.dart';
import '../services/subscription_manager.dart';
import '../models/feed_source.dart';
import '../services/album_store.dart';
import '../services/backup_service.dart';
import 'test_listening_time.dart';
import 'package:file_picker/file_picker.dart';

class FeedsScreen extends StatefulWidget {
  const FeedsScreen({super.key});

  @override
  State<FeedsScreen> createState() => _FeedsScreenState();
}

class _FeedsScreenState extends State<FeedsScreen> {
  final _parser = FeedParser();
  final _subs = SubscriptionManager();
  final _backupService = BackupService();
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

  Future<void> _exportBackup() async {
    try {
      final result = await _backupService.exportToFile();
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success ? result.message : 'Export failed: ${result.message}'),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export error: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) {
        return; // User canceled
      }

      final filePath = result.files.single.path!;
      final importResult = await _backupService.importFromFile(filePath);

      if (!mounted) return;

      if (importResult.success) {
        // Reload the feeds list after import
        await _load();
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${importResult.message}\nPlease restart the app to see all changes.'),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: ${importResult.message}'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import error: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
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
      body: Column(
        children: [
          // Backup/Restore section
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Library Backup',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Export your library to backup file or import from a previous backup.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exportBackup,
                          icon: const Icon(Icons.file_upload),
                          label: const Text('Export'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _importBackup,
                          icon: const Icon(Icons.file_download),
                          label: const Text('Import'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Feeds list
          Expanded(
            child: ListView.builder(
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
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
    );
  }
}
