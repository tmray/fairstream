import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../services/subscription_manager.dart';
import '../services/album_store.dart';
import '../services/feed_parser.dart';
import '../models/feed_source.dart';

/// Service for exporting and importing app data (library, listening time, etc.)
class BackupService {
  static const _backupVersion = 1;
  
  /// Keys to include in backup (all app data)
  static const _backupKeys = [
    'albums_all',
    'listening_time_v1',
    'support_tab_last_viewed_v1',
    'albums_version_v1',
    'artists_index_v1',
    'albums_normalized_v2',
    'albums_artist_fix_v1',
    'albums_dupe_cleanup_v1',
    'albums_title_fix_v1',
    'search_history_v1',
  ];

  /// Export all app data to JSON
  Future<Map<String, dynamic>> exportData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    
    for (final key in _backupKeys) {
      final value = prefs.get(key);
      if (value != null) {
        data[key] = value;
      }
    }
    
    return {
      'version': _backupVersion,
      'timestamp': DateTime.now().toIso8601String(),
      'data': data,
    };
  }

  /// Import data from JSON backup
  Future<BackupImportResult> importData(Map<String, dynamic> backup) async {
    try {
      final version = backup['version'] as int?;
      if (version == null || version > _backupVersion) {
        return BackupImportResult(
          success: false,
          message: 'Incompatible backup version',
        );
      }

      final data = backup['data'] as Map<String, dynamic>?;
      if (data == null) {
        return BackupImportResult(
          success: false,
          message: 'Invalid backup format',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      int imported = 0;

      for (final entry in data.entries) {
        final key = entry.key;
        final value = entry.value;

        if (value is String) {
          await prefs.setString(key, value);
          imported++;
        } else if (value is int) {
          await prefs.setInt(key, value);
          imported++;
        } else if (value is bool) {
          await prefs.setBool(key, value);
          imported++;
        } else if (value is double) {
          await prefs.setDouble(key, value);
          imported++;
        } else if (value is List<String>) {
          await prefs.setStringList(key, value);
          imported++;
        }
      }

      return BackupImportResult(
        success: true,
        message: 'Imported $imported items',
        itemsImported: imported,
      );
    } catch (e) {
      return BackupImportResult(
        success: false,
        message: 'Import failed: $e',
      );
    }
  }

  /// Export to file in downloads directory
  Future<BackupFileResult> exportToFile() async {
    try {
      final data = await exportData();
      final json = jsonEncode(data);
      
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final filename = 'fairstream_backup_$timestamp.json';
      
      Directory directory;
      if (Platform.isAndroid) {
        // Use downloads directory on Android
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        }
      } else if (Platform.isIOS) {
        // Use documents directory on iOS
        directory = await getApplicationDocumentsDirectory();
      } else {
        // Desktop (Linux, macOS, Windows)
        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }
      
      final file = File('${directory.path}/$filename');
      await file.writeAsString(json);
      
      return BackupFileResult(
        success: true,
        filePath: file.path,
        message: 'Backup saved to ${file.path}',
      );
    } catch (e) {
      debugPrint('Export to file failed: $e');
      return BackupFileResult(
        success: false,
        message: 'Export failed: $e',
      );
    }
  }

  /// Export a lightweight catalog of subscriptions (M3U links + labels)
  Future<Map<String, dynamic>> exportCatalogData() async {
    final subs = await SubscriptionManager().load();
    return {
      'catalogVersion': 1,
      'generatedAt': DateTime.now().toIso8601String(),
      'feeds': subs.map((f) => {
            'url': f.url,
            'name': f.name,
            'imageUrl': f.imageUrl,
            'addedAt': f.addedAt.toIso8601String(),
          }).toList(),
    };
  }

  /// Export catalog to file in downloads directory
  Future<BackupFileResult> exportCatalogToFile() async {
    try {
      final data = await exportCatalogData();
      final json = jsonEncode(data);

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final filename = 'fairstream_catalog_$timestamp.json';

      Directory directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        }
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      final file = File('${directory.path}/$filename');
      await file.writeAsString(json);

      return BackupFileResult(
        success: true,
        filePath: file.path,
        message: 'Catalog saved to ${file.path}',
      );
    } catch (e) {
      debugPrint('Export catalog failed: $e');
      return BackupFileResult(
        success: false,
        message: 'Catalog export failed: $e',
      );
    }
  }

  /// Import catalog data: re-parse each feed URL and populate albums
  Future<BackupImportResult> importCatalogData(Map<String, dynamic> catalog) async {
    try {
      final feeds = catalog['feeds'] as List<dynamic>?;
      if (feeds == null) {
        return BackupImportResult(success: false, message: 'Invalid catalog format');
      }

      final parser = FeedParser();
      final store = AlbumStore();
      final subsMgr = SubscriptionManager();
      final existingSubs = await subsMgr.load();

      int addedAlbums = 0;
      int skippedAlbums = 0;
      int processedFeeds = 0;

      for (final f in feeds) {
        final m = Map<String, dynamic>.from(f as Map);
        final url = m['url'] as String?;
        final imageUrl = m['imageUrl'] as String?;
        if (url == null || url.isEmpty) continue;

        try {
          final albums = await parser.parseFeed(url);
          for (final album in albums) {
            final exists = await store.albumExistsCanonical(album);
            if (exists) {
              skippedAlbums++;
              continue;
            }

            final feedId = '${DateTime.now().millisecondsSinceEpoch}_${album.title}';
            final feed = FeedSource(
              id: feedId,
              url: url,
              name: album.title,
              imageUrl: album.coverUrl ?? imageUrl,
              addedAt: DateTime.now(),
            );

            existingSubs.add(feed);
            await store.saveAlbum(feedId, album);
            addedAlbums++;
          }
          processedFeeds++;
        } catch (e) {
          debugPrint('Error parsing feed $url: $e');
        }
      }

      await subsMgr.save(existingSubs);

      return BackupImportResult(
        success: true,
        message: 'Imported $addedAlbums album(s), $skippedAlbums duplicate(s) from $processedFeeds feed(s)',
        itemsImported: addedAlbums,
      );
    } catch (e) {
      return BackupImportResult(success: false, message: 'Catalog import failed: $e');
    }
  }

  /// Import from file, auto-detect backup vs catalog format
  Future<BackupImportResult> importAutoFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return BackupImportResult(success: false, message: 'File not found');
      }
      final jsonStr = await file.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (data.containsKey('version') && data.containsKey('data')) {
        return await importData(data);
      }
      if (data.containsKey('catalogVersion') && data.containsKey('feeds')) {
        return await importCatalogData(data);
      }
      // Heuristic: if it has 'feeds' only, treat as catalog
      if (data.containsKey('feeds')) {
        return await importCatalogData(data);
      }
      return BackupImportResult(success: false, message: 'Unrecognized file format');
    } catch (e) {
      return BackupImportResult(success: false, message: 'Failed to read file: $e');
    }
  }

  /// Import from file
  Future<BackupImportResult> importFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return BackupImportResult(
          success: false,
          message: 'File not found',
        );
      }

      final json = await file.readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      
      return await importData(data);
    } catch (e) {
      return BackupImportResult(
        success: false,
        message: 'Failed to read file: $e',
      );
    }
  }

  /// Get backup data as JSON string (for cloud sync)
  Future<String> getBackupJson() async {
    final data = await exportData();
    return jsonEncode(data);
  }

  /// Restore from JSON string (for cloud sync)
  Future<BackupImportResult> restoreFromJson(String json) async {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return await importData(data);
    } catch (e) {
      return BackupImportResult(
        success: false,
        message: 'Invalid JSON: $e',
      );
    }
  }
}

class BackupImportResult {
  final bool success;
  final String message;
  final int itemsImported;

  BackupImportResult({
    required this.success,
    required this.message,
    this.itemsImported = 0,
  });
}

class BackupFileResult {
  final bool success;
  final String message;
  final String? filePath;

  BackupFileResult({
    required this.success,
    required this.message,
    this.filePath,
  });
}
