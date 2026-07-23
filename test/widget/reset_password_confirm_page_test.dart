// Widget tests for ResetPasswordConfirmPage (FL-T01, design §4.4.2, §6.1).
//
// Pumps /reset-password-confirm; fills code + new password + confirm; taps
// submit. Asserts:
// - Success → toast + /login.
// - AuthErrorException(network flavor) → stays on page + reset-code-invalid
//   toast (FL-D04 binding: the FL-D02 contract collapses non-configMissing
//   400s to `network`; the page maps both `network` and `configMissing` to
//   the resetCodeInvalid message).
// - Password-policy 400 (configMissing flavor) → stays on page.
// - Client-side password mismatch blocks submit (confirmResetPasswordCalls
//   stays empty — the form validator rejects before the repository is hit).
//
// Repository contract honored (FL-D02 binding): `confirmResetPassword` THROWS
// AuthErrorException on failure; it does NOT return an AuthFailure.
import 'package:app/l10n/app_localizations.dart';
import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/herald_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_herald_auth_repository.dart';
import '../helpers/pump_herald_app.dart';

void main() {
  const code = '123456';
  const newPassword = 'Password1';

  Future<FakeHeraldAuthRepository> fillAndSubmit(
    WidgetTester tester, {
    String confirmPassword = newPassword,
  }) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/reset-password-confirm',
      initialExtra: const <String, dynamic>{'email': 'user@example.com'},
    );
    final repo = harness.repo;
    await tester.enterText(
      find.byKey(const ValueKey('resetConfirmCodeField')),
      code,
    );
    await tester.enterText(
      find.byKey(const ValueKey('resetConfirmPasswordField')),
      newPassword,
    );
    await tester.enterText(
      find.byKey(const ValueKey('resetConfirmNewPasswordField')),
      confirmPassword,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('resetConfirmSubmitButton')));
    await tester.pump();
    return repo;
  }

  testWidgets('Success shows a toast and navigates to /login', (tester) async {
    final repo = await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
    expect(repo.confirmResetPasswordCalls.single.code, code);
    expect(repo.confirmResetPasswordCalls.single.newPass, newPassword);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.passwordResetSuccess), findsWidgets);
    await drainSmartDialogToasts(tester);
  });

  testWidgets(
    'AuthErrorException(network flavor) stays on the page and shows the '
    'reset-code-invalid toast',
    (tester) async {
      // Seed the error BEFORE filling (the fake reads it on submit).
      final harness = await pumpHeraldApp(
        tester,
        initialLocation: '/reset-password-confirm',
        initialExtra: const <String, dynamic>{'email': 'user@example.com'},
      );
      harness.repo.confirmResetPasswordError = const AuthErrorException(
        AuthError(AuthErrorKind.network),
      );

      await tester.enterText(
        find.byKey(const ValueKey('resetConfirmCodeField')),
        code,
      );
      await tester.enterText(
        find.byKey(const ValueKey('resetConfirmPasswordField')),
        newPassword,
      );
      await tester.enterText(
        find.byKey(const ValueKey('resetConfirmNewPasswordField')),
        newPassword,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('resetConfirmSubmitButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Still on /reset-password-confirm.
      expect(
        find.byKey(const ValueKey('resetConfirmSubmitButton')),
        findsOneWidget,
      );
      expect(harness.repo.confirmResetPasswordCalls, hasLength(1));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.resetCodeInvalid), findsWidgets);
      await drainSmartDialogToasts(tester);
    },
  );

  testWidgets('Password-policy 400 (configMissing flavor) stays on the page', (
    tester,
  ) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/reset-password-confirm',
      initialExtra: const <String, dynamic>{'email': 'user@example.com'},
    );
    // The FL-D02 contract maps Client-App-disabled / realm-capability 400 to
    // configMissing; the page also surfaces resetCodeInvalid for that bucket.
    harness.repo.confirmResetPasswordError = const AuthErrorException(
      AuthError(AuthErrorKind.configMissing),
    );

    await tester.enterText(
      find.byKey(const ValueKey('resetConfirmCodeField')),
      code,
    );
    await tester.enterText(
      find.byKey(const ValueKey('resetConfirmPasswordField')),
      newPassword,
    );
    await tester.enterText(
      find.byKey(const ValueKey('resetConfirmNewPasswordField')),
      newPassword,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('resetConfirmSubmitButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('resetConfirmSubmitButton')),
      findsOneWidget,
    );
    await drainSmartDialogToasts(tester);
  });

  testWidgets('Client-side password mismatch blocks submit '
      '(confirmResetPasswordCalls stays empty)', (tester) async {
    final repo = await fillAndSubmit(tester, confirmPassword: 'Different1');
    await tester.pumpAndSettle();

    // Form validator rejected → still on the page, no repository call.
    expect(
      find.byKey(const ValueKey('resetConfirmSubmitButton')),
      findsOneWidget,
    );
    expect(
      repo.confirmResetPasswordCalls,
      isEmpty,
      reason: 'password mismatch must block the repository call',
    );
  });
}
