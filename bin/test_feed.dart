import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:fairstream_app/services/feed_parser.dart';

/// Simple CLI helper to run the feed parser against a local feed file.
/// If the referenced file doesn't exist, prints a message and exits.
void main() async {
  final filePath = '/home/tom/Public/FairStreamApp/reference files/feed.rss';
  final f = File(filePath);
  if (!await f.exists()) {
    debugPrint('Local test feed not found at $filePath — skipping.');
    return;
  }

  final tempDir = await Directory.systemTemp.createTemp('fairstream_test');
  final tempFile = File(path.join(tempDir.path, 'test_feed.rss'));
  await tempFile.writeAsString(await f.readAsString());

  try {
    final uri = tempFile.uri.toString();
    final parser = FeedParser();
    final albums = await parser.parseFeed(uri);
    if (albums.isEmpty) {
      debugPrint('No albums parsed from $uri');
      return;
    }
    final album = albums.first;
    debugPrint('\nParsed Album:');
    debugPrint('Title: ${album.title}');
    debugPrint('Artist: ${album.artist}');
    debugPrint('Cover URL: ${album.coverUrl}');
    debugPrint('\nTracks (${album.tracks.length}):');
    for (final track in album.tracks) {
      debugPrint('- ${track.title}');
      debugPrint('  URL: ${track.url}');
    }
  } catch (e, stack) {
    debugPrint('Error testing feed parser: $e');
    debugPrint('Stack trace:\n$stack');
  } finally {
    await tempDir.delete(recursive: true);
  }
}