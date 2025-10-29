import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'text_normalizer.dart';

class FeedMetadata {
  final String title;
  final String artist;
  final String? description;
  final String? imageUrl;
  final String? published;
  final String link;

  FeedMetadata({
    required this.title,
    this.artist = '',
    this.description,
    this.imageUrl,
    this.published,
    required this.link,
  });
}

// Use the shared normalizer functions from `text_normalizer.dart`.

class FeedMetadataService {
  /// Given a playlist URL like https://faircamp.lorenzosmusic.com/album-name/playlist.m3u
  /// tries to find and parse RSS/Atom feed at https://faircamp.lorenzosmusic.com/feed.rss
  /// or https://faircamp.lorenzosmusic.com/feed.atom
  Future<FeedMetadata?> findMetadataForAlbum(String playlistUrl) async {
    try {
      final uri = Uri.parse(playlistUrl);
      // The album path is usually the first segment after the domain
      final albumPath = uri.pathSegments.firstWhere(
        (segment) => segment != 'playlist.m3u' && segment.isNotEmpty,
        orElse: () => '',
      );
      if (albumPath.isEmpty) return null;

  // Metadata lookup for albumPath

      // Extract base URL (everything before the album path)
      final baseUri = uri.replace(path: '');
      
      // Try RSS feed first
      final rssUri = baseUri.replace(path: '/feed.rss');
      try {
        final response = await http.get(rssUri);
        if (response.statusCode == 200) {
          // Successfully fetched RSS feed
          
          return _parseRssFeed(response.body, albumPath);
        }
      } catch (_) {}

      // Try Atom feed next
      final atomUri = baseUri.replace(path: '/feed.atom');
      try {
        final response = await http.get(atomUri);
        if (response.statusCode == 200) {
          return _parseAtomFeed(response.body, uri.pathSegments[0]);
        }
      } catch (_) {}
    } catch (_) {}
    return null;
  }

  FeedMetadata? _parseRssFeed(String xml, String albumPath) {
    try {
      final document = XmlDocument.parse(xml);
      // Find the item with link containing our album path
      final items = document.findAllElements('item');
      final matchingItem = items.firstWhere(
        (item) {
          final link = item.findElements('link').firstOrNull?.innerText ?? '';
          return link.contains(albumPath);
        },
        orElse: () => throw Exception('No matching item found'),
      );

      // Clean and parse the title first as it might contain artist information
  final title = cleanTrackTitle(matchingItem.findElements('title').firstOrNull?.innerText ?? '');

      // Try to extract artist from various possible fields
      String artist = '';
      final authorElement = matchingItem.findElements('author').firstOrNull;
      if (authorElement != null) {
        artist = cleanHtmlContent(authorElement.innerText);
      } else {
        // Try dc:creator if author isn't found
        artist = cleanHtmlContent(matchingItem.findElements('dc:creator').firstOrNull?.innerText);
      }

      // If no explicit artist field, try to parse it from the cleaned title
      if (artist.isEmpty && title.contains(' - ')) {
        final parts = title.split(' - ');
        if (parts.length >= 2) {
          artist = parts[0].trim();
        }
      }

      final rawTitle = matchingItem.findElements('title').firstOrNull?.innerText ?? '';
      final cleanedTitle = cleanHtmlContent(rawTitle);

      return FeedMetadata(
        title: cleanedTitle,
        artist: cleanHtmlContent(artist),
        description: cleanHtmlContent(matchingItem.findElements('description').firstOrNull?.innerText),
        imageUrl: matchingItem.findElements('image').firstOrNull?.innerText ??
            matchingItem.findElements('coverImage').firstOrNull?.innerText,
        published: cleanHtmlContent(matchingItem.findElements('pubDate').firstOrNull?.innerText),
        link: matchingItem.findElements('link').firstOrNull?.innerText ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  FeedMetadata? _parseAtomFeed(String xml, String albumPath) {
    try {
      final document = XmlDocument.parse(xml);
      // Find the entry with link containing our album path
      final entries = document.findAllElements('entry');
      final matchingEntry = entries.firstWhere(
        (entry) {
          final links = entry.findElements('link');
          return links.any((link) => 
            (link.getAttribute('href') ?? '').contains(albumPath));
        },
        orElse: () => throw Exception('No matching entry found'),
      );

      // Try to extract artist information
      String artist = '';
      final authorElement = matchingEntry.findElements('author').firstOrNull;
      if (authorElement != null) {
        final name = authorElement.findElements('name').firstOrNull;
        if (name != null) {
          artist = cleanHtmlContent(name.innerText);
        }
      }

      // Try parsing from title if no author found
  final title = cleanHtmlContent(matchingEntry.findElements('title').firstOrNull?.innerText);
      if (artist.isEmpty && title.contains(' - ')) {
        final parts = title.split(' - ');
        if (parts.length >= 2) {
          artist = parts[0].trim();
        }
      }

      String? getLink() {
        final links = matchingEntry.findElements('link');
        final alternate = links.firstWhere(
          (link) => link.getAttribute('rel') == 'alternate',
          orElse: () => links.first,
        );
        return alternate.getAttribute('href');
      }

      return FeedMetadata(
        title: title,
        artist: artist,
        description: cleanHtmlContent(
          matchingEntry.findElements('summary').firstOrNull?.innerText ?? 
          matchingEntry.findElements('content').firstOrNull?.innerText
        ),
        imageUrl: matchingEntry.findElements('image').firstOrNull?.innerText ??
                 matchingEntry.findElements('coverImage').firstOrNull?.innerText,
        published: matchingEntry.findElements('published').firstOrNull?.innerText,
        link: getLink() ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}