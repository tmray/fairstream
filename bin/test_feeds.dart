import 'package:fairstream_app/services/feed_type_detector.dart';
import 'package:fairstream_app/services/feed_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:fairstream_app/models/album.dart';

void main() async {
  // Test URLs
  final rssUrl = 'https://faircamp.lorenzosmusic.com/feed.rss';
  final m3uUrl = 'https://faircamp.meljoann.com/playlist.m3u';

  try {
    // Test RSS feed
    final rssFeedType = await FeedTypeDetector.detectFeedType(rssUrl);
    debugPrint('\nTesting RSS feed: $rssUrl');
    debugPrint('Detecting feed type...');
    debugPrint('Detected feed type: $rssFeedType');

    if (rssFeedType == FeedType.rss) {
      debugPrint('Testing RSS parsing...');
      final parser = FeedParser();
      final rssAlbums = await parser.parseFeed(rssUrl);
      _printAlbums(rssAlbums);
    }

    // Test M3U feed
    final m3uFeedType = await FeedTypeDetector.detectFeedType(m3uUrl);
    debugPrint('\nTesting M3U feed: $m3uUrl');
    debugPrint('Detecting feed type...');
    debugPrint('Detected feed type: $m3uFeedType');

    if (m3uFeedType == FeedType.m3u) {
      debugPrint('Testing M3U parsing...');
      final parser = FeedParser();
      final m3uAlbums = await parser.parseFeed(m3uUrl);
      _printAlbums(m3uAlbums);
    }

  } catch (e, stack) {
    debugPrint('Error during testing: $e');
    debugPrint('Stack trace:\n$stack');
  }
}

void _printAlbums(List<Album> albums) {
  debugPrint('\nParsed ${albums.length} albums:');
  for (final album in albums) {
    debugPrint('\nAlbum: ${album.title}');
    debugPrint('Artist: ${album.artist}');
    debugPrint('Cover URL: ${album.coverUrl}');
    debugPrint('Tracks (${album.tracks.length}):');
    for (final track in album.tracks) {
      debugPrint('- ${track.title}');
      debugPrint('  Duration: ${track.durationSeconds}s');
      debugPrint('  URL: ${track.url}');
    }
    debugPrint('-' * 80);
  }
}