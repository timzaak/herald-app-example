// Widget tests for RegisterPage (FL-T01, design §4.4.2, §6.1).
//
// Pumps /register; fills email + password + confirm; taps submit. Asserts:
// - RegisterResult(verificationRequired: true) → /verify-email-pending with
//   extra.email forwarded.
// - RegisterResult(false) → toast + /login.
// - AuthErrorException(emailAlreadyRegistered) → toast + stays.
// - Loading disables the submit button.
//
// Repository contract honored (FL-D02 binding): `register` THROWS
// AuthErrorException on failure; it does NOT return an AuthFailure. The fake
// surfaces this via `registerError`.
import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/auth_result.dart';
import 'package:app/services/auth/herald_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_herald_app.dart';

void main() {
  const email = 'newuser@example.com';
  const password = 'Password1'; // validatePassword: 8-24, upper+lower+digit.

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('registerEmailField')),
      email,
    );
    await tester.enterText(
      find.byKey(const ValueKey('registerPasswordField')),
      password,
    );
    await tester.enterText(
      find.byKey(const ValueKey('registerConfirmPasswordField')),
      password,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('registerSubmitButton')));
    await tester.pump();
  }

  testWidgets('disabled registration fails closed on direct navigation', (
    tester,
  ) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/register',
      registrationEnabled: false,
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('registrationDisabledTitle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('registerSubmitButton')), findsNothing);
    expect(harness.repo.registerCalls, isEmpty);
  });

  testWidgets('RegisterResult(verificationRequired: true) navigates to '
      '/verify-email-pending carrying the email', (tester) async {
    final harness = await pumpHeraldApp(tester, initialLocation: '/register');
    harness.repo.registerResult = const RegisterResult(true);

    await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('verifyEmailResendButton')),
      findsOneWidget,
    );
    expect(harness.repo.registerCalls.single.email, email);
    expect(harness.repo.registerCalls.single.password, password);
  });

  testWidgets(
    'RegisterResult(false) shows a success toast and navigates to /login',
    (tester) async {
      final harness = await pumpHeraldApp(tester, initialLocation: '/register');
      harness.repo.registerResult = const RegisterResult(false);

      await fillAndSubmit(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.registerSuccess), findsWidgets);
      await drainSmartDialogToasts(tester);
    },
  );

  testWidgets(
    'AuthErrorException(emailAlreadyRegistered) keeps the user on /register and '
    'shows the email-already-registered hint',
    (tester) async {
      final harness = await pumpHeraldApp(tester, initialLocation: '/register');
      harness.repo.registerError = const AuthErrorException(
        AuthError(AuthErrorKind.emailAlreadyRegistered),
      );

      await fillAndSubmit(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Still on /register.
      expect(
        find.byKey(const ValueKey('registerSubmitButton')),
        findsOneWidget,
      );
      expect(harness.repo.registerCalls, hasLength(1));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.textContaining(l10n.emailAlreadyRegistered), findsWidgets);
      await drainSmartDialogToasts(tester);
    },
  );

  testWidgets(
    'Submit button is disabled while the register call is in flight',
    (tester) async {
      final harness = await pumpHeraldApp(tester, initialLocation: '/register');
      final completer = Completer<RegisterResult>();
      // Drive the pending path via the future-result channel.
      harness.repo.registerPending = completer.future;

      await fillAndSubmit(tester);
      await tester.pump();

      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('registerSubmitButton')),
      );
      expect(
        button.onPressed,
        isNull,
        reason: 'submit button must be disabled while loading',
      );

      completer.complete(const RegisterResult(false));
      await tester.pumpAndSettle();
      await drainSmartDialogToasts(tester);
    },
  );
}
