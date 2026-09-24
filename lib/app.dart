import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';

/// Root widget of MarketFlow.
///
/// PLACEHOLDER for the presentation wave: screens and routing land there.
/// The core / domain / data / state layers underneath are fully wired.
class MarketFlowApp extends StatelessWidget {
  const MarketFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarketFlow',
      debugShowCheckedModeBanner: false,
      theme: MarketFlowTheme.light,
      darkTheme: MarketFlowTheme.dark,
      home: const _PresentationPendingScreen(),
    );
  }
}

/// Minimal placeholder home screen (replaced by the real router/screens in
/// the presentation wave).
class _PresentationPendingScreen extends StatelessWidget {
  const _PresentationPendingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MarketFlow')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'MarketFlow',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Core, domain, data and application/state layers are wired. '
                'Screens land in the presentation wave.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
