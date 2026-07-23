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
    FakeTurnstileService turnstile,
  })
>
pumpHeraldApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  String initialLocation = '/login',
  Object? initialExtra,
}) async {
  final repo = FakeHeraldAuthRepository();
  final turnstile = FakeTurnstileService();
  final container = ProviderContainer(
    overrides: [
      heraldAuthRepositoryProvider.overrideWithValue(repo),
      turnstileServiceProvider.overrideWithValue(turnstile),
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
  return (container: container, repo: repo, turnstile: turnstile);
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
    // authenticated bounce, same `?returnTo=` encoding.
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
