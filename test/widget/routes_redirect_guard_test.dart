// Widget tests for the routes.dart redirect guard (FL-T01, design §4.4.3).
//
// The guard reads the router's `authStateProvider` synchronously. For this
// test we drive the real notifier via the returned test container's
// `authStateProvider.notifier` (Riverpod 3 binding — `authStateProvider` is a
// NotifierProvider, NOT a StateNotifierProvider; the item's §11 instruction
// to override as a StateNotifierProvider is spec drift). Asserts:
// - Unauthenticated + protected route (/index) → redirect to
//   /login?returnTo=%2Findex.
// - Authenticated + /login → redirect to /index.
// - Unauthenticated + each anonymous path → no redirect (page renders).
// - returnTo round-trip: bounce to /login with a protected target encoded;
//   flip authStateProvider to authenticated; assert LoginPage reads returnTo
//   and navigates there on success.
import 'package:app/pages/account/password_type.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:app/services/auth/auth_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_herald_auth_repository.dart';
import '../helpers/pump_herald_app.dart';

void main() {
  testWidgets(
    'Unauthenticated + /index → redirect to /login?returnTo=%2Findex',
    (tester) async {
      final harness = await pumpHeraldApp(tester, initialLocation: '/index');
      // Default state is unauthenticated — no seeding needed.
      await tester.pumpAndSettle();

      // LoginPage is the redirect target; assert it rendered AND the returnTo
      // query param encodes the original protected location.
      expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
      final state = GoRouterState.of(
        tester.element(find.byKey(const ValueKey('loginSubmitButton'))),
      );
      expect(state.uri.path, '/login');
      expect(state.uri.queryParameters['returnTo'], '/index');
      expect(harness.repo.loginCalls, isEmpty);
    },
  );

  testWidgets('Authenticated + /login → redirect to /index', (tester) async {
    // Seed authenticated BEFORE pumping so the redirect fires on the first
    // frame. We build the container first via a no-op pump, flip state, then
    // re-pump at /login.
    final harness = await pumpHeraldApp(tester, initialLocation: '/index');
    harness.container.read(authStateProvider.notifier).seedAuthenticated(true);
    // Navigate to /login while authenticated — the guard bounces to /index.
    final ctx = tester.element(find.byType(Navigator).first);
    GoRouter.of(ctx).go('/login');
    await tester.pumpAndSettle();

    // /index hosts a ShellRoute with BottomNavigationBar.
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('loginSubmitButton')), findsNothing);
  });

  testWidgets(
    'Unauthenticated + each anonymous path renders without redirect',
    (tester) async {
      // /register
      await pumpHeraldApp(tester, initialLocation: '/register');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('registerSubmitButton')),
        findsOneWidget,
        reason: '/register must render while unauthenticated',
      );

      // /verify-email-pending
      await pumpHeraldApp(
        tester,
        initialLocation: '/verify-email-pending',
        initialExtra: const <String, dynamic>{'email': 'e'},
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('verifyEmailResendButton')),
        findsOneWidget,
        reason: '/verify-email-pending must render while unauthenticated',
      );

      // /totp-verify
      await pumpHeraldApp(
        tester,
        initialLocation: '/totp-verify',
        initialExtra: const <String, dynamic>{
          'tempToken': 't1',
          'secondFactors': <String>[],
        },
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('totpVerifyButton')),
        findsOneWidget,
        reason: '/totp-verify must render while unauthenticated',
      );

      // /consent
      await pumpHeraldApp(
        tester,
        initialLocation: '/consent',
        initialExtra: <String, dynamic>{
          'agreements': <AgreementView>[
            const AgreementView(agreementType: 'terms', id: 'a', title: 'A'),
          ],
          'originalFlow': <String, dynamic>{'kind': 'password'},
        },
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('consentAcceptButton')),
        findsOneWidget,
        reason: '/consent must render while unauthenticated',
      );

      // /password
      await pumpHeraldApp(
        tester,
        initialLocation: '/password',
        initialExtra: ChangePasswordType.ForgotPassword,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('passwordSubmitButton')),
        findsOneWidget,
        reason: '/password must render while unauthenticated',
      );

      // /reset-password-confirm
      await pumpHeraldApp(
        tester,
        initialLocation: '/reset-password-confirm',
        initialExtra: const <String, dynamic>{'email': 'e'},
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('resetConfirmSubmitButton')),
        findsOneWidget,
        reason: '/reset-password-confirm must render while unauthenticated',
      );
    },
  );

  testWidgets(
    'returnTo round-trip: protected route while unauthenticated bounces '
    'to /login; flipping authStateProvider to authenticated + login submit '
    'returns to the protected route',
    (tester) async {
      final harness = await pumpHeraldApp(tester, initialLocation: '/my');
      await tester.pumpAndSettle();

      // /my is protected → bounced to /login?returnTo=%2Fmy.
      expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
      final loginState = GoRouterState.of(
        tester.element(find.byKey(const ValueKey('loginSubmitButton'))),
      );
      expect(loginState.uri.queryParameters['returnTo'], '/my');

      // Seed the fake to return AuthSuccess on the next loginWithPassword call.
      harness.repo.loginWithPasswordResult = FutureOrResult.value(
        authSuccess(),
      );

      // Perform a password-tab login (the page reads returnTo and context.go's
      // there on AuthSuccess).
      await tester.enterText(
        find.byKey(const ValueKey('loginEmailField')),
        'user@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('loginPasswordField')),
        'Password1',
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('loginSubmitButton')));
      await tester.pumpAndSettle();

      // AuthSuccess flipped authStateProvider to authenticated (the notifier
      // does this), and the page read returnTo=/my → navigated there.
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byKey(const ValueKey('loginSubmitButton')), findsNothing);
      // /my is the MyPage (one of the bottom-nav tabs); the route landed there.
      final state = GoRouterState.of(
        tester.element(find.byType(BottomNavigationBar)),
      );
      expect(state.uri.path, '/my');
    },
  );

  testWidgets(
    'Mid-session authState flip to unauthenticated (refresh failure / logout '
    'path) auto-redirects to /login without an explicit navigation',
    (tester) async {
      // This is the gap the refreshListenable wiring closes: the redirect
      // guard only re-evaluates on navigation, so a state flip from
      // `onSessionEnd` (refresh failure) or `logout()` while the user is on a
      // protected route must itself bounce them to /login. Without
      // refreshListenable the user would be stuck on a protected page with no
      // valid session until they tapped somewhere.
      final harness = await pumpHeraldApp(tester, initialLocation: '/index');
      harness.container
          .read(authStateProvider.notifier)
          .seedAuthenticated(true);
      await tester.pumpAndSettle();

      // Authenticated on a protected route — index renders.
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byKey(const ValueKey('loginSubmitButton')), findsNothing);

      // Simulate the interceptor's onSessionEnd: refresh failed, session ended.
      harness.container.read(authStateProvider.notifier).markUnauthenticated();
      await tester.pumpAndSettle();

      // The redirect re-evaluated on the state flip alone — bounced to /login.
      expect(find.byKey(const ValueKey('loginSubmitButton')), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      final state = GoRouterState.of(
        tester.element(find.byKey(const ValueKey('loginSubmitButton'))),
      );
      expect(state.uri.path, '/login');
      expect(state.uri.queryParameters['returnTo'], '/index');
    },
  );
}
