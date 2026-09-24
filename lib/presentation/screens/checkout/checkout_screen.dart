import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../domain/entities/address.dart';
import '../../../domain/entities/order.dart';
import '../../providers/cart_controller.dart';
import '../../providers/checkout_controller.dart';
import '../../widgets/app_text_form_field.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/error_view.dart';

/// The checkout flow: `address → review → submitting → success | failure`.
///
/// All flow state lives in [checkoutControllerProvider]; this screen is a
/// pure renderer of [CheckoutStep] plus the address form's field
/// controllers (form text is inherently widget-local).
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _fullName = TextEditingController();
  late final _street = TextEditingController();
  late final _city = TextEditingController();
  late final _state = TextEditingController();
  late final _zip = TextEditingController();
  late final _country = TextEditingController();
  late final _phone = TextEditingController();

  /// Server-side (or controller) field errors, rendered as accessible
  /// `errorText` — cleared per-field as the user retypes.
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    // The flow restarts fresh whenever the user (re-)enters checkout — a
    // completed or abandoned flow must never leak into the next one.
    ref.read(checkoutControllerProvider.notifier).reset();
    final address = ref.read(checkoutControllerProvider).address;
    _fullName.text = address?.fullName ?? '';
    _street.text = address?.street ?? '';
    _city.text = address?.city ?? '';
    _state.text = address?.state ?? '';
    _zip.text = address?.zip ?? '';
    _country.text = address?.country ?? 'United States';
    _phone.text = address?.phone ?? '';
  }

  @override
  void dispose() {
    _fullName.dispose();
    _street.dispose();
    _city.dispose();
    _state.dispose();
    _zip.dispose();
    _country.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _clearFieldError(String key) {
    if (_fieldErrors.containsKey(key)) {
      _fieldErrors = {..._fieldErrors}..remove(key);
    }
  }

  Address _readAddress() => Address(
    fullName: _fullName.text.trim(),
    street: _street.text.trim(),
    city: _city.text.trim(),
    state: _state.text.trim(),
    zip: _zip.text.trim(),
    country: _country.text.trim(),
    phone: _phone.text.trim(),
  );

  void _submitAddress() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    ref.read(checkoutControllerProvider.notifier).submitAddress(_readAddress());
    // Invalid fields are recorded in the controller state; surface them.
    final errors = ref.read(checkoutControllerProvider).fieldErrors;
    setState(() => _fieldErrors = errors);
    _formKey.currentState?.validate();
  }

  @override
  Widget build(BuildContext context) {
    final checkout = ref.watch(checkoutControllerProvider);

    return PopScope(
      canPop: _canPop(checkout.step),
      child: Scaffold(
        appBar: AppBar(
          leading: _canPop(checkout.step)
              ? IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _onBack,
                )
              : null,
          title: const Text('Checkout'),
        ),
        body: switch (checkout.step) {
          CheckoutStep.editingAddress => _AddressStep(
            formKey: _formKey,
            fieldErrors: _fieldErrors,
            controllers: (
              fullName: _fullName,
              street: _street,
              city: _city,
              state: _state,
              zip: _zip,
              country: _country,
              phone: _phone,
            ),
            onFieldChanged: _clearFieldError,
            onContinue: _submitAddress,
          ),
          CheckoutStep.reviewing => const _ReviewStep(),
          CheckoutStep.submitting => const _SubmittingView(),
          CheckoutStep.success => _SuccessView(orderId: checkout.orderId!),
          CheckoutStep.failure => _FailureView(
            error: checkout.error!,
            onRetry: () =>
                ref.read(checkoutControllerProvider.notifier).retry(),
            onEditCart: () => context.pop(),
          ),
        },
      ),
    );
  }

  bool _canPop(CheckoutStep step) =>
      step == CheckoutStep.editingAddress || step == CheckoutStep.reviewing;

  void _onBack() {
    final step = ref.read(checkoutControllerProvider).step;
    if (step == CheckoutStep.reviewing) {
      ref.read(checkoutControllerProvider.notifier).backToEditing();
    } else {
      context.pop();
    }
  }
}

/// Progress header: Address → Review → Done.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current});

  /// 0 = address, 1 = review, 2 = done.
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const labels = ['Address', 'Review', 'Done'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _StepDot(index: i, current: current, labels: labels),
            if (i < labels.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  color: i < current
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.current,
    required this.labels,
  });

  final int index;
  final int current;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = index < current;
    final active = index == current;

    return Semantics(
      label:
          'Step ${index + 1} of ${labels.length}: ${labels[index]}, '
          '${done
              ? 'completed'
              : active
              ? 'current'
              : 'upcoming'}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: done || active
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              done ? Icons.check_rounded : Icons.circle_rounded,
              size: 14,
              color: done || active
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              labels[index],
              style: theme.textTheme.labelLarge?.copyWith(
                color: done || active
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 1 — the shipping address form.
class _AddressStep extends StatelessWidget {
  const _AddressStep({
    required this.formKey,
    required this.fieldErrors,
    required this.controllers,
    required this.onFieldChanged,
    required this.onContinue,
  });

  final GlobalKey<FormState> formKey;
  final Map<String, String> fieldErrors;
  final ({
    TextEditingController fullName,
    TextEditingController street,
    TextEditingController city,
    TextEditingController state,
    TextEditingController zip,
    TextEditingController country,
    TextEditingController phone,
  })
  controllers;
  final ValueChanged<String> onFieldChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _StepHeader(current: 0),
          const SizedBox(height: 12),
          AppTextFormField(
            controller: controllers.fullName,
            label: 'Full name',
            prefixIcon: Icons.person_outline,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.next,
            onChanged: (_) => onFieldChanged('fullName'),
            validator: (value) =>
                fieldErrors['fullName'] ?? Validators.name(value),
          ),
          const SizedBox(height: 16),
          AppTextFormField(
            controller: controllers.street,
            label: 'Street address',
            prefixIcon: Icons.home_outlined,
            autofillHints: const [AutofillHints.streetAddressLine1],
            textInputAction: TextInputAction.next,
            onChanged: (_) => onFieldChanged('street'),
            validator: (value) =>
                fieldErrors['street'] ?? Validators.street(value),
          ),
          const SizedBox(height: 16),
          AppTextFormField(
            controller: controllers.city,
            label: 'City',
            prefixIcon: Icons.location_city_outlined,
            autofillHints: const [AutofillHints.addressCity],
            textInputAction: TextInputAction.next,
            onChanged: (_) => onFieldChanged('city'),
            validator: (value) => fieldErrors['city'] ?? Validators.city(value),
          ),
          const SizedBox(height: 16),
          AppTextFormField(
            controller: controllers.state,
            label: 'State',
            prefixIcon: Icons.map_outlined,
            autofillHints: const [AutofillHints.addressState],
            textInputAction: TextInputAction.next,
            onChanged: (_) => onFieldChanged('state'),
            validator: (value) =>
                fieldErrors['state'] ?? Validators.region(value),
          ),
          const SizedBox(height: 16),
          AppTextFormField(
            controller: controllers.zip,
            label: 'ZIP code',
            prefixIcon: Icons.markunread_mailbox_outlined,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.postalCode],
            textInputAction: TextInputAction.next,
            onChanged: (_) => onFieldChanged('zip'),
            validator: (value) =>
                fieldErrors['zip'] ?? Validators.zipCode(value),
          ),
          const SizedBox(height: 16),
          AppTextFormField(
            controller: controllers.country,
            label: 'Country',
            prefixIcon: Icons.public,
            autofillHints: const [AutofillHints.countryName],
            textInputAction: TextInputAction.next,
            onChanged: (_) => onFieldChanged('country'),
            validator: (value) =>
                fieldErrors['country'] ??
                Validators.requiredField(value, label: 'Country'),
          ),
          const SizedBox(height: 16),
          AppTextFormField(
            controller: controllers.phone,
            label: 'Phone number',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textInputAction: TextInputAction.done,
            onChanged: (_) => onFieldChanged('phone'),
            validator: (value) =>
                fieldErrors['phone'] ?? Validators.phone(value),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Continue to review'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2 — review address, payment, items and totals; place the order.
class _ReviewStep extends ConsumerWidget {
  const _ReviewStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartControllerProvider);
    final checkout = ref.watch(checkoutControllerProvider);
    final address = checkout.address!;

    if (cart.isEmpty) {
      return EmptyView(
        icon: Icons.remove_shopping_cart_outlined,
        title: 'Your cart is empty',
        message: 'Add products before checking out.',
        actionLabel: 'Browse products',
        onAction: () => context.go('/shop'),
      );
    }

    final controller = ref.read(checkoutControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _StepHeader(current: 1),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Shipping address',
          trailing: TextButton.icon(
            onPressed: controller.backToEditing,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(address.fullName, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                '${address.street}\n'
                '${address.city}, ${address.state} ${address.zip}\n'
                '${address.country}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Payment method',
          child: RadioGroup<PaymentMethod>(
            groupValue: checkout.paymentMethod,
            onChanged: (method) {
              if (method != null) controller.setPaymentMethod(method);
            },
            child: const Column(
              children: [
                RadioListTile<PaymentMethod>.adaptive(
                  value: PaymentMethod.card,
                  title: Text('Credit or debit card'),
                  subtitle: Text('Charged when the order ships.'),
                  secondary: Icon(Icons.credit_card_rounded),
                ),
                RadioListTile<PaymentMethod>.adaptive(
                  value: PaymentMethod.cashOnDelivery,
                  title: Text('Cash on delivery'),
                  subtitle: Text('Pay the courier at your door.'),
                  secondary: Icon(Icons.payments_rounded),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Your items',
          child: Column(
            children: [
              for (final item in cart.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: CachedNetworkImage(
                            imageUrl: item.product.imageUrls.first,
                            fit: BoxFit.cover,
                            memCacheWidth: 150,
                            placeholder: (_, _) => ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                            errorWidget: (_, _, _) => ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${item.quantity} × ${item.product.title}',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Formatters.currency(item.lineTotal),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Order total',
          child: Column(
            children: [
              _TotalRow(
                label: 'Subtotal',
                value: Formatters.currency(cart.totals.subtotal),
              ),
              _TotalRow(
                label: 'Shipping',
                value: cart.totals.shipping == 0
                    ? 'Free'
                    : Formatters.currency(cart.totals.shipping),
              ),
              _TotalRow(
                label: 'Tax',
                value: Formatters.currency(cart.totals.tax),
              ),
              const Divider(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text('Total', style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    Formatters.currency(cart.totals.total),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: controller.confirmAndPlaceOrder,
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('Place order'),
          ),
        ),
      ],
    );
  }
}

class _SubmittingView extends StatelessWidget {
  const _SubmittingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Placing your order',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Placing your order…', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Please keep the app open.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 48,
                color: theme.colorScheme.onPrimaryContainer,
                semanticLabel: 'Order placed',
              ),
            ),
            const SizedBox(height: 20),
            Text('Order placed!', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(
                'Your order $orderId is confirmed.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.replace('/orders'),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('View orders'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.go('/shop'),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Continue shopping'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.error,
    required this.onRetry,
    required this.onEditCart,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onEditCart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ErrorView(
          message: switch (error) {
            AppException exception => exception.message,
            _ => 'Something went wrong. Please try again.',
          },
          title: 'We could not place your order',
          onRetry: onRetry,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onEditCart,
          icon: const Icon(Icons.shopping_cart_outlined),
          label: const Text('Back to cart'),
        ),
      ],
    );
  }
}

/// Reusable card section with a header row.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
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
