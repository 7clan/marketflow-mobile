import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'presentation/providers/theme_mode_controller.dart';
import 'presentation/router/app_router.dart';

/// Root widget of MarketFlow: themes + declarative routing.
///
/// Both brightnesses derive from the deep-teal brand seed ([MarketFlowTheme])
/// and the light/dark/system preference is user-controlled from the profile
/// tab (persisted by [themeModeControllerProvider]).
class MarketFlowApp extends ConsumerWidget {
  const MarketFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeControllerProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'MarketFlow',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: MarketFlowTheme.light,
      darkTheme: MarketFlowTheme.dark,
      routerConfig: router,
    );
  }
}
