/// Common interface for platform-specific HTTP clients
abstract class PlatformHttpClient {
  /// Fetches content from a URL and returns it as a string
  Future<String> fetchString(String url);
}