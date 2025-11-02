import '../models/album.dart';
import '../models/track.dart';
import '../utils/dev_config.dart';
import 'http_client/http_client.dart';
import 'text_normalizer.dart';
import 'package:flutter/foundation.dart';

class M3UParser {
  final PlatformHttpClient _client;

  /// Allow injecting a [PlatformHttpClient] for testing; default uses the
  /// platform implementation.
  M3UParser({PlatformHttpClient? client}) : _client = client ?? createPlatformHttpClient();

  /// Normalizes special characters and cleans up artist prefix
  String _cleanTitle(String title, String artistName) {
    // Use shared normalizer to handle unicode dashes and mojibake
    var cleaned = cleanTrackTitle(title);
    
    // Remove everything up to and including "number. " pattern
    // E.g. "Lorenzo's Music – 1. With you" -> "With you"
    cleaned = cleaned.replaceFirst(RegExp(r'^.+?\d+\.\s*'), '');

    return cleaned;
  }

  /// Parses a duration string that might be in various formats
  int _parseDuration(String durationStr) {
    try {
      // If it's just a number, treat as seconds
      return int.parse(durationStr);
    } catch (e) {
      try {
        // Try MM:SS format
        final parts = durationStr.split(':');
        if (parts.length == 2) {
          return int.parse(parts[0]) * 60 + int.parse(parts[1]);
        }
      } catch (_) {}
      return 0; // Default if parsing fails
    }
  }

  Future<List<Album>> parseM3U(String m3uUrl) async {
    try {
      var urlToFetch = m3uUrl;
      if (DevConfig.useDevCorsProxy) {
        urlToFetch = '${DevConfig.devProxyBase}${Uri.encodeComponent(m3uUrl)}';
      }

  debugPrint('Fetching M3U from $urlToFetch...');
      var content = await _client.fetchString(urlToFetch);
      // Normalize common dash variants and mojibake at the content level so
      // parsing never sees U+2013/U+2014 or â/Â artifacts.
      content = content
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('â', '-')
        .replaceAll('Â', '-')
        .replaceAll('€“', '-')
        .replaceAll('€', '');
      final lines = content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty || !lines[0].startsWith('#EXTM3U')) {
        throw Exception('Invalid M3U file: Missing #EXTM3U header');
      }

  String? playlistTitle;
  final albums = <Album>[];
  var currentTracks = <Track>[];
  var currentAlbumTitle = 'Unknown Album';
  // lastSeenCoverUrl updates whenever we see an #EXTIMG line (may be a global banner or album cover)
  // currentAlbumCover is the snapshot of the cover that applies to the current album (captured on #EXTALB)
  String lastSeenCoverUrl = '';
  String currentAlbumCover = '';
  String? canonicalFromTracks(List<Track> tracks) {
        if (tracks.isEmpty) return null;
        try {
          final u = Uri.parse(tracks.first.url);
          if (u.host.isEmpty || u.pathSegments.isEmpty) return null;
          final slug = u.pathSegments.first;
          if (slug.isEmpty || slug == 'playlist.m3u') return null;
          return '${u.scheme}://${u.host}/$slug';
        } catch (_) {
          return null;
        }
      }

  String fallbackCanonicalFromM3u(String url) {
        try {
          final u = Uri.parse(url);
          if (u.host.isEmpty) return url;
          if (u.pathSegments.length >= 2) {
            // e.g., /album-slug/playlist.m3u
            final slug = u.pathSegments.first;
            if (slug.isNotEmpty && slug != 'playlist.m3u') {
              return '${u.scheme}://${u.host}/$slug';
            }
          }
        } catch (_) {}
        return url;
      }
      
      bool looksLikeBanner(String? url) => (url ?? '').contains('image_fixed_');
      bool coverMatchesSlug(String? cover, String slug) {
        if (cover == null || cover.isEmpty) return false;
        return cover.contains('/$slug/');
      }
      String derivedCoverFromCanonical(String canonical) {
        try {
          final u = Uri.parse(canonical);
          final slug = u.pathSegments.isNotEmpty ? u.pathSegments.first : '';
          if (u.host.isEmpty || slug.isEmpty) return canonical;
          return Uri(scheme: u.scheme, host: u.host, pathSegments: [slug, 'cover_480.jpg']).toString();
        } catch (_) {
          return canonical;
        }
      }
      
      String? currentTitle;
      int? currentDuration;

      for (var i = 1; i < lines.length; i++) {
        final line = lines[i];
        
        if (line.startsWith('#PLAYLIST:')) {
          playlistTitle = line.substring('#PLAYLIST:'.length).trim();
        } else if (line.startsWith('#EXTIMG:')) {
          lastSeenCoverUrl = line.substring('#EXTIMG:'.length).trim();
        } else if (line.startsWith('#EXTALB:')) {
          // Save current album if we have tracks
          if (currentTracks.isNotEmpty) {
            final canonical = canonicalFromTracks(currentTracks) ?? fallbackCanonicalFromM3u(m3uUrl);
            // Validate/sanitize cover: avoid global banner and mismatched slug
            var cover = currentAlbumCover;
            try {
              final u = Uri.parse(canonical);
              final slug = u.pathSegments.isNotEmpty ? u.pathSegments.first : '';
              if (looksLikeBanner(cover) || !coverMatchesSlug(cover, slug)) {
                cover = derivedCoverFromCanonical(canonical);
              }
            } catch (_) {}
            albums.add(Album(
              id: canonical,
              title: currentAlbumTitle,
              artist: playlistTitle ?? 'Unknown Artist',
              coverUrl: cover,
              tracks: List.from(currentTracks),
            ));
            currentTracks.clear();
          }
          currentAlbumTitle = line.substring('#EXTALB:'.length).trim();
          // Snapshot the cover that applies to this album based on the most recent #EXTIMG before this #EXTALB
          currentAlbumCover = lastSeenCoverUrl;
        } else if (line.startsWith('#EXTINF:')) {
          // Parse duration and title
          // Correct behavior: title is EVERYTHING after the first comma
          // Example:
          //   #EXTINF:146, Spiral Island, Lorenzo's Music – 1. So long ...
          //   duration = 146, title = "Spiral Island, Lorenzo's Music – 1. So long ..."
          final rest = line.substring('#EXTINF:'.length);
          final commaIdx = rest.indexOf(',');
          if (commaIdx >= 0) {
            final durStr = rest.substring(0, commaIdx).trim();
            final titleStr = rest.substring(commaIdx + 1).trim();
            currentDuration = _parseDuration(durStr);
            currentTitle = titleStr;
          } else {
            // Fallback: no comma found, treat entire rest as title
            currentDuration = 0;
            currentTitle = rest.trim();
          }
        } else if (!line.startsWith('#')) {
          // This is a URL line
          if (currentTitle != null) {
            // Clean up the title
            final cleanTitle = _cleanTitle(currentTitle, playlistTitle ?? '');
            
            currentTracks.add(Track(
              id: line, // Using URL as ID for now
              title: cleanTitle,
              url: line,
              durationSeconds: currentDuration ?? 0,
            ));
            
            currentTitle = null;
            currentDuration = null;
          }
        }
      }

      // Add the final album if we have tracks
      if (currentTracks.isNotEmpty) {
        final canonical = canonicalFromTracks(currentTracks) ?? fallbackCanonicalFromM3u(m3uUrl);
        var cover = currentAlbumCover;
        try {
          final u = Uri.parse(canonical);
          final slug = u.pathSegments.isNotEmpty ? u.pathSegments.first : '';
          if (looksLikeBanner(cover) || !coverMatchesSlug(cover, slug)) {
            cover = derivedCoverFromCanonical(canonical);
          }
        } catch (_) {}
        albums.add(Album(
          id: canonical,
          title: currentAlbumTitle,
          artist: playlistTitle ?? 'Unknown Artist',
          coverUrl: cover,
          tracks: currentTracks,
        ));
      }

      if (albums.isEmpty) {
        throw Exception('No tracks found in M3U file');
      }

      return albums;

    } catch (e) {
      throw Exception('Error parsing M3U: ${e.toString()}');
    }
  }
}