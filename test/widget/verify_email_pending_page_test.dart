// Widget tests for VerifyEmailPendingPage (FL-T01, design §4.4.2, §6.1).
//
// Pumps /verify-email-pending with extra {email}; asserts:
// - Tapping resend calls resendVerification with the forwarded email and
//   shows the success toast.
// - The resend button is rate-limited by the 60s countdown — after a resend,
//   the button is disabled / shows the countdown text; only re-enables after
//   the countdown elapses.
// - "Back to login" navigates to /login.
//
// NO real-time waiting (guides/flutter/testing.md "禁止真实时间等待"): the
// page's Timer.periodic is a FakeTimer under the test binding; we advance it
// via tester.pump(Duration), which advances the binding's fake clock only.
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_herald_auth_repository.dart';
import '../helpers/pump_herald_app.dart';

void main() {
  const email = 'pending@example.com';

  Future<FakeHeraldAuthRepository> pumpPending(WidgetTester tester) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/verify-email-pending',
      initialExtra: const <String, dynamic>{'email': email},
    );
    return harness.repo;
  }

  testWidgets(
    'Resend calls resendVerification with the forwarded email and shows '
    'the success toast',
    (tester) async {
      final repo = await pumpPending(tester);

      await tester.tap(find.byKey(const ValueKey('verifyEmailResendButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(repo.resendVerificationCalls.single, email);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.verificationEmailSent), findsWidgets);
      await drainSmartDialogToasts(tester);
    },
  );

  testWidgets(
    'Resend button is rate-limited by the 60s countdown, then re-enables',
    (tester) async {
      final repo = await pumpPending(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // First resend succeeds and starts the 60s countdown.
      await tester.tap(find.byKey(const ValueKey('verifyEmailResendButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The toast + countdown are now both pending. Pump one short step to
      // read the countdown BEFORE the drain advances it too far.
      expect(
        find.text(l10n.resendCode('60')),
        findsOneWidget,
        reason: 'after a resend the button shows the 60s countdown',
      );
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('verifyEmailResendButton')),
      );
      expect(
        button.onPressed,
        isNull,
        reason: 'resend button must be disabled during the countdown',
      );

      // Tap-while-counting-down does NOT fire another resend (the page guards
      // on seconds != null).
      await tester.tap(find.byKey(const ValueKey('verifyEmailResendButton')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.resendVerificationCalls, hasLength(1));

      // Drain the toast lifecycle (also advances the countdown, which is fine).
      await drainSmartDialogToasts(tester);

      // Advance the fake clock past the remaining 60s countdown. The page's
      // Timer.periodic decrements seconds each second; at 0 it nulls seconds
      // and re-enables the button.
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();

      // Button re-enabled and showing the idle label again.
      expect(find.text(l10n.resendVerificationEmail), findsOneWidget);
      final buttonAfter = tester.widget<TextButton>(
        find.byKey(const ValueKey('verifyEmailResendButton')),
      );
      expect(
        buttonAfter.onPressed,
        isNotNull,
        reason: 'resend button must re-enable after the countdown elapses',
      );
    },
  );

  testWidgets('"Back to login" navigates to /login', (tester) async {
    await pumpPending(tester);

    await tester.tap(
      find.byKey(const ValueKey('verifyEmailBackToLoginButton')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
  });
}
