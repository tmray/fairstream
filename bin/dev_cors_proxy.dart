import 'dart:io';

Future<void> main() async {
  final port = 8081;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  // print('CORS proxy listening on http://localhost:$port');

  await for (final req in server) {
    try {
      final uri = req.uri;
      if (uri.path != '/fetch') {
        req.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found - use /fetch?url=https://example.com/feed.rss')
          ..close();
        continue;
      }

      final target = uri.queryParameters['url'];
      if (target == null || target.isEmpty) {
        req.response
          ..statusCode = HttpStatus.badRequest
          ..write('Missing url query parameter')
          ..close();
        continue;
      }

  // print('Proxying: $target');

      final client = HttpClient();
      final fReq = await client.getUrl(Uri.parse(target));
      final fRes = await fReq.close();

      // Copy status and headers
      req.response.statusCode = fRes.statusCode;
      fRes.headers.forEach((name, values) {
        for (final v in values) {
          if (name.toLowerCase() == 'transfer-encoding') continue;
          req.response.headers.add(name, v);
        }
      });

      // Add CORS header for browser-based development
      req.response.headers.set('Access-Control-Allow-Origin', '*');
      req.response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
      req.response.headers.set('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept');

      // Stream body
      await fRes.pipe(req.response);
  } catch (e) {
  // print('Proxy error: $e\n$st');
      try {
        req.response
          ..statusCode = 500
          ..write('Proxy error: $e')
          ..close();
      } catch (_) {}
    }
  }
}