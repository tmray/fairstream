// import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:fairstream_app/services/feed_parser.dart';

void main() async {
  final testUrl = 'https://faircamp.lorenzosmusic.com/feed.rss';
  
  try {
      debugPrint('Testing feed parser with URL: $testUrl');
    final parser = FeedParser();
    final albums = await parser.parseFeed(testUrl);
    if (albums.isEmpty) {
        debugPrint('No albums parsed');
      return;
    }
    final album = albums.first;

      debugPrint('\nParsed Album Successfully:');
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
  }
}