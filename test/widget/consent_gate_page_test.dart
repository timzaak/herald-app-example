// Widget tests for ConsentGatePage (FL-T01, design §4.4.2, §6.1).
//
// Pumps /consent with extra {agreements, originalFlow}; asserts:
// - Accept → replays the originating flow with the accepted agreements and
//   a FRESH Turnstile token; AuthSuccess → /index. The accepted agreements
//   are recorded on the fake's loginWithPasswordCalls.last.agreements.
// - Reject → /login with loginWithPasswordCalls unchanged.
// - Failure → stays on /consent (originalFlow preserved for retry).
//
// Per the Work §6 note: the "total == 2" obtainToken count includes the
// original flow's first call (login page), which is out of scope for this
// isolated page test. Here we assert the fresh-token-on-replay semantics:
// exactly ONE obtainToken call is made during the accept path. The full
// "original submit + fresh token" sequence is covered by integration tests.
import 'package:app/l10n/app_localizations.dart';
import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/auth_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../fakes/fake_herald_auth_repository.dart';
import '../fakes/fake_turnstile_service.dart';
import '../helpers/pump_herald_app.dart';

void main() {
  // The agreements the consent page renders and replays.
  final agreements = <AgreementView>[
    const AgreementView(
      id: 'terms-v1',
      title: 'Terms of Service',
      summary: 'summary',
      externalUrl: 'https://example.com/terms',
    ),
    const AgreementView(id: 'privacy-v1', title: 'Privacy Policy'),
  ];

  // originalFlow for the password-replay path. The page reads email/password
  // from this map and calls loginWithPassword with the accepted agreements.
  const originalFlow = <String, dynamic>{
    'kind': 'password',
    'email': 'user@example.com',
    'password': 'Password1',
  };

  Future<
    ({
      ProviderContainer container,
      FakeHeraldAuthRepository repo,
      FakeTurnstileService turnstile,
    })
  >
  pumpConsent(WidgetTester tester) async {
    return pumpHeraldApp(
      tester,
      initialLocation: '/consent',
      initialExtra: <String, dynamic>{
        'agreements': agreements,
        'originalFlow': originalFlow,
      },
    );
  }

  testWidgets(
    'Accept replays loginWithPassword with the accepted agreements + a '
    'fresh Turnstile token, then navigates to /index on success',
    (tester) async {
      final harness = await pumpConsent(tester);
      harness.repo.loginWithPasswordResult = FutureOrResult.value(
        authSuccess(),
      );
      // Opt into Turnstile so the accept path takes a fresh single-use token.
      harness.turnstile.returnToken = 'fresh-token';

      await tester.tap(find.byKey(const ValueKey('consentAcceptButton')));
      await tester.pump();
      await tester.pumpAndSettle();

      // AuthSuccess → /index (ShellRoute with BottomNavigationBar).
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byKey(const ValueKey('consentAcceptButton')), findsNothing);
      // The accepted flow was replayed exactly once with the agreements list.
      expect(harness.repo.loginCalls, hasLength(1));
      final replayed = harness.repo.loginCalls.single;
      expect(replayed.email, 'user@example.com');
      expect(replayed.password, 'Password1');
      expect(replayed.agreements, isNotNull);
      expect(replayed.agreements!.map((a) => a.versionId), [
        'terms-v1',
        'privacy-v1',
      ]);
      // Fresh Turnstile token taken on replay (single-use semantics).
      expect(replayed.turnstileToken, 'fresh-token');
      expect(harness.turnstile.obtainTokenCalls, 1);
    },
  );

  testWidgets(
    'Reject navigates to /login without replaying the originating flow',
    (tester) async {
      final harness = await pumpConsent(tester);

      await tester.tap(find.byKey(const ValueKey('consentRejectButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
      expect(
        harness.repo.loginCalls,
        isEmpty,
        reason: 'reject must not establish a session — no replay call',
      );
      expect(harness.turnstile.obtainTokenCalls, 0);
    },
  );

  testWidgets(
    'Failure keeps the user on /consent with the originalFlow preserved '
    '(retry path)',
    (tester) async {
      final harness = await pumpConsent(tester);
      harness.repo.loginWithPasswordResult = FutureOrResult.value(
        const AuthFailure(AuthError(AuthErrorKind.rateLimited)),
      );
      harness.turnstile.returnToken = 'fresh-token';

      await tester.tap(find.byKey(const ValueKey('consentAcceptButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Still on /consent — accept / reject buttons still present.
      expect(find.byKey(const ValueKey('consentAcceptButton')), findsOneWidget);
      expect(find.byKey(const ValueKey('consentRejectButton')), findsOneWidget);
      // Agreements still rendered (originalFlow preserved by the page).
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      // A failure toast was shown.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.rateLimited), findsWidgets);
      await drainSmartDialogToasts(tester);
    },
  );
}
