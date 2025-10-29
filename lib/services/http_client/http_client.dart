import 'platform_http_client.dart';
import 'web/platform_http_client_web.dart' if (dart.library.io) 'io/platform_http_client_io.dart' as impl;

export 'platform_http_client.dart';

PlatformHttpClient createPlatformHttpClient() => impl.createHttpClient();