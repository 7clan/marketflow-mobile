import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../providers/auth_controller.dart';
import '../../widgets/error_view.dart';

/// Startup screen: restores the persisted session while the router holds
/// every other route here.
///
/// * `AsyncLoading` — brand mark + progress indicator;
/// * `AsyncError` — mapped error message + retry (re-runs the restore);
/// * resolved — this screen is immediately replaced by the router redirect
///   (`/login` or `/shop`), so no success branch is rendered.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  size: 48,
                  color: theme.colorScheme.onPrimaryContainer,
                  semanticLabel: 'MarketFlow',
                ),
              ),
              const SizedBox(height: 20),
              Text('MarketFlow', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Everything you need, from people you trust.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              if (auth.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ErrorView(
                    message: switch (auth.error) {
                      final AppException exception => exception.message,
                      _ => 'Something went wrong. Please try again.',
                    },
                    title: 'We could not sign you in',
                    retryLabel: 'Retry',
                    onRetry: () => ref.invalidate(authControllerProvider),
                  ),
                )
              else
                const SizedBox(
                  height: 28,
                  width: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
