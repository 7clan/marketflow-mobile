import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/utils/debouncer.dart';

void main() {
  group('Debouncer', () {
    test(
      'rapid calls fire only the last action after the quiet period',
      () async {
        final debouncer = Debouncer(delay: const Duration(milliseconds: 20));
        final fired = <String>[];

        for (var i = 0; i < 5; i++) {
          debouncer(() => fired.add('action-$i'));
          // Keep calling well inside the quiet period.
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        expect(fired, isEmpty, reason: 'nothing fires while typing continues');
        expect(debouncer.isPending, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(fired, ['action-4'], reason: 'only the most recent action runs');
        expect(debouncer.isPending, isFalse);
      },
    );

    test('an action fires exactly once after the quiet period', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 10));
      var calls = 0;
      debouncer(() => calls++);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(calls, 1);
    });

    test('different delays are honored', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 80));
      var fired = false;
      debouncer(() => fired = true);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fired, isFalse, reason: 'the 80ms quiet period has not elapsed');

      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(fired, isTrue);
    });

    test('cancel drops the pending action', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 10));
      var fired = false;
      debouncer(() => fired = true);
      debouncer.cancel();

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(fired, isFalse);
      expect(debouncer.isPending, isFalse);
    });

    test(
      'dispose drops the pending action and blocks future scheduling',
      () async {
        final debouncer = Debouncer(delay: const Duration(milliseconds: 10));
        var fired = 0;
        debouncer(() => fired++);
        debouncer.dispose();
        debouncer(() => fired++); // ignored: disposed

        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(fired, 0);
        expect(debouncer.isPending, isFalse);
      },
    );

    test('a scheduled action can reschedule before firing', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 30));
      final order = <String>[];
      debouncer(() => order.add('first'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      debouncer(() => order.add('second'));

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(order, ['second'], reason: 'the first action was replaced');
    });
  });
}
