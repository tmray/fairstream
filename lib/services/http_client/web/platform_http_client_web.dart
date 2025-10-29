import 'dart:async';
import 'dart:html' as html;
import '../platform_http_client.dart';

/// Web-specific implementation of PlatformHttpClient that bypasses CORS
class WebHttpClient implements PlatformHttpClient {
  @override
  Future<String> fetchString(String url) async {
    try {
      final request = html.HttpRequest();
      final completer = Completer<String>();
      
      request.open('GET', url, async: true);
      request.withCredentials = false;  // Don't send credentials for CORS requests
      
      request.onLoad.listen((_) {
        if (request.status == 200) {
          completer.complete(request.responseText);
        } else {
          completer.completeError(
            Exception('HTTP error ${request.status}: ${request.statusText}')
          );
        }
      });
      
      request.onError.listen((e) {
        completer.completeError(
          Exception('Failed to fetch $url: Network error')
        );
      });
      
      request.send();
      return await completer.future;
    } catch (e) {
      throw Exception('Failed to fetch $url: ${e.toString()}');
    }
  }
}

PlatformHttpClient createHttpClient() => WebHttpClient();