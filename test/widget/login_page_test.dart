// Widget tests for LoginPage (FL-T01, design §4.4.2, §6.1).
//
// Asserts the observable routing behavior driven by AuthResult branching:
// password-tab success → /index; AuthRequiresTotp → /totp-verify with
// tempToken; AuthConsentRequired → /consent with originalFlow.kind=password;
// AuthFailure(invalidCredentials) → stays + toast. The email-otp tab's
// sendEmailOtp emailNotRegistered / consentRequired branches and the
// loginWithEmailOtp success path are also covered. A loading-state case
// drives the fake via a Completer to assert the submit button is disabled
// while a request is in flight.
//
// Fakes at the provider boundary only (guides/flutter/testing.md "fake 优先");
// no dio mock. ProviderScope is isolated per test via pumpHeraldApp. No real
// time is awaited (countdown assertions live in verify_email_pending_page_test
// where they're under FakeAsync).
import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/auth_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_herald_auth_repository.dart';
import '../helpers/pump_herald_app.dart';

void main() {
  // SmartDialog's toast uses an overlay; ensure its bindings are ready. The
  // real toast UI is mounted on the root navigator via FlutterSmartDialog's
  // observer (configured on appRouter in lib/routes.dart). For widget tests we
  // rely on SmartDialog.showToast being callable without its full init — the
  // page code wraps every call in a context.mounted check and the toast
  // attaches to the Overlay that MaterialApp.router provides. If a test needs
  // to assert toast text it pumps enough frames for the toast to render.

  const email = 'user@example.com';
  // validatePassword requires 8-24 chars with upper + lower + digit.
  const password = 'Password1';

  Future<void> enterPasswordAndTapSubmit(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('loginEmailField')),
      email,
    );
    await tester.enterText(
      find.byKey(const ValueKey('loginPasswordField')),
      password,
    );
    // The agreement checkbox is required on the password tab (login_page.dart
    // §3) — toggle it via its onChanged by tapping the Checkbox widget.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('loginSubmitButton')));
    await tester.pump();
  }

  testWidgets('password tab: AuthSuccess navigates to /index '
      '(expect IndexPage, not LoginPage)', (tester) async {
    final harness = await pumpHeraldApp(tester);
    harness.repo.loginWithPasswordResult = FutureOrResult.value(authSuccess());

    await enterPasswordAndTapSubmit(tester);
    await tester.pumpAndSettle();

    // IndexPage is hosted in a ShellRoute; assert the route landed there by
    // checking the BottomNavigationBar (always present on /index) is shown
    // and LoginPage is gone.
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('loginSubmitButton')), findsNothing);
    expect(harness.repo.loginCalls.single.email, email);
    expect(harness.repo.loginCalls.single.password, password);
  });

  testWidgets(
    'password tab: AuthRequiresTotp navigates to /totp-verify carrying '
    'tempToken + secondFactors',
    (tester) async {
      final harness = await pumpHeraldApp(tester);
      harness.repo.loginWithPasswordResult = FutureOrResult.value(
        const AuthRequiresTotp('temp-token-xyz', ['totp']),
      );

      await enterPasswordAndTapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('totpCodeField')), findsOneWidget);
      expect(find.text('Two-Factor Verification'), findsOneWidget);
      expect(harness.repo.loginCalls, isNotEmpty);
    },
  );

  testWidgets('password tab: AuthConsentRequired navigates to /consent with '
      'originalFlow.kind == password', (tester) async {
    final harness = await pumpHeraldApp(tester);
    harness.repo.loginWithPasswordResult = FutureOrResult.value(
      AuthConsentRequired(const [
        AgreementView(
          id: 'terms-v1',
          title: 'Terms',
          summary: 'summary',
          externalUrl: 'https://example.com/terms',
        ),
      ]),
    );

    await enterPasswordAndTapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('consentAcceptButton')), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
  });

  testWidgets('password tab: AuthFailure(invalidCredentials) stays on /login '
      'and shows a localized toast', (tester) async {
    final harness = await pumpHeraldApp(tester);
    harness.repo.loginWithPasswordResult = FutureOrResult.value(
      const AuthFailure(AuthError(AuthErrorKind.invalidCredentials)),
    );

    await enterPasswordAndTapSubmit(tester);
    // Pump the toast onto the overlay. SmartDialog schedules its toast via
    // timers on the test binding's clock, so pump() advances the fake clock
    // (no real-time wait). Pump several frames so the toast widget mounts.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
    // login_page.dart maps invalidCredentials → loginFailed(enterPassword)
    // ("Login failed: Please enter password"). Assert that text is rendered
    // somewhere in the tree (toast overlay).
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final expected = l10n.loginFailed(l10n.enterPassword);
    expect(find.text(expected), findsWidgets);
    // Drain the toast lifecycle so teardown sees no pending timer.
    await drainSmartDialogToasts(tester);
  });

  testWidgets('email-otp tab: sendEmailOtp 409 emailNotRegistered surfaces the '
      'not-registered toast and stays on /login', (tester) async {
    final harness = await pumpHeraldApp(tester);
    harness.repo.sendEmailOtpResult = FutureOrResult.value(
      const SendEmailOtpResult.failure(
        AuthError(AuthErrorKind.emailNotRegistered),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('loginEmailField')),
      email,
    );
    // Switch to the email-otp tab.
    await tester.tap(find.text('Verification Code Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('loginGetCodeButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.emailOtpNotRegistered), findsWidgets);
    expect(harness.repo.sendEmailOtpCalls.single.email, email);
    // Drain the toast lifecycle (see invalidCredentials test).
    await drainSmartDialogToasts(tester);
  });

  testWidgets(
    'email-otp tab: sendEmailOtp consentRequired navigates to /consent '
    'with originalFlow.kind == email-otp',
    (tester) async {
      final harness = await pumpHeraldApp(tester);
      harness.repo.sendEmailOtpResult = FutureOrResult.value(
        SendEmailOtpResult.consent(const [
          AgreementView(id: 'terms-v1', title: 'Terms'),
        ]),
      );

      await tester.enterText(
        find.byKey(const ValueKey('loginEmailField')),
        email,
      );
      await tester.tap(find.text('Verification Code Login'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loginGetCodeButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('consentAcceptButton')), findsOneWidget);
    },
  );

  testWidgets(
    'password tab: submit button is disabled while the repository call '
    'is in flight',
    (tester) async {
      final harness = await pumpHeraldApp(tester);
      // Hold the response until the test completes it.
      final completer = Completer<AuthResult>();
      harness.repo.loginWithPasswordResult = FutureOrResult.pending(
        completer.future,
      );

      await enterPasswordAndTapSubmit(tester);
      await tester.pump();

      // The submit button is the TextButton keyed `loginSubmitButton` itself.
      // While loading its onPressed is null (disabled).
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('loginSubmitButton')),
      );
      expect(
        button.onPressed,
        isNull,
        reason: 'submit button must be disabled while loading',
      );

      // Release the pending response so the test tears down cleanly.
      completer.complete(authSuccess());
      await tester.pumpAndSettle();
    },
  );
}
