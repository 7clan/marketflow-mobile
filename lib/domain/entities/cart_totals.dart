import 'cart_item.dart';

/// Derived monetary summary of a cart, produced by [computeCartTotals].
///
/// Totals are always computed (never stored) so every UI surface shows the
/// same numbers from the same item list.
class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.shipping,
    required this.tax,
    required this.total,
  });

  final double subtotal;
  final double shipping;
  final double tax;
  final double total;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CartTotals &&
        other.subtotal == subtotal &&
        other.shipping == shipping &&
        other.tax == tax &&
        other.total == total;
  }

  @override
  int get hashCode => Object.hash(subtotal, shipping, tax, total);

  @override
  String toString() =>
      'CartTotals(subtotal: $subtotal, shipping: $shipping, tax: $tax, '
      'total: $total)';
}

/// Marketplace pricing rules.
///
/// These constants are mirrored server-side: the mock backend recomputes
/// order totals from the same formulas, so the amounts the user reviews are
/// exactly what the order records.
abstract final class CartPricing {
  /// Flat shipping fee below the free-shipping threshold.
  static const double standardShipping = 8.99;

  /// Subtotals at or above this amount ship for free.
  static const double freeShippingThreshold = 99.0;

  /// Sales tax applied to the subtotal.
  static const double taxRate = 0.085;

  /// Shipping cost for a given subtotal.
  static double shippingFor(double subtotal) {
    if (subtotal <= 0) return 0;
    return subtotal >= freeShippingThreshold ? 0 : standardShipping;
  }
}

/// Pure pricing function — no I/O, no clocks, deterministic.
CartTotals computeCartTotals(List<CartItem> items) {
  final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
  final roundedSubtotal = _round2(subtotal);
  final shipping = CartPricing.shippingFor(roundedSubtotal);
  final tax = _round2(roundedSubtotal * CartPricing.taxRate);
  return CartTotals(
    subtotal: roundedSubtotal,
    shipping: shipping,
    tax: tax,
    total: _round2(roundedSubtotal + shipping + tax),
  );
}

double _round2(double value) => (value * 100).round() / 100;
