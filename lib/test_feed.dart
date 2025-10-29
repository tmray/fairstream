import 'dart:io';
import 'package:flutter/foundation.dart';
import 'services/feed_parser.dart';

void main() async {
  // Read the reference feed file
  final feedContent = await File('/home/tom/Public/FairStreamApp/referece files/feed.rss').readAsString();
  
  // Create a test server to serve the feed content
  final server = await HttpServer.bind('localhost', 8080);
  server.listen((request) {
    request.response
      ..headers.contentType = ContentType('application', 'rss+xml', charset: 'utf-8')
      ..write(feedContent)
      ..close();
  });

  try {
    debugPrint('Testing feed parser...');
    final parser = FeedParser();
    final albums = await parser.parseFeed('http://localhost:8080');
    if (albums.isEmpty) {
      debugPrint('No albums parsed');
      return;
    }
    final album = albums.first;
    debugPrint('\nParsed Album:');
    debugPrint('Title: ${album.title}');
    debugPrint('Artist: ${album.artist}');
    debugPrint('Cover URL: ${album.coverUrl}');
    debugPrint('\nTracks:');
    for (final track in album.tracks) {
      debugPrint('- ${track.title}');
      debugPrint('  URL: ${track.url}');
    }
  } catch (e) {
    debugPrint('Error testing feed parser: $e');
  } finally {
    await server.close();
  }
}