import 'package:marketflow/core/config/app_config.dart';
import 'package:marketflow/core/network/api_client.dart';
import 'package:marketflow/data/datasources/mock_marketplace_server.dart';

/// A started [MockMarketplaceServer] plus an [ApiClient] wired to it.
///
/// Latency is set to zero so repository tests run fast; specific tests
/// override `server.conditions` explicitly.
class MockApiHarness {
  MockApiHarness({required this.server, required this.apiClient});

  /// The live in-process backend (mutate `server.conditions` to inject
  /// failures).
  final MockMarketplaceServer server;

  /// A client whose token provider returns the harness [token] (possibly
  /// `null` for anonymous requests), or a dynamic provider when one was
  /// supplied.
  final ApiClient apiClient;
}

/// Starts a fresh server + client pair. Register disposal with
/// `addTearDown(harness.dispose)`.
///
/// [token] fixes a static bearer token; [tokenProvider] takes precedence and
/// is consulted on every request (use it to mirror the app wiring, where the
/// token comes from session storage).
Future<MockApiHarness> startMockApi({
  String? token,
  Future<String?> Function()? tokenProvider,
  Duration receiveTimeout = const Duration(seconds: 10),
}) async {
  final server = MockMarketplaceServer();
  server.conditions.latencyMinMs = 0;
  server.conditions.latencyMaxMs = 0;
  await server.start();
  final config = AppConfig(
    baseUrl: 'http://127.0.0.1:${server.port}',
    // Generous default so only tests that opt in ever hit timeouts.
    receiveTimeout: receiveTimeout,
  );
  final apiClient = ApiClient(
    config: config,
    tokenProvider: tokenProvider ?? () async => token,
  );
  return MockApiHarness(server: server, apiClient: apiClient);
}

extension MockApiHarnessDispose on MockApiHarness {
  /// Closes the client and the server. Register with `addTearDown`.
  Future<void> dispose() async {
    apiClient.close();
    await server.close();
  }
}
