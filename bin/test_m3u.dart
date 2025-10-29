import 'package:fairstream_app/services/m3u_parser.dart';
import 'package:flutter/foundation.dart';

void main() async {
  final testUrl = 'https://faircamp.meljoann.com/playlist.m3u';
  
  try {
  debugPrint('Testing M3U parser with URL: $testUrl');
    final parser = M3UParser();
    final albums = await parser.parseM3U(testUrl);
    
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
  } catch (e, stack) {
  debugPrint('Error testing M3U parser: $e');
  debugPrint('Stack trace:\n$stack');
  }
}