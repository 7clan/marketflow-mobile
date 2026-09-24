import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../domain/entities/category.dart';
import '../../providers/categories_provider.dart';
import '../../providers/filter_controller.dart';
import '../../widgets/error_view.dart';
import '../../widgets/skeleton.dart';

/// The categories tab: every catalog category with its product count.
///
/// Tapping a category applies it as the feed filter and switches to the
/// shop tab (`/shop`), where the feed restarts filtered.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: switch (categories) {
        AsyncValue(hasValue: false) => SkeletonAnnouncer(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SkeletonPulse(
              child: Column(
                children: [
                  for (var i = 0; i < 7; i++)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: SkeletonTile(),
                    ),
                ],
              ),
            ),
          ),
        ),
        AsyncError(:final error) => ErrorView(
          message: switch (error) {
            AppException exception => exception.message,
            _ => 'Something went wrong. Please try again.',
          },
          title: 'We could not load categories',
          onRetry: () => ref.invalidate(categoriesProvider),
        ),
        AsyncValue(:final value!) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(categoriesProvider);
            await ref.read(categoriesProvider.future);
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: value.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final category = value[index];
              return _CategoryTile(
                category: category,
                onTap: () {
                  ref
                      .read(filterControllerProvider.notifier)
                      .setCategory(category.id);
                  context.go('/shop');
                },
              );
            },
          ),
        ),
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconFor(category.id, category.name),
                  color: theme.colorScheme.onSecondaryContainer,
                  semanticLabel: category.name,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${category.productCount} products',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
                semanticLabel: 'Browse ${category.name}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(String id, String name) {
    switch (id) {
      case 'c1':
        return Icons.devices_rounded;
      case 'c2':
        return Icons.kitchen_rounded;
      case 'c3':
        return Icons.sports_soccer_rounded;
      case 'c4':
        return Icons.checkroom_rounded;
      case 'c5':
        return Icons.auto_stories_rounded;
      case 'c6':
        return Icons.spa_rounded;
    }
    final lower = name.toLowerCase();
    if (lower.contains('electro')) return Icons.devices_rounded;
    if (lower.contains('home')) return Icons.kitchen_rounded;
    if (lower.contains('sport')) return Icons.sports_soccer_rounded;
    if (lower.contains('fashion') || lower.contains('cloth')) {
      return Icons.checkroom_rounded;
    }
    if (lower.contains('book')) return Icons.auto_stories_rounded;
    if (lower.contains('beauty')) return Icons.spa_rounded;
    return Icons.category_rounded;
  }
}
