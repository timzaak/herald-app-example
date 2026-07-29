// Widget tests for the MyPage membership-display surface.
//
// Asserts the observable render + navigation behavior of the membership row
// and the IAP checkout subtitle. The membership display state is
// `lastFulfillment` (NOT authoritative entitlement — evidence limitation);
// these tests assert the null + non-null branches render the snapshot text
// and that the purchase entry navigates to /purchase.
//
// Fakes at the provider boundary only (guides/flutter/testing.md "fake 优先"):
// `accountOverviewProvider` is overridden per test with the membership state
// under assertion. No real-time waits. Per-test isolation: each test pumps a
// fresh harness.
import 'package:app/l10n/app_localizations.dart';
import 'package:app/providers/account_providers.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:app/services/account/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../helpers/pump_herald_app.dart';

/// Pumps the app authenticated at /my (a ShellRoute-protected route). The
/// harness's first pump happens with the default unauthenticated container, so
/// the redirect guard bounces to /login; authenticate, then navigate to /my so
/// the page mounts. Mirrors the purchase_page test helper's redirect handling.
Future<ProviderContainerShared> _pumpMyPage(
  WidgetTester tester, {
  required AccountOverview overview,
}) async {
  final harness = await pumpHeraldApp(
    tester,
    initialLocation: '/my',
    overrides: [accountOverviewProvider.overrideWith((ref) async => overview)],
  );
  harness.container.read(authStateProvider.notifier).seedAuthenticated(true);
  final ctx = tester.element(find.byType(Navigator).first);
  GoRouter.of(ctx).go('/my');
  await tester.pumpAndSettle();
  return harness.container;
}

/// Readability alias for the Riverpod container type.
typedef ProviderContainerShared = ProviderContainer;

void main() {
  testWidgets(
    'membership == null (default): renders membershipNone + the IAP '
    'checkout subtitle; NO stripe/creem subtitle text',
    (tester) async {
      // WHY: getOverview() leaves membership null (no backend entitlement
      // field — evidence limitation). The null branch must surface the
      // "no membership" text + a purchase entry whose subtitle is the IAP
      // text (iapCheckoutSubtitle), NOT the legacy stripe/creem text
      // (the subtitle was repurposed).
      await _pumpMyPage(
        tester,
        overview: const AccountOverview(
          email: 'user@example.com',
          nickname: 'User',
          points: 0,
          membership: null,
        ),
      );

      // Membership row renders the null-branch text.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.membershipNone), findsOneWidget);
      // The membership row has the membershipStatus ValueKey.
      expect(find.byKey(const ValueKey('membershipStatus')), findsOneWidget);
      // The purchase entry tile is present with the IAP subtitle.
      expect(find.byKey(const ValueKey('purchasePointsTile')), findsOneWidget);
      expect(find.text(l10n.iapCheckoutSubtitle), findsOneWidget);
      // Widget-layer proof: the legacy stripe/creem subtitle text is
      // NOT shown on the purchase tile.
      expect(
        find.text(l10n.stripeCreemCheckout),
        findsNothing,
        reason: 'the IAP subtitle replaced the stripe/creem one',
      );
    },
  );

  testWidgets(
    'membership != null: renders membershipStatus row with the entitlementKey + '
    'billingType snapshot (lastFulfillment, NOT verified entitlement)',
    (tester) async {
      // WHY: when a membership display value is present (lastFulfillment
      // snapshot), the row renders the entitlementKey + billingType. The
      // wording is a display snapshot — NOT "verified entitlement" (evidence
      // limitation). This guards the non-null branch.
      await _pumpMyPage(
        tester,
        overview: const AccountOverview(
          email: 'user@example.com',
          points: 100,
          membership: MembershipStatus(
            entitlementKey: 'pro',
            billingType: 'recurring',
          ),
        ),
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // The membership row renders the snapshot: "Active: pro (recurring)".
      expect(find.byKey(const ValueKey('membershipStatus')), findsOneWidget);
      expect(
        find.text('${l10n.membershipActive}: pro (recurring)'),
        findsOneWidget,
        reason:
            'the row renders the lastFulfillment snapshot '
            '(entitlementKey + billingType)',
      );
      // The null-branch text must NOT render when a membership is present.
      expect(find.text(l10n.membershipNone), findsNothing);
    },
  );

  testWidgets('tapping purchasePointsTile navigates to /purchase', (
    tester,
  ) async {
    // WHY: the purchase entry must route to the IAP purchase page.
    await _pumpMyPage(
      tester,
      overview: const AccountOverview(email: 'user@example.com', points: 0),
    );

    await tester.tap(find.byKey(const ValueKey('purchasePointsTile')));
    await tester.pumpAndSettle();

    // The purchase page mounted (its AppBar title is `purchasePoints`).
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.purchasePoints), findsOneWidget);
  });
}
