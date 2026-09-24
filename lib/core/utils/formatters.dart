import 'package:intl/intl.dart';

/// Display formatting helpers (currency, dates, ratings).
///
/// All formatters are cached — creating [NumberFormat] / [DateFormat]
/// instances is expensive, and these run on every list item during scroll.
abstract final class Formatters {
  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_US',
    symbol: r'$',
    decimalDigits: 2,
  );

  static final NumberFormat _compactCurrency = NumberFormat.compactCurrency(
    locale: 'en_US',
    symbol: r'$',
  );

  static final DateFormat _date = DateFormat.yMMMd('en_US');

  static final DateFormat _dateTime = DateFormat.yMMMd('en_US').add_jm();

  static final NumberFormat _rating = NumberFormat('0.0', 'en_US');

  /// `$1,249.99` — full precision currency for prices and totals.
  static String currency(num amount) => _currency.format(amount);

  /// `$1.2K` — compact currency for dense tiles and chips.
  static String compactCurrency(num amount) => _compactCurrency.format(amount);

  /// `Jan 5, 2026` — order dates and member-since labels.
  static String date(DateTime value) => _date.format(value);

  /// `Jan 5, 2026 4:30 PM` — order timestamps.
  static String dateTime(DateTime value) => _dateTime.format(value);

  /// `4.6` — one-decimal product rating.
  static String rating(double value) => _rating.format(value);
}
