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
      var currentCoverUrl = '';
      
      String? currentTitle;
      int? currentDuration;

      for (var i = 1; i < lines.length; i++) {
        final line = lines[i];
        
        if (line.startsWith('#PLAYLIST:')) {
          playlistTitle = line.substring('#PLAYLIST:'.length).trim();
        } else if (line.startsWith('#EXTIMG:')) {
          currentCoverUrl = line.substring('#EXTIMG:'.length).trim();
        } else if (line.startsWith('#EXTALB:')) {
          // Save current album if we have tracks
          if (currentTracks.isNotEmpty) {
            albums.add(Album(
              id: '$m3uUrl#$currentAlbumTitle',
              title: currentAlbumTitle,
              artist: playlistTitle ?? 'Unknown Artist',
              coverUrl: currentCoverUrl,
              tracks: List.from(currentTracks),
            ));
            currentTracks.clear();
          }
          currentAlbumTitle = line.substring('#EXTALB:'.length).trim();
        } else if (line.startsWith('#EXTINF:')) {
          // Parse duration and title
          // Format: #EXTINF:123, Artist - Title
          final parts = line.substring('#EXTINF:'.length).split(',');
          if (parts.isNotEmpty) {
            currentDuration = _parseDuration(parts[0].trim());
            if (parts.length > 1) {
              currentTitle = parts[1].trim();
            }
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
        albums.add(Album(
          id: '$m3uUrl#$currentAlbumTitle',
          title: currentAlbumTitle,
          artist: playlistTitle ?? 'Unknown Artist',
          coverUrl: currentCoverUrl,
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