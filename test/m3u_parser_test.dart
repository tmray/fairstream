import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fairstream_app/services/m3u_parser.dart';
import 'package:fairstream_app/services/http_client/platform_http_client.dart';

class FakeClient implements PlatformHttpClient {
  final String path;
  FakeClient(this.path);

  @override
  Future<String> fetchString(String url) async {
    final f = File(path);
    if (!await f.exists()) throw Exception('Test file not found: $path');
    final bytes = await f.readAsBytes();
    // simulate proper UTF-8 decode like the real client does
    return utf8.decode(bytes, allowMalformed: true);
  }
}

void main() {
  test('M3U parsing decodes UTF-8 and normalizes dashes', () async {
    final path = '/home/tom/Public/FairStreamApp/referece files/example-m3u-file.m3u';
    final client = FakeClient(path);
    final parser = M3UParser(client: client);

    final albums = await parser.parseM3U('http://example.test/playlist.m3u');
    expect(albums, isNotEmpty);
    final album = albums.first;
    expect(album.tracks, isNotEmpty);
    // Expect 7 tracks based on the example file
    expect(album.tracks.length, 7);

    // Check first track title does not contain mojibake and is cleaned properly
    final firstTitle = album.tracks.first.title;

    // No mojibake bytes/characters like 'â' should remain
    expect(firstTitle.contains('â'), isFalse, reason: 'Title should not contain mojibake "â"');

    // Should be just the song title without artist or track number
    // Expected: "With you" (not "Lorenzo's Music – 1. With you")
    expect(firstTitle, 'With you', reason: 'Title should be cleaned to just the song name');
  });
}
