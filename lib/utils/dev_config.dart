class DevConfig {
  // Toggle to route feed fetches through the local dev CORS proxy
  static bool useDevCorsProxy = false;
  static const devProxyBase = 'http://localhost:8081/fetch?url=';
}