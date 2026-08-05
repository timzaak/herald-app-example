// Widget-test pump helper (FL-T01, guides/flutter/testing.md pattern).
//
// Single entry point: [pumpHeraldApp]. Pumps a fresh [ProviderContainer]
// (so each test isolates state — Work §13) wrapped in [UncontrolledProviderScope],
// hosting a router built from the real `appRouter` route table + redirect
// logic. The redirect guard is rebound to read THIS test's container (not the
// production `heraldContainer` in `main.dart`), so a page's `authStateProvider`
// state-flip is visible to the guard within the same test.
//
// Why UncontrolledProviderScope + a returned container (vs ProviderScope):
// the redirect guard reads `container.read(authStateProvider)` synchronously.
// For page tests this must be the SAME container the page reads, otherwise a
// login-success state-flip in the widget scope wouldn't propagate to the guard
// and `/index` navigation would bounce back to `/login`. Exposing the
// container lets tests seed state directly for the redirect-guard cases.
//
// For the dedicated routes_redirect_guard_test, the same helper is used; it
// seeds `authStateProvider` via the returned container before / between
// assertions. No production-code change to `main.dart`'s `heraldContainer`.
import 'package:app/l10n/app_localizations.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
// Riverpod 3 does not publicly export the `Override` type (it lives in
// `package:riverpod/src/internals`); `ProviderScope.overrides` and
// `ProviderContainer(overrides:)` are typed `List<Override>`. Importing the
// internals here is the library-blessed way to type the helper's overrides
// parameter (see Riverpod 3 migration notes). `riverpod` itself is a
// transitive dep of `hooks_riverpod` (already a direct dep), so no new
// pubspec entry is warranted (Rule 2).
// ignore: depend_on_referenced_packages, invalid_use_of_internal_member
import 'package:riverpod/src/internals.dart' show Override;

import '../fakes/fake_herald_auth_repository.dart';
import '../fakes/fake_account_security_service.dart';
import '../fakes/fake_turnstile_service.dart';

/// Pumps the herald app with a fresh container hosting the real route table.
///
/// [overrides] are layered on top of the shared repository + turnstile fakes
/// (created here and returned). [initialLocation] selects the router's
/// starting route (default `/login`). [initialExtra] is forwarded to the
/// route's page builder for extra-carrying routes (/totp-verify, /consent,
/// /verify-email-pending, /reset-password-confirm, /password).
///
/// The fakes are returned so the test can drive / assert them.
Future<
  ({
    ProviderContainer container,
    FakeHeraldAuthRepository repo,
    FakeAccountSecurityService security,
    FakeTurnstileService turnstile,
  })
>
pumpHeraldApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  String initialLocation = '/login',
  Object? initialExtra,
  bool emailOtpEnabled = true,
  bool registrationEnabled = true,
}) async {
  final repo = FakeHeraldAuthRepository();
  final security = FakeAccountSecurityService();
  final turnstile = FakeTurnstileService();
  final container = ProviderContainer(
    overrides: [
      heraldAuthRepositoryProvider.overrideWithValue(repo),
      accountSecurityServiceProvider.overrideWithValue(security),
      turnstileServiceProvider.overrideWithValue(turnstile),
      emailOtpEnabledProvider.overrideWith((ref) async => emailOtpEnabled),
      registrationEnabledProvider.overrideWith(
        (ref) async => registrationEnabled,
      ),
      // Native-login buttons are hidden in widget tests by default (no real
      // public-config fetch). Tests that need them pass their own override.
      nativeLoginAvailabilityProvider.overrideWith(
        (ref) => const NativeLoginAvailability(),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _HeraldTestApp(
        container: container,
        initialLocation: initialLocation,
        initialExtra: initialExtra,
      ),
    ),
  );
  // One pump so the first frame + router resolve. Tests pump further as
  // needed (e.g. after tapping).
  await tester.pump();
  return (
    container: container,
    repo: repo,
    security: security,
    turnstile: turnstile,
  );
}

/// Inner widget hosting the router. The redirect guard is rebound to read
/// [container] (the test's own scope) instead of the production
/// `heraldContainer`. This keeps page + guard consistent within one test.
class _HeraldTestApp extends StatelessWidget {
  const _HeraldTestApp({
    required this.container,
    required this.initialLocation,
    this.initialExtra,
  });

  final ProviderContainer container;
  final String initialLocation;
  final Object? initialExtra;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HeraldTest',
      // Pages call AppLocalizations.of(context)! — register the delegates so
      // that lookup resolves. Matches MyApp's configuration in lib/main.dart.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // SmartDialog attaches its toast/loading overlay via the builder. Without
      // this, SmartDialog.showToast calls in the pages would fail to find a
      // host overlay (the pages toast on every failure / success path).
      builder: FlutterSmartDialog.init(),
      routerConfig: _routerForTest(container, initialLocation, initialExtra),
    );
  }
}

/// Anonymous-route whitelist, mirrored from `lib/routes.dart`'s private
/// `_anonymousPaths`. Kept in sync here so this test helper does not depend on
/// a private symbol from production. If the production list changes, update
/// this copy too (the redirect-guard test would otherwise drift).
const Set<String> _anonymousPaths = {
  '/login',
  '/register',
  '/verify-email-pending',
  '/totp-verify',
  '/consent',
  '/password',
  '/reset-password-confirm',
};

GoRouter _routerForTest(
  ProviderContainer container,
  String initialLocation,
  Object? initialExtra,
) {
  return GoRouter(
    initialLocation: initialLocation,
    initialExtra: initialExtra,
    // Mirror the production redirect (lib/routes.dart) but read from the
    // test's container. Same anonymous-path whitelist, same `/login`-when-
    // authenticated bounce, same `?returnTo=` encoding. The
    // `refreshListenable` mirrors production too: without it, a state flip
    // mid-session (e.g. markUnauthenticated) would not re-evaluate redirect.
    refreshListenable: _TestAuthRefreshNotifier(container),
    redirect: (BuildContext context, GoRouterState state) {
      final authed =
          container.read(authStateProvider).status == AuthStatus.authenticated;
      final location = state.matchedLocation;
      if (!authed && !_anonymousPaths.contains(location)) {
        final encoded = Uri.encodeComponent(state.uri.toString());
        return '/login?returnTo=$encoded';
      }
      if (authed && location == '/login') {
        return '/index';
      }
      return null;
    },
    routes: appRouter.configuration.routes,
  );
}

/// Test-only analogue of production `_AuthStateRouterRefreshNotifier`
/// (lib/routes.dart): bridges this test container's [authStateProvider] into
/// the test router's `refreshListenable` so a mid-session state flip
/// re-evaluates the redirect — same behavior as production, but bound to the
/// test's own container (production reads `heraldContainer`, not this one).
class _TestAuthRefreshNotifier extends ChangeNotifier {
  _TestAuthRefreshNotifier(ProviderContainer container) {
    // Mirror production: only `status` flips re-evaluate redirect. A `loading`
    // flip (e.g. during /consent's accept-replay) must not rebuild the route.
    AuthStatus? previous = container.read(authStateProvider).status;
    container.listen<AuthState>(authStateProvider, (_, next) {
      if (next.status != previous) {
        previous = next.status;
        notifyListeners();
      }
    });
  }
}

/// Pumps the test binding's fake clock long enough for a SmartDialog toast to
/// complete its full lifecycle (auto-dismiss default 2s + the 100ms interval
/// delay scheduled after dismiss), so the post-test `!timersPending`
/// invariant holds for tests that trigger a toast.
///
/// This is NOT a real-time wait: `tester.pump(Duration)` advances the test
/// binding's fake clock only (guides/flutter/testing.md "禁止真实时间等待").
/// The 25 small increments let the async continuation inside
/// `ToastTool.dismiss` fully resolve (a single large pump doesn't drain the
/// microtask chain the dismiss schedules).
Future<void> drainSmartDialogToasts(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
