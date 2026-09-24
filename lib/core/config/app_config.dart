/// Environment-level configuration for the app's HTTP pipeline.
///
/// The app ships with a deterministic in-process mock marketplace server (see
/// `lib/data/datasources/mock_marketplace_server.dart`). Pointing [baseUrl]
/// at a real backend is the only change required to swap it out — every
/// repository talks to this config through the [Dio] client.
class AppConfig {
  /// Creates a configuration for an explicit backend origin, e.g.
  /// `https://api.marketflow.dev/v1`.
  const AppConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 8),
    this.receiveTimeout = const Duration(seconds: 12),
    this.sendTimeout = const Duration(seconds: 10),
    this.pageSize = defaultPageSize,
  });

  /// Creates a configuration pointed at the in-process mock server.
  factory AppConfig.localServer({required int port}) =>
      AppConfig(baseUrl: 'http://127.0.0.1:$port');

  /// Default number of items fetched per feed page.
  static const int defaultPageSize = 20;

  /// Backend origin every relative request path is resolved against.
  final String baseUrl;

  /// Aborts requests that cannot even establish a connection in time.
  final Duration connectTimeout;

  /// Aborts requests whose response body trickles in too slowly.
  final Duration receiveTimeout;

  /// Aborts requests whose request body cannot be uploaded in time.
  final Duration sendTimeout;

  /// Default page size used by paginated product queries.
  final int pageSize;
}
