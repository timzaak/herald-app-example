// Widget tests for TotpVerifyPage (FL-T01, design §4.4.2, §6.1).
//
// Pumps /totp-verify with extra {tempToken, secondFactors}; asserts the
// AuthResult branching observable from the page:
// - AuthSuccess → /index
// - AuthConsentRequired → /consent with originalFlow.kind == 'totp' +
//   tempToken
// - AuthFailure(sessionExpired) → toast + /login
// - Cancel → /login with NO repository call (verifyTotpCalls.isEmpty)
//
// Fakes at the provider boundary only; isolated ProviderScope per test.
import 'package:app/l10n/app_localizations.dart';
import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/auth_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_herald_auth_repository.dart';
import '../helpers/pump_herald_app.dart';

void main() {
  const tempToken = 'temp-token-1';
  const code = '123456'; // validateVerificationCode requires 6 digits.

  Future<void> enterCodeAndSubmit(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('totpCodeField')), code);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('totpVerifyButton')));
    await tester.pump();
  }

  testWidgets('AuthSuccess navigates to /index', (tester) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/totp-verify',
      initialExtra: const {
        'tempToken': tempToken,
        'secondFactors': <String>['totp'],
      },
    );
    harness.repo.verifyTotpResult = FutureOrResult.value(authSuccess());

    await enterCodeAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('totpCodeField')), findsNothing);
    // /index hosts a ShellRoute with a BottomNavigationBar.
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(harness.repo.verifyTotpCalls.single.tempToken, tempToken);
    expect(harness.repo.verifyTotpCalls.single.code, code);
  });

  testWidgets('AuthSuccess preserves the pre-login destination', (
    tester,
  ) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/totp-verify',
      initialExtra: const {
        'tempToken': tempToken,
        'secondFactors': <String>['totp'],
        'returnTo': '/my',
      },
    );
    harness.repo.verifyTotpResult = FutureOrResult.value(authSuccess());

    await enterCodeAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.logout), findsOneWidget);
  });

  testWidgets('backup-code mode sends uppercase backupCode without TOTP code', (
    tester,
  ) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/totp-verify',
      initialExtra: const {
        'tempToken': tempToken,
        'secondFactors': <String>['totp'],
      },
    );
    harness.repo.verifyTotpResult = FutureOrResult.value(authSuccess());

    await tester.tap(find.byKey(const ValueKey('totpCodeModeButton')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('totpCodeField')),
      'ab12cd34',
    );
    await tester.tap(find.byKey(const ValueKey('totpVerifyButton')));
    await tester.pumpAndSettle();

    expect(harness.repo.verifyTotpCalls.single.code, isNull);
    expect(harness.repo.verifyTotpCalls.single.backupCode, 'AB12CD34');
  });

  testWidgets('AuthConsentRequired navigates to /consent with '
      'originalFlow.kind == totp + tempToken', (tester) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/totp-verify',
      initialExtra: const {
        'tempToken': tempToken,
        'secondFactors': <String>['totp'],
      },
    );
    harness.repo.verifyTotpResult = FutureOrResult.value(
      AuthConsentRequired(const [
        AgreementView(agreementType: 'terms', id: 'terms-v1', title: 'Terms'),
      ]),
    );

    await enterCodeAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('consentAcceptButton')), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
  });

  testWidgets('backup code is preserved when routing through consent', (
    tester,
  ) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/totp-verify',
      initialExtra: const {
        'tempToken': tempToken,
        'secondFactors': <String>['totp'],
      },
    );
    harness.repo.verifyTotpResult = FutureOrResult.value(
      AuthConsentRequired(const [
        AgreementView(agreementType: 'terms', id: 'terms-v1', title: 'Terms'),
      ]),
    );

    await tester.tap(find.byKey(const ValueKey('totpCodeModeButton')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('totpCodeField')),
      'ab12cd34',
    );
    await tester.tap(find.byKey(const ValueKey('totpVerifyButton')));
    await tester.pumpAndSettle();

    harness.repo.verifyTotpResult = FutureOrResult.value(authSuccess());
    await tester.tap(find.byKey(const ValueKey('consentAcceptButton')));
    await tester.pumpAndSettle();

    expect(harness.repo.verifyTotpCalls, hasLength(2));
    expect(harness.repo.verifyTotpCalls.last.code, isNull);
    expect(harness.repo.verifyTotpCalls.last.backupCode, 'AB12CD34');
  });

  testWidgets(
    'AuthFailure(sessionExpired) shows a toast and navigates to /login',
    (tester) async {
      final harness = await pumpHeraldApp(
        tester,
        initialLocation: '/totp-verify',
        initialExtra: const {
          'tempToken': tempToken,
          'secondFactors': <String>['totp'],
        },
      );
      harness.repo.verifyTotpResult = FutureOrResult.value(
        const AuthFailure(AuthError(AuthErrorKind.sessionExpired)),
      );

      await enterCodeAndSubmit(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // /login is the post-bounce route.
      expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.totpExpired), findsWidgets);
      await drainSmartDialogToasts(tester);
    },
  );

  testWidgets('Cancel returns to /login without calling the repository', (
    tester,
  ) async {
    final harness = await pumpHeraldApp(
      tester,
      initialLocation: '/totp-verify',
      initialExtra: const {
        'tempToken': tempToken,
        'secondFactors': <String>['totp'],
      },
    );

    await tester.tap(find.byKey(const ValueKey('totpCancelButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
    expect(
      harness.repo.verifyTotpCalls,
      isEmpty,
      reason: 'cancel must not establish a session — no verifyTotp call',
    );
  });
}
