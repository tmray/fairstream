import 'dart:async';
import 'package:web/web.dart' as web;
import '../platform_http_client.dart';

/// Web-specific implementation of PlatformHttpClient that bypasses CORS
class WebHttpClient implements PlatformHttpClient {
  @override
  Future<String> fetchString(String url) async {
    try {
      final request = web.XMLHttpRequest();
      final completer = Completer<String>();
      
      request.open('GET', url);
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
      
      request.onError.listen((_) {
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