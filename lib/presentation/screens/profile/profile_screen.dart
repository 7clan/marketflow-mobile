import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../domain/entities/user.dart';
import '../../providers/auth_controller.dart';
import '../../providers/theme_mode_controller.dart';

/// Profile tab: account card, appearance preference, shortcuts, sign-out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AccountCard(user: user),
          const SizedBox(height: 16),
          const _AppearanceCard(),
          const SizedBox(height: 16),
          _ShortcutsCard(),
          const SizedBox(height: 16),
          _SignOutCard(user: user),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'MarketFlow v1.0.0',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sign-out with a confirmation dialog (destructive action).
Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text('Your cart and favorites stay saved on this device.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    await ref.read(authControllerProvider.notifier).logout();
    // The router's auth redirect handles the move to /login.
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = user?.name ?? 'MarketFlow shopper';
    final email = user?.email ?? 'Not signed in';
    final memberSince = user?.memberSince;

    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part.isEmpty ? '' : part[0])
        .join()
        .toUpperCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                initials.isEmpty ? 'MF' : initials,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (memberSince != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Member since ${Formatters.date(memberSince)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Theme mode preference (persisted by the controller).
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeControllerProvider);
    final controller = ref.read(themeModeControllerProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('Auto'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) =>
                    controller.setMode(selection.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('My orders'),
            subtitle: const Text('History, status and details'),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              semanticLabel: 'View orders',
            ),
            onTap: () => context.push('/orders'),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ListTile(
            leading: const Icon(Icons.favorite_border_rounded),
            title: const Text('My favorites'),
            subtitle: const Text('Saved products'),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              semanticLabel: 'View favorites',
            ),
            onTap: () => context.go('/favorites'),
          ),
        ],
      ),
    );
  }
}

class _SignOutCard extends ConsumerWidget {
  const _SignOutCard({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = user != null;
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          Icons.logout_rounded,
          color: signedIn ? theme.colorScheme.error : null,
        ),
        title: Text(signedIn ? 'Sign out' : 'Sign in'),
        subtitle: signedIn ? const Text('You can sign back in anytime') : null,
        onTap: () {
          if (signedIn) {
            _confirmSignOut(context, ref);
          } else {
            context.go('/login');
          }
        },
      ),
    );
  }
}
