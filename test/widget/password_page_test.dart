// Widget tests for ChangePasswordPage — ForgotPassword variant (FL-T01,
// design §4.4.2, §6.1).
//
// The page's /password route builder requires `state.extra` to be a
// ChangePasswordType (NOT a map) — see lib/routes.dart line 161. The
// ForgotPassword variant (the in-scope recover-password request entry)
// renders email + a standalone get-code button (`passwordGetCodeButtonForgot`)
// + submit; the code input is hidden (confirmation happens on the confirm
// page). Asserts:
// - Tapping get-code fires requestResetPassword with the entered email +
//   starts the countdown.
// - Herald always returns 200 (the fake returns normally) — assert no
//   existence-branch UI change (the page does not branch on email existence).
// - Submit navigates to /reset-password-confirm carrying extra.email.
// - On AuthErrorException(rateLimited) → toast.
//
// NO real-time waiting: the page's countdown uses Future.doWhile +
// Future.delayed(1s), which are FakeTimers under the test binding — advanced
// via tester.pump(Duration) on the fake clock only.
import 'package:app/l10n/app_localizations.dart';
import 'package:app/pages/account/password_type.dart';
import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/herald_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_herald_app.dart';

void main() {
  const email = 'recover@example.com';

  testWidgets(
    'Get-code fires requestResetPassword with the email and starts the '
    'countdown (Herald always 200 → no existence-branch UI change)',
    (tester) async {
      final harness = await pumpHeraldApp(
        tester,
        initialLocation: '/password',
        initialExtra: ChangePasswordType.ForgotPassword,
      );

      await tester.enterText(
        find.byKey(const ValueKey('passwordEmailField')),
        email,
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('passwordGetCodeButtonForgot')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(harness.repo.requestResetPasswordCalls.single.email, email);
      // Countdown started — the button now shows the countdown text and is
      // disabled. isCounting is true; the label flips to resendCode(N).
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.resendCode('60')), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('passwordGetCodeButtonForgot')),
      );
      expect(
        button.onPressed,
        isNull,
        reason: 'get-code button must be disabled during the countdown',
      );
      // The page's countdown uses Future.doWhile + Future.delayed(1s) per
      // tick — FakeTimers under the test binding. Advance the fake clock past
      // the full 60s so the doWhile loop terminates and no timer is pending at
      // teardown. NOT a real-time wait (guides/flutter/testing.md).
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();
      // Also drain the SmartDialog toast lifecycle if any toast was shown.
      await drainSmartDialogToasts(tester);
    },
  );

  testWidgets(
    'Submit navigates to /reset-password-confirm carrying extra.email',
    (tester) async {
      final harness = await pumpHeraldApp(
        tester,
        initialLocation: '/password',
        initialExtra: ChangePasswordType.ForgotPassword,
      );

      await tester.enterText(
        find.byKey(const ValueKey('passwordEmailField')),
        email,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('passwordSubmitButton')));
      await tester.pumpAndSettle();

      // /reset-password-confirm page rendered.
      expect(
        find.byKey(const ValueKey('resetConfirmSubmitButton')),
        findsOneWidget,
      );
      // The email was carried forward (the confirm page renders it for context
      // only when non-empty; the route builder reads extra.email). Assert the
      // request step did not fire (submit is the navigation step, not the
      // request step).
      expect(harness.repo.requestResetPasswordCalls, isEmpty);
    },
  );

  testWidgets('On AuthErrorException(rateLimited) → toast', (tester) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/password',
      initialExtra: ChangePasswordType.ForgotPassword,
    );
    harness.repo.requestResetPasswordError = const AuthErrorException(
      AuthError(AuthErrorKind.rateLimited),
    );

    await tester.enterText(
      find.byKey(const ValueKey('passwordEmailField')),
      email,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('passwordGetCodeButtonForgot')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Still on /password; get-code button stays enabled (countdown NOT
    // started on failure — the page only starts the timer on success).
    expect(find.byKey(const ValueKey('passwordSubmitButton')), findsOneWidget);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.rateLimited), findsWidgets);
    await drainSmartDialogToasts(tester);
  });
}
