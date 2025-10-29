import 'http_client/http_client.dart';
import 'package:flutter/foundation.dart';

enum FeedType {
  rss,
  m3u,
  unknown
}

class FeedTypeDetector {
  static Future<FeedType> detectFeedType(String url) async {
    try {
      final client = createPlatformHttpClient();
      final contentType = 'text/plain';
      
      // For now, we'll rely on URL extension since we can't do HEAD requests
      // in the web platform without CORS issues

      if (contentType.contains('application/rss+xml') || 
          contentType.contains('application/xml') || 
          contentType.contains('text/xml') ||
          url.toLowerCase().endsWith('.rss') ||
          url.toLowerCase().endsWith('.xml')) {
        return FeedType.rss;
      }

      if (contentType.contains('audio/x-mpegurl') || 
          contentType.contains('application/vnd.apple.mpegurl') ||
          contentType.contains('application/x-mpegurl') ||
          url.toLowerCase().endsWith('.m3u') ||
          url.toLowerCase().endsWith('.m3u8')) {
        return FeedType.m3u;
      }

      // Try to peek at the content
      final content = (await client.fetchString(url)).trim().toLowerCase();
      
      if (content.startsWith('<?xml') || content.contains('<rss')) {
        return FeedType.rss;
      }
      
      if (content.startsWith('#extm3u') || content.contains('#extinf')) {
        return FeedType.m3u;
      }

      return FeedType.unknown;
    } catch (e) {
      debugPrint('Error detecting feed type: $e');
      return FeedType.unknown;
    }
  }
}