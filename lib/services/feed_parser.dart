import 'package:xml/xml.dart';
import 'package:flutter/foundation.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../utils/dev_config.dart';
import 'feed_type_detector.dart';
import 'm3u_parser.dart';
import 'http_client/http_client.dart';
import 'text_normalizer.dart';

class FeedParser {
  final PlatformHttpClient _client = createPlatformHttpClient();
  final M3UParser _m3uParser = M3UParser();

  Future<List<Album>> parseFeed(String feedUrl) async {
    try {
      var urlToFetch = feedUrl;
      if (DevConfig.useDevCorsProxy) {
        urlToFetch = '${DevConfig.devProxyBase}${Uri.encodeComponent(feedUrl)}';
      }

  final feedType = await FeedTypeDetector.detectFeedType(urlToFetch);
      switch (feedType) {
        case FeedType.rss:
          final album = await _parseRssFeed(urlToFetch);
          return [album];
        case FeedType.m3u:
          return await _m3uParser.parseM3U(urlToFetch);
        case FeedType.unknown:
          throw Exception('Unknown or unsupported feed type');
      }
    } catch (e) {
      debugPrint('Error parsing feed: $e');
      rethrow;
    }
  }

  Future<Album> _parseRssFeed(String feedUrl) async {
    try {
      final response = await _client.fetchString(feedUrl);
      final doc = XmlDocument.parse(response);
      final channels = doc.findAllElements('channel').toList();
      
      if (channels.isEmpty) {
        throw Exception('Invalid RSS feed: No channel element found');
      }

      final channel = channels.first;
      
      final generator = channel.findElements('generator').firstOrNull?.innerText ?? '';
      if (!generator.toLowerCase().contains('faircamp')) {
        throw Exception('Not a valid Faircamp feed: Missing Faircamp generator tag');
      }
  final fullTitleRaw = channel.findElements('title').firstOrNull?.innerText ?? 'Unknown';
  // Clean and normalize dashes/mojibake before splitting into artist/album
  final fullTitle = cleanTrackTitle(fullTitleRaw);
  // After cleaning, dashes are normalized to ASCII '-' without surrounding spaces.
  final titleParts = fullTitle.split('-');
  final artist = titleParts.isNotEmpty ? titleParts[0].trim() : 'Unknown';
  final albumTitle = titleParts.length > 1 ? titleParts.sublist(1).join('-').trim() : fullTitle;
      final imageElement = channel.findElements('image').firstOrNull;
      final coverUrl = imageElement?.findElements('url').firstOrNull?.innerText;
      final items = channel.findElements('item').toList();
      
      // Use shared normalizer helper

      final tracks = <Track>[];
      for (var i = 0; i < items.length; i++) {
    final item = items[i];
    // Clean item title to normalize dashes/mojibake and entities
    final rawItemTitle = item.findElements('title').firstOrNull?.innerText ?? 'Unknown Track';
    final cleanedItemTitle = cleanTrackTitle(rawItemTitle);
    // Strip the artist prefix safely using the shared helper.
    var trackTitle = stripArtistPrefix(cleanedItemTitle, artist);
    // Remove numbered prefix pattern (e.g. "1. ", "(1) ")
    trackTitle = trackTitle.replaceFirst(RegExp(r'^(\d+\.\s*|\(\d+\)\s*)'), '');
        
        final guid = item.findElements('guid').firstOrNull?.innerText ?? i.toString();
        final link = item.findElements('link').firstOrNull?.innerText ?? '';
        
  // trackTitle and link are collected for later use
        
        tracks.add(Track(
          id: guid,
          title: trackTitle,
          url: link,
          durationSeconds: 0  // Duration not available in Faircamp feed
        ));
      }

      if (tracks.isEmpty) {
        throw Exception('No tracks found in feed');
      }

      return Album(
        id: fullTitle,
        title: albumTitle,
        artist: artist,
        coverUrl: coverUrl,
        tracks: tracks
      );
    } catch (e) {
      throw Exception('Error parsing RSS feed: ${e.toString()}');
    }
  }
}