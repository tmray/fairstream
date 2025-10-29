import 'package:http/http.dart' as http;
import 'platform_http_client.dart';

/// Implementation for non-web platforms using standard HTTP client
class DefaultHttpClient implements PlatformHttpClient {
  final http.Client _client = http.Client();

  @override
  Future<String> fetchString(String url) async {
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.body;
    }
    throw Exception('Failed to fetch $url: ${response.statusCode}');
  }
}