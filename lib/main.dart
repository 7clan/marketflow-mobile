import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/datasources/market_api_host.dart';
import 'presentation/providers/infrastructure_providers.dart';

/// App bootstrap.
///
/// 1. starts the in-process deterministic mock marketplace server (real
///    HTTP on an ephemeral loopback port) — a production build replaces
///    this with an `appConfigProvider` override pointing at the real API;
/// 2. loads [SharedPreferences] once;
/// 3. runs the app with both wired into the [ProviderScope].
///
/// The server stops automatically when the scope is disposed (app shutdown
/// or test teardown).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final host = MarketApiHost();
  await host.start();

  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        mockApiHostProvider.overrideWith((ref) {
          ref.onDispose(() => unawaited(host.stop()));
          return host;
        }),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const MarketFlowApp(),
    ),
  );
}
