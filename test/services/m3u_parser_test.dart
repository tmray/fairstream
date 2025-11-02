import 'package:flutter_test/flutter_test.dart';
import 'package:fairstream_app/services/m3u_parser.dart';
import 'package:fairstream_app/services/http_client/platform_http_client.dart';

class _FakeHttpClient implements PlatformHttpClient {
  final Map<String, String> responses;
  _FakeHttpClient(this.responses);

  @override
  Future<String> fetchString(String url) async {
    if (!responses.containsKey(url)) {
      throw Exception('No fake response for URL: $url');
    }
    return responses[url]!;
  }
}

void main() {
  test('root-level playlist uses correct per-album cover and ignores banner', () async {
    const url = 'https://example.com/playlist.m3u';
    const content = '#EXTM3U\n'
        '#PLAYLIST: Lorenzo\'s Music\n'
        '#EXTIMG:https://example.com/image_fixed_item_big.jpg\n'
        '#EXTIMG:https://example.com/lorenzos-remixes-volume-1/cover_480.jpg\n'
        "#EXTALB:Lorenzo's Remixes Volume 1\n"
        '#EXTINF:215, Lorenzo\'s Music - Track 01\n'
        'https://example.com/lorenzos-remixes-volume-1/01.mp3\n'
        '#EXTINF:210, Lorenzo\'s Music - Track 02\n'
        'https://example.com/lorenzos-remixes-volume-1/02.mp3\n'
        '#EXTIMG:https://example.com/lorenzos-remixes-volume-2/cover_480.jpg\n'
        "#EXTALB:Lorenzo's Remixes Volume 2\n"
        '#EXTINF:205, Lorenzo\'s Music - Track A\n'
        'https://example.com/lorenzos-remixes-volume-2/01.mp3\n';

    final parser = M3UParser(client: _FakeHttpClient({url: content}));
    final albums = await parser.parseM3U(url);

    expect(albums.length, 2);
    final a1 = albums[0];
    final a2 = albums[1];

    expect(a1.id, 'https://example.com/lorenzos-remixes-volume-1');
    expect(a2.id, 'https://example.com/lorenzos-remixes-volume-2');

    expect(a1.coverUrl, isNotNull);
    expect(a2.coverUrl, isNotNull);

    expect(a1.coverUrl!, contains('/lorenzos-remixes-volume-1/'));
    expect(a2.coverUrl!, contains('/lorenzos-remixes-volume-2/'));

    // Ensure first album did not pick up Volume 2 cover
    expect(a1.coverUrl!, isNot(contains('/lorenzos-remixes-volume-2/')));
  });

  test('parses #EXTINF with extra comma in pre-title correctly', () async {
    const url = 'https://example.com/root.m3u';
    const content = '#EXTM3U\n'
        '#PLAYLIST: Lorenzo\'s Music\n'
        '#EXTIMG:https://example.com/lorenzos-remixes-vol-1/cover_480.jpg\n'
        "#EXTALB:Lorenzo's Remixes, Volume 1\n"
        // Note extra comma before the artist/title dash
        '#EXTINF:146, Spiral Island, Lorenzo\'s Music – 1. So long (Spiral Island remix) by Spiral Island\n'
        'https://example.com/lorenzos-remixes-vol-1/01.opus\n';

    final parser = M3UParser(client: _FakeHttpClient({url: content}));
    final albums = await parser.parseM3U(url);

    expect(albums.length, 1);
    expect(albums.first.tracks.length, 1);
    expect(albums.first.id, 'https://example.com/lorenzos-remixes-vol-1');

    // Title should be cleaned to remove the index prefix "1. " and keep the rest
    expect(
      albums.first.tracks.first.title,
      'So long (Spiral Island remix) by Spiral Island',
    );
  });
}
