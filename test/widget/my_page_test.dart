import 'package:app/pages/account/legal_agreement_page.dart';
import 'package:app/providers/account_providers.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:app/services/account/account_service.dart';
import 'package:app/services/auth/legal_agreement_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_herald_app.dart';

class _FakeLegalAgreementService implements LegalAgreementService {
  @override
  Future<LegalAgreement> getAgreement({
    required String agreementType,
    required String locale,
  }) async => LegalAgreement(content: 'content:$agreementType');
}

void main() {
  testWidgets('My page displays the server-provided points total', (
    tester,
  ) async {
    // WHY: the backend total includes bucket/quota rules that the app must not
    // duplicate, so the page renders the provider value verbatim.
    final harness = await pumpHeraldApp(
      tester,
      overrides: [
        accountOverviewProvider.overrideWith(
          (ref) async => const AccountOverview(
            email: 'user@example.com',
            nickname: 'User',
            points: 1250,
          ),
        ),
      ],
    );
    harness.container.read(authStateProvider.notifier).seedAuthenticated(true);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();

    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.byKey(const ValueKey('pointsBalance')), findsOneWidget);
    expect(find.text('1250'), findsOneWidget);
    expect(find.byKey(const ValueKey('purchasePointsTile')), findsOneWidget);
  });

  testWidgets('Logout revokes the session and returns to login', (
    tester,
  ) async {
    final harness = await pumpHeraldApp(tester);
    harness.container.read(authStateProvider.notifier).seedAuthenticated(true);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(harness.repo.logoutCalls, hasLength(1));
    expect(
      harness.container.read(authStateProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
  });

  testWidgets('the user agreement entry opens the legal agreement page', (
    tester,
  ) async {
    // WHY: this entry was previously a "Not Implemented" toast; it must now
    // push the real LegalAgreementPage with the same agreementType the login
    // page uses, so both surfaces stay consistent.
    final harness = await pumpHeraldApp(
      tester,
      overrides: [
        legalAgreementServiceProvider.overrideWithValue(
          _FakeLegalAgreementService(),
        ),
      ],
    );
    harness.container.read(authStateProvider.notifier).seedAuthenticated(true);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.policy));
    await tester.pumpAndSettle();

    expect(find.byType(LegalAgreementPage), findsOneWidget);
    expect(find.text('content:terms_of_service'), findsOneWidget);
  });

  testWidgets('the privacy policy entry opens the legal agreement page', (
    tester,
  ) async {
    // WHY: mirrors the user-agreement case for the privacy entry; both must
    // navigate to the agreement page with their respective agreementType.
    final harness = await pumpHeraldApp(
      tester,
      overrides: [
        legalAgreementServiceProvider.overrideWithValue(
          _FakeLegalAgreementService(),
        ),
      ],
    );
    harness.container.read(authStateProvider.notifier).seedAuthenticated(true);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.privacy_tip));
    await tester.pumpAndSettle();

    expect(find.byType(LegalAgreementPage), findsOneWidget);
    expect(find.text('content:privacy_policy'), findsOneWidget);
  });
}
