import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/presentation/widgets/error_view.dart';

void main() {
  group('ErrorView', () {
    testWidgets('shows title, message and a retry button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorView(
              message: 'Cannot reach the server.',
              onRetry: () {},
            ),
          ),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Cannot reach the server.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('hides the retry button without a callback', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ErrorView(message: 'Cannot reach the server.')),
        ),
      );

      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('tapping retry invokes the callback once', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorView(
              message: 'Cannot reach the server.',
              onRetry: () => retries++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(retries, 1);
    });

    testWidgets('the message is exposed to assistive technology', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ErrorView(message: 'Cannot reach the server.')),
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp('Cannot reach the server')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
