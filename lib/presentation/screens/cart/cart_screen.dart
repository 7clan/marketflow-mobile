import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../domain/entities/cart_item.dart';
import '../../../domain/entities/cart_totals.dart';
import '../../providers/cart_controller.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/quantity_stepper.dart';

/// The cart tab: line items with steppers, validation messages, derived
/// totals (always [CartTotals] from the same items) and the checkout CTA.
///
/// The cart lives in a provider and is persisted by the controller — this
/// screen renders state and forwards intents only.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);

    // Announce persistence failures without reverting the optimistic cart.
    ref.listen(cartControllerProvider.select((state) => state.error), (
      previous,
      next,
    ) {
      if (next != null) {
        ref.read(cartControllerProvider.notifier).clearError();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.message)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: cart.isEmpty
          ? EmptyView(
              icon: Icons.shopping_cart_outlined,
              title: 'Your cart is empty',
              message: 'Browse the marketplace and add something you love.',
              actionLabel: 'Browse products',
              onAction: () => context.go('/shop'),
            )
          : _CartBody(cart: cart),
    );
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({required this.cart});

  final CartState cart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            itemCount: cart.items.length,
            itemBuilder: (context, index) => _CartLineCard(
              item: cart.items[index],
              validationMessage: cart.messageFor(cart.items[index].product.id),
            ),
          ),
        ),
        _TotalsFooter(totals: cart.totals),
      ],
    );
  }
}

/// One cart line: image, title, unit price, stepper (bounded by stock and
/// the per-line maximum), line total and remove.
class _CartLineCard extends ConsumerWidget {
  const _CartLineCard({required this.item, required this.validationMessage});

  final CartItem item;
  final String? validationMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final product = item.product;
    final maxQuantity = product.stock > 0
        ? (product.stock < CartItem.maxQuantity
              ? product.stock
              : CartItem.maxQuantity)
        : CartItem.maxQuantity;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: InkWell(
                    onTap: () =>
                        context.push('/product/${product.id}', extra: product),
                    child: CachedNetworkImage(
                      imageUrl: product.imageUrls.first,
                      fit: BoxFit.cover,
                      memCacheWidth: 220,
                      placeholder: (_, _) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (_, _, _) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                          semanticLabel: 'Image unavailable',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Formatters.currency(item.unitPrice)} each',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        QuantityStepper(
                          value: item.quantity,
                          min: 1,
                          max: maxQuantity,
                          compact: true,
                          onChanged: (value) => ref
                              .read(cartControllerProvider.notifier)
                              .updateQuantity(product.id, value),
                        ),
                        const Spacer(),
                        Text(
                          Formatters.currency(item.lineTotal),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    if (validationMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Semantics(
                label: 'Remove ${product.title} from cart',
                button: true,
                child: IconButton(
                  tooltip: 'Remove from cart',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => ref
                      .read(cartControllerProvider.notifier)
                      .removeItem(product.id),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Totals summary, free-shipping hint and the checkout CTA.
class _TotalsFooter extends ConsumerWidget {
  const _TotalsFooter({required this.totals});

  final CartTotals totals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final remaining = CartPricing.freeShippingThreshold - totals.subtotal;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (remaining > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'You are ${Formatters.currency(remaining)} away from '
                      'free shipping',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                _TotalRow(
                  label: 'Subtotal',
                  value: Formatters.currency(totals.subtotal),
                ),
                _TotalRow(
                  label: 'Shipping',
                  value: totals.shipping == 0
                      ? 'Free'
                      : Formatters.currency(totals.shipping),
                ),
                _TotalRow(
                  label: 'Tax (8.5%)',
                  value: Formatters.currency(totals.tax),
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text('Total', style: theme.textTheme.titleMedium),
                    ),
                    Text(
                      Formatters.currency(totals.total),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/checkout'),
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: const Text('Checkout'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
