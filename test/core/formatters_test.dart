import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/utils/formatters.dart';

void main() {
  group('Formatters.currency', () {
    test('formats whole dollars with two decimals', () {
      expect(Formatters.currency(1249), r'$1,249.00');
    });

    test('formats fractional amounts with thousands separators', () {
      expect(Formatters.currency(1249.99), r'$1,249.99');
      expect(Formatters.currency(1000000.5), r'$1,000,000.50');
    });

    test(r'zero renders as $0.00', () {
      expect(Formatters.currency(0), r'$0.00');
    });
  });

  group('Formatters.compactCurrency', () {
    test('compacts thousands with a K suffix', () {
      final formatted = Formatters.compactCurrency(1249.99);
      expect(formatted, r'$1.25K');
    });

    test('compacts millions with an M suffix', () {
      expect(Formatters.compactCurrency(2100000), r'$2.1M');
    });
  });

  group('Formatters.date', () {
    test('formats as MMM d, yyyy', () {
      expect(Formatters.date(DateTime(2026, 1, 5)), 'Jan 5, 2026');
      expect(Formatters.date(DateTime(2025, 12, 31)), 'Dec 31, 2025');
    });
  });

  group('Formatters.dateTime', () {
    test('appends a 12-hour clock time with AM/PM', () {
      final afternoon = Formatters.dateTime(DateTime(2026, 1, 5, 16, 30));
      expect(afternoon, startsWith('Jan 5, 2026'));
      expect(afternoon, contains('4:30'));
      expect(afternoon.endsWith('PM'), isTrue);

      final morning = Formatters.dateTime(DateTime(2026, 1, 5, 9, 5));
      expect(morning, startsWith('Jan 5, 2026'));
      expect(morning, contains('9:05'));
      expect(morning.endsWith('AM'), isTrue);
    });
  });

  group('Formatters.rating', () {
    test('renders one decimal', () {
      expect(Formatters.rating(4.6), '4.6');
      expect(Formatters.rating(3.0), '3.0');
      expect(Formatters.rating(5), '5.0');
    });

    test('rounds extra precision to one decimal', () {
      expect(Formatters.rating(4.64), '4.6');
      expect(Formatters.rating(4.65), '4.7');
    });
  });
}
