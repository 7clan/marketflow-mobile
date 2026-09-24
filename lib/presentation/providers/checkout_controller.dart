import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/validators.dart';
import '../../domain/entities/address.dart';
import '../../domain/entities/order.dart';
import 'cart_controller.dart';
import 'infrastructure_providers.dart';

/// Steps of the checkout flow.
enum CheckoutStep {
  /// Entering / editing the shipping address.
  editingAddress('Address'),

  /// Reviewing address, payment and totals.
  reviewing('Review'),

  /// Placing the order (network in flight).
  submitting('Placing order'),

  /// Order placed successfully.
  success('Done'),

  /// The order failed — retry or go back to the cart.
  failure('Failed');

  const CheckoutStep(this.label);

  /// Short human label (safe to render).
  final String label;
}

/// Rendered state of the checkout flow — a multi-step state machine.
class CheckoutState {
  const CheckoutState({
    this.step = CheckoutStep.editingAddress,
    this.address,
    this.paymentMethod = PaymentMethod.card,
    this.orderId,
    this.error,
    this.failureStep,
    this.fieldErrors = const <String, String>{},
  });

  /// Current step.
  final CheckoutStep step;

  /// The address being checked out with (`null` until submitted).
  final Address? address;

  /// Selected payment method (simulated).
  final PaymentMethod paymentMethod;

  /// Id of the successfully placed order ([CheckoutStep.success] only).
  final String? orderId;

  /// Error of the failed submission ([CheckoutStep.failure] only).
  final AppException? error;

  /// The step the failure should return to when the user retries/edits.
  final CheckoutStep? failureStep;

  /// Address form errors (`null` values mean valid). Keys match
  /// [Address] field names, so server-side 422s map onto the same fields.
  final Map<String, String> fieldErrors;

  /// `true` while the order is being placed.
  bool get isSubmitting => step == CheckoutStep.submitting;

  CheckoutState copyWith({
    CheckoutStep? step,
    Address? address,
    PaymentMethod? paymentMethod,
    String? orderId,
    Object? error = _unset,
    Object? failureStep = _unset,
    Map<String, String>? fieldErrors,
  }) {
    return CheckoutState(
      step: step ?? this.step,
      address: address ?? this.address,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      orderId: orderId ?? this.orderId,
      error: identical(error, _unset) ? this.error : error as AppException?,
      failureStep: identical(failureStep, _unset)
          ? this.failureStep
          : failureStep as CheckoutStep?,
      fieldErrors: fieldErrors ?? this.fieldErrors,
    );
  }

  /// Sentinel for [copyWith]'s nullable clears.
  static const _unset = Object();
}

/// The checkout flow:
/// `editingAddress → reviewing → submitting → success | failure(error, step)`.
///
/// The controller validates the address with the shared [Validators]
/// (server 422s land on the same field keys), submits via
/// [OrderRepository] and clears the cart on success. Conflicts (items that
/// went out of stock since the cart was loaded) surface as
/// [ConflictException] with the affected product ids.
final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);

class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() {
    // A checkout flow should restart fresh whenever the user re-enters it —
    // no keepAlive on purpose.
    return const CheckoutState();
  }

  /// Validates [address] locally and advances to the review step.
  ///
  /// Invalid fields keep the flow on [CheckoutStep.editingAddress] with the
  /// errors recorded in [CheckoutState.fieldErrors].
  void submitAddress(Address address) {
    final errors = _validateAddress(address);
    if (errors.isNotEmpty) {
      state = state.copyWith(
        address: address,
        fieldErrors: errors,
        step: CheckoutStep.editingAddress,
      );
      return;
    }
    state = state.copyWith(
      address: address,
      fieldErrors: const <String, String>{},
      step: CheckoutStep.reviewing,
    );
  }

  /// Returns from the review step to edit the address.
  void backToEditing() {
    state = state.copyWith(
      step: CheckoutStep.editingAddress,
      fieldErrors: const <String, String>{},
    );
  }

  /// Changes the (simulated) payment method.
  void setPaymentMethod(PaymentMethod method) {
    state = state.copyWith(paymentMethod: method);
  }

  /// Places the order with the current cart and address.
  Future<void> confirmAndPlaceOrder() async {
    final cart = ref.read(cartControllerProvider);
    final address = state.address;
    if (address == null) {
      state = state.copyWith(step: CheckoutStep.editingAddress);
      return;
    }
    if (cart.isEmpty) {
      state = state.copyWith(
        step: CheckoutStep.failure,
        error: const ValidationException(
          fieldErrors: {
            'items': ['Your cart is empty.'],
          },
        ),
        failureStep: CheckoutStep.reviewing,
      );
      return;
    }

    state = state.copyWith(step: CheckoutStep.submitting, error: null);
    final repository = ref.read(orderRepositoryProvider);
    try {
      final order = await repository.placeOrder(
        items: cart.items,
        address: address,
        paymentMethod: state.paymentMethod,
      );
      ref.read(cartControllerProvider.notifier).clear();
      state = CheckoutState(
        step: CheckoutStep.success,
        address: address,
        paymentMethod: state.paymentMethod,
        orderId: order.id,
      );
    } on ValidationException catch (error) {
      // Server-side address validation: back to the form with field errors.
      state = state.copyWith(
        step: CheckoutStep.editingAddress,
        fieldErrors: _firstMessages(error),
        error: error,
        failureStep: null,
      );
    } on AppException catch (error) {
      state = state.copyWith(
        step: CheckoutStep.failure,
        error: error,
        failureStep: CheckoutStep.reviewing,
      );
    }
  }

  /// Retries the failed submission (same address / payment / cart).
  Future<void> retry() => confirmAndPlaceOrder();

  /// Abandons the flow and resets to a clean state.
  void reset() => state = const CheckoutState();

  Map<String, String> _validateAddress(Address address) {
    final errors = <String, String>{};
    void check(String key, String? message) {
      if (message != null) errors[key] = message;
    }

    check('fullName', Validators.name(address.fullName));
    check('street', Validators.street(address.street));
    check('city', Validators.city(address.city));
    check('state', Validators.region(address.state));
    check('zip', Validators.zipCode(address.zip));
    check('phone', Validators.phone(address.phone));
    return errors;
  }

  /// Flattens the repository's field → messages map into field → message.
  Map<String, String> _firstMessages(ValidationException error) {
    return {
      for (final entry in error.fieldErrors.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value.first,
    };
  }
}
