import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/presentation/providers/auth_controller.dart';
import 'package:marketflow/presentation/screens/auth/login_screen.dart';

import '../helpers/fake_repositories.dart';

void main() {
  late FakeAuthRepository authRepository;

  Future<ProviderContainer> pumpLogin(WidgetTester tester) async {
    final container = await createFakeRepositoryContainer(
      authRepository: authRepository,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    return container;
  }

  setUp(() {
    authRepository = FakeAuthRepository();
  });

  Finder emailField() => find.byType(TextFormField).at(0);
  Finder passwordField() => find.byType(TextFormField).at(1);

  bool passwordIsObscured(WidgetTester tester) => (tester.widget(
    find.descendant(of: passwordField(), matching: find.byType(TextField)),
  ) as TextField).obscureText;

  group('LoginScreen — validation', () {
    testWidgets('empty submit shows per-field inline errors', (tester) async {
      await pumpLogin(tester);

      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(
        find.text('Email is required.'),
        findsOneWidget,
        reason: 'email field must render its errorText',
      );
      expect(
        find.text('Password is required.'),
        findsOneWidget,
        reason: 'password field must render its errorText',
      );
      expect(
        authRepository.loginCalls,
        0,
        reason: 'client-side validation must not hit the repository',
      );
    });

    testWidgets('a malformed email is rejected inline', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(emailField(), 'not-an-email');
      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(authRepository.loginCalls, 0);
    });
  });

  group('LoginScreen — submission', () {
    testWidgets('valid demo credentials drive a loading state', (tester) async {
      // The gate keeps the login request in flight until the test opens it.
      final gate = Completer<void>();
      authRepository = FakeAuthRepository(loginGate: gate);
      final container = await pumpLogin(tester);

      await tester.enterText(emailField(), 'demo@marketflow.dev');
      await tester.enterText(passwordField(), 'Password123');
      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(authRepository.loginCalls, 1);
      // Loading: the submit button turns into a progress indicator and the
      // demo-prefill button is disabled while in flight.
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        (tester.widget(
          find.byType(OutlinedButton),
        ) as OutlinedButton).onPressed,
        isNull,
      );

      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // Settled: authenticated through the controller, button re-enabled.
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        (tester.widget(find.byType(FilledButton)) as FilledButton).onPressed,
        isNotNull,
      );
    });

    testWidgets('wrong credentials surface a mapped error banner', (
      tester,
    ) async {
      await pumpLogin(tester);

      await tester.enterText(emailField(), 'demo@marketflow.dev');
      await tester.enterText(passwordField(), 'WrongPass1');
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.text('Invalid email or password.'),
        findsOneWidget,
        reason: 'the 401 message is user-safe copy, not raw Dio output',
      );
      expect(
        find.text('Email is required.'),
        findsNothing,
        reason: 'a form-level failure must not re-assert field errors',
      );
    });
  });

  group('LoginScreen — accessibility', () {
    testWidgets('the password field is obscured with a labeled toggle', (
      tester,
    ) async {
      await pumpLogin(tester);

      final obscured = passwordIsObscured(tester);
      expect(
        obscured,
        isTrue,
        reason: 'passwords must not render as plain text',
      );

      expect(find.bySemanticsLabel('Show password'), findsOneWidget);
      await tester.tap(find.byTooltip('Show'));
      await tester.pump();

      expect(passwordIsObscured(tester), isFalse);
      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
    });

    testWidgets('form fields and the submit button expose semantics', (
      tester,
    ) async {
      await pumpLogin(tester);

      // Every input is labeled for screen readers.
      expect(find.bySemanticsLabel('Email'), findsOneWidget);
      expect(find.bySemanticsLabel('Password'), findsOneWidget);

      // The submit button starts enabled.
      final button = tester.widget(find.byType(FilledButton)) as FilledButton;
      expect(button.onPressed, isNotNull);
    });
  });
}
