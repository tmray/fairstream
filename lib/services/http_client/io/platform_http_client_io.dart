import 'dart:convert';
import 'package:http/http.dart' as http;
import '../platform_http_client.dart';

/// Implementation for non-web platforms using standard HTTP client
class DefaultHttpClient implements PlatformHttpClient {
  final http.Client _client = http.Client();

  @override
  Future<String> fetchString(String url) async {
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode == 200) {
      // Decode bytes as UTF-8 to respect #EXTENC:UTF-8 playlists and
      // avoid mojibake where multibyte sequences appear as separate
      // Latin-1 codepoints (e.g. 0xE2 0x80 0x93 -> U+2013 en-dash).
      try {
        return utf8.decode(response.bodyBytes, allowMalformed: true);
      } catch (_) {
        // Fallback to latin1 if UTF-8 decode somehow fails
        return latin1.decode(response.bodyBytes);
      }
    }
    throw Exception('Failed to fetch $url: ${response.statusCode}');
  }
}

PlatformHttpClient createHttpClient() => DefaultHttpClient();