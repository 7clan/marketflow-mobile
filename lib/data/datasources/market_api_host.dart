import 'mock_marketplace_server.dart';

/// Owns the lifecycle of the in-process mock marketplace API.
///
/// The host is started **once at app bootstrap** (see `main.dart`) and
/// stopped when the [ProviderScope] is disposed. Everything downstream —
/// `AppConfig`, `ApiClient`, repositories — resolves its base URL from the
/// running host, so a production swap is a single `appConfigProvider`
/// override pointing at a real backend.
class MarketApiHost {
  MarketApiHost({MockMarketplaceServer? server})
    : server = server ?? MockMarketplaceServer();

  /// The underlying deterministic mock server (expose conditions here).
  final MockMarketplaceServer server;

  Future<void>? _starting;

  /// Binds the server to an ephemeral loopback port. Idempotent — repeated
  /// calls return the same in-flight/complete future.
  Future<void> start() => _starting ??= server.start();

  /// Stops the server. Safe to call twice.
  Future<void> stop() => server.close();

  /// The bound port, or `null` while stopped.
  int? get port => server.port;

  /// The HTTP origin clients should talk to.
  ///
  /// Throws a [StateError] with a fix-it hint when accessed before [start]
  /// completed — misconfiguration should fail loudly, not silently.
  String get baseUrl {
    final boundPort = server.port;
    if (boundPort == null) {
      throw StateError(
        'MarketApiHost is not running — await host.start() before resolving '
        'AppConfig (see main.dart for the bootstrap pattern).',
      );
    }
    return 'http://127.0.0.1:$boundPort';
  }

  /// `true` while the server is bound.
  bool get isRunning => server.isRunning;
}

/// Starts a fresh [MarketApiHost] — the bootstrap helper used by `main()`
/// and by tests.
Future<MarketApiHost> startMockApiHost() async {
  final host = MarketApiHost();
  await host.start();
  return host;
}
