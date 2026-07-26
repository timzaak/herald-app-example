import 'package:app/providers/account_providers.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:app/services/account/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_herald_app.dart';

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
}
