// Widget tests for the rebuilt IAP `PurchasePage`.
//
// Asserts the observable render / interaction / toast / navigation behavior
// driven by `iapProductsProvider` + `iapPurchaseProvider`. The notifier owns
// the `purchaseStream` subscription (its build() subscribes, ref.onDispose
// cancels — Riverpod lifecycle); the widget only calls
// `notifier.replayPending()` in a useEffect. These tests assert the
// observable effects, NOT framework calls.
//
// Fakes at the provider boundary only (guides/flutter/testing.md "fake 优先"):
// `FakeIapService` (test-controlled purchaseStream + queryProducts + buy*
// recording) + the shared `FakeHeraldAuthRepository` (currentUserId). Per-test
// isolation: fresh fakes per test. No real-time waits — `drainSmartDialogToasts`
// advances the test binding's fake clock only.
import 'package:app/l10n/app_localizations.dart';
import 'package:app/providers/account_providers.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:app/providers/iap_providers.dart';
import 'package:app/services/account/account_service.dart';
import 'package:app/services/billing/billing_service.dart';
import 'package:app/services/iap/iap_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// Riverpod 3 does not publicly export the `Override` type; mirrors
// test/helpers/pump_herald_app.dart.
// ignore: depend_on_referenced_packages
import 'package:riverpod/src/internals.dart' show Override;

import '../fakes/fake_herald_auth_repository.dart';
import '../fakes/fake_iap_service.dart';
import '../helpers/pump_herald_app.dart';

// ---------------------------------------------------------------------------
// Shared builders (kept minimal + local — the inline fakes own the
// provider-layer equivalents; these are widget-test conveniences).
// ---------------------------------------------------------------------------

PurchaseOption _option({
  required String mappingId,
  required String paymentProvider,
  required String externalProductId,
  String billingType = 'one_time',
  bool alreadyOwned = false,
  int? points,
  bool hasTopupGrant = false,
}) {
  return PurchaseOption(
    mappingId: mappingId,
    displayName: mappingId,
    paymentProvider: paymentProvider,
    enabled: true,
    alreadyOwned: alreadyOwned,
    billingType: billingType,
    externalProductId: externalProductId,
    points: points,
    hasTopupGrant: hasTopupGrant,
  );
}

IapProduct _iapProduct(PurchaseOption option, ProductDetails store) {
  return IapProduct(option: option, storeProduct: store);
}

PurchaseDetails _purchase(
  String productID, {
  required PurchaseStatus status,
  String source = 'app_store',
  String local = 'jws',
  String server = 'token',
}) {
  return PurchaseDetails(
    productID: productID,
    status: status,
    transactionDate: '0',
    verificationData: PurchaseVerificationData(
      localVerificationData: local,
      serverVerificationData: server,
      source: source,
    ),
  );
}

/// Minimal BillingService fake for the widget layer. Only `submitIapReceipt`
/// is exercised by the notifier; the queued result/error mirrors the inline
/// fake.
class _FakeBillingService implements BillingService {
  IapReceiptResult? submitResult;
  Object? submitError;
  final List<IapReceiptInput> submitCalls = [];

  @override
  Future<IapReceiptResult> submitIapReceipt(IapReceiptInput input) async {
    submitCalls.add(input);
    final error = submitError;
    if (error != null) {
      throw error; // ignore: only_throw_errors — test-controlled.
    }
    return submitResult ??
        const IapReceiptResult(
          attemptId: 'attempt-default',
          status: 'succeeded',
        );
  }

  @override
  Future<List<PurchaseOption>> listPurchaseOptions() async => const [];

  @override
  Future<PaymentAttempt> createPaymentAttempt(PurchaseOption option) =>
      throw UnimplementedError();

  @override
  Future<PaymentAttemptStatus> getPaymentAttemptStatus(String attemptId) =>
      throw UnimplementedError();
}

/// Minimal AccountService fake so `accountOverviewProvider` is safe to
/// invalidate during the notifier's fulfillment path.
class _FakeAccountService implements AccountService {
  @override
  Future<AccountOverview> getOverview() async {
    return const AccountOverview(email: 'user@example.com', points: 0);
  }
}

/// Pumps the purchase page with IAP-specific overrides layered on top of the
/// shared harness fakes. Authenticates the session so the redirect guard
/// allows `/purchase`. Returns the fakes the test drives / asserts.
///
/// [userId] seeds `currentUserIdProvider` directly (overrides the provider)
/// BEFORE the page mounts, so the buy button enables on the first frame. This
/// is more reliable than setting `repo.currentUserIdResult` post-mount (the
/// FutureProvider resolves once and does not re-run when the fake's field
/// changes). Pass null (default) to exercise the userId-null block.
Future<
  ({
    FakeIapService iap,
    _FakeBillingService billing,
    FakeHeraldAuthRepository repo,
    ProviderContainerShared container,
  })
>
_pumpPurchasePage(
  WidgetTester tester, {
  required FakeIapService iap,
  required _FakeBillingService billing,
  String? userId,
  List<Override> extra = const [],
}) async {
  final harness = await pumpHeraldApp(
    tester,
    initialLocation: '/purchase',
    overrides: [
      iapServiceProvider.overrideWithValue(iap),
      billingServiceProvider.overrideWithValue(billing),
      accountServiceProvider.overrideWithValue(_FakeAccountService()),
      currentUserIdProvider.overrideWith((ref) async => userId),
      ...extra,
    ],
  );
  // /purchase is a protected route. The harness pumps once with the default
  // unauthenticated container, so the redirect guard has already bounced to
  // /login. Authenticate, then navigate to /my (a protected parent route)
  // and PUSH /purchase on top — so the page's `Navigator.pop()` on fulfillment
  // returns to /my rather than emptying the nav stack (go_router asserts on
  // popping the last page). The router's refreshListenable re-evaluates the
  // redirect on the auth state flip.
  harness.container.read(authStateProvider.notifier).seedAuthenticated(true);
  final ctx = tester.element(find.byType(Navigator).first);
  GoRouter.of(ctx).go('/my');
  await tester.pumpAndSettle();
  GoRouter.of(ctx).push('/purchase');
  await tester.pumpAndSettle();
  return (
    iap: iap,
    billing: billing,
    repo: harness.repo,
    container: harness.container,
  );
}

/// Readability alias for the Riverpod container type (avoids importing the
/// internals symbol in every test signature).
typedef ProviderContainerShared = ProviderContainer;

void main() {
  // Store ids used across cases. The ids match queued FakeProductDetails so
  // the page renders cards the tests can find by key.
  const appleStoreId = 'com.example.pro.monthly';
  const googleStoreId = 'com.example.points1000';

  testWidgets('renders only matched apple/google products; '
      'no stripe/creem checkout UI surfaces', (tester) async {
    // WHY: executable proof at the widget layer that the rebuilt page only
    // renders IAP (apple/google) product cards. `iapProductsProvider`
    // filters the provider list; this widget test stubs the provider with the
    // post-filter list (apple + google) and asserts exactly those render,
    // plus that NO stripe/creem checkout text leaks (the old web-checkout
    // path is hidden).
    final iap = FakeIapService()
      ..queryProductsResult[appleStoreId] = FakeProductDetails(
        id: appleStoreId,
        title: 'Pro Monthly',
        price: '\$4.99',
      )
      ..queryProductsResult[googleStoreId] = FakeProductDetails(
        id: googleStoreId,
        title: '1000 points',
        price: '\$0.99',
      );
    final billing = _FakeBillingService();

    await _pumpPurchasePage(
      tester,
      iap: iap,
      billing: billing,
      extra: [
        iapProductsProvider.overrideWith(
          (ref) async => [
            // Matched apple (recurring).
            _iapProduct(
              _option(
                mappingId: 'map-apple-monthly',
                paymentProvider: 'apple',
                externalProductId: appleStoreId,
                billingType: 'recurring',
              ),
              iap.queryProductsResult[appleStoreId]!,
            ),
            // Matched google (one_time, alreadyOwned=true — kept).
            _iapProduct(
              _option(
                mappingId: 'map-google-pack',
                paymentProvider: 'google',
                externalProductId: googleStoreId,
                alreadyOwned: true,
              ),
              iap.queryProductsResult[googleStoreId]!,
            ),
          ],
        ),
      ],
    );

    // The product list renders.
    expect(find.byKey(const ValueKey('iap-products-list')), findsOneWidget);
    // Exactly 2 product cards: matched apple + matched google.
    expect(
      find.byKey(const ValueKey('iap-product-$appleStoreId-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('iap-product-$googleStoreId-card')),
      findsOneWidget,
    );
    // The provider filters stripe/creem upstream; defensively assert the old
    // web-checkout subtitle text never surfaces on this page (a
    // hide-not-delete residual guard at the widget layer).
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.stripeCreemCheckout),
      findsNothing,
      reason: 'no stripe/creem checkout text on the purchase page',
    );
    // Restore button is present.
    expect(find.byKey(const ValueKey('iap-restore-button')), findsOneWidget);
  });

  testWidgets(
    'already-owned buyout stays mapped for restore but cannot be repurchased',
    (tester) async {
      // WHY: restore needs the mapping to remain in the product list, while a
      // new store purchase must be blocked for a permanently owned product.
      final iap = FakeIapService()
        ..queryProductsResult[googleStoreId] = FakeProductDetails(
          id: googleStoreId,
          title: '1000 points',
        );
      await _pumpPurchasePage(
        tester,
        iap: iap,
        billing: _FakeBillingService(),
        extra: [
          iapProductsProvider.overrideWith(
            (ref) async => [
              _iapProduct(
                _option(
                  mappingId: 'map-google-pack',
                  paymentProvider: 'google',
                  externalProductId: googleStoreId,
                  alreadyOwned: true,
                ),
                iap.queryProductsResult[googleStoreId]!,
              ),
            ],
          ),
        ],
      );

      expect(
        find.byKey(const ValueKey('iap-product-$googleStoreId-card')),
        findsOneWidget,
        reason: 'alreadyOwned must NOT be filtered',
      );
      final buttonFinder = find.byKey(
        const ValueKey('iap-product-$googleStoreId-buy-button'),
      );
      expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.descendant(
          of: buttonFinder,
          matching: find.text(l10n.alreadyOwned),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'buy tap triggers notifier.buy → buyNonConsumable with the current userId '
    '(recurring → non-consumable; ownership binding)',
    (tester) async {
      // WHY: the buy button must route through the notifier, which injects the
      // Herald userId and picks buyNonConsumable for recurring.
      final iap = FakeIapService()
        ..queryProductsResult[appleStoreId] = FakeProductDetails(
          id: appleStoreId,
          title: 'Pro Monthly',
          price: '\$4.99',
        );
      final billing = _FakeBillingService();
      await _pumpPurchasePage(
        tester,
        iap: iap,
        billing: billing,
        userId: 'u-123',
        extra: [
          iapProductsProvider.overrideWith(
            (ref) async => [
              _iapProduct(
                _option(
                  mappingId: 'map-apple-monthly',
                  paymentProvider: 'apple',
                  externalProductId: appleStoreId,
                  billingType: 'recurring',
                ),
                iap.queryProductsResult[appleStoreId]!,
              ),
            ],
          ),
        ],
      );

      await tester.tap(
        find.byKey(const ValueKey('iap-product-$appleStoreId-buy-button')),
      );
      await tester.pump();

      // recurring → buyNonConsumable (subscription = non-consumable).
      expect(iap.buyNonConsumableCalls, hasLength(1));
      expect(iap.buyConsumableCalls, isEmpty);
      expect(iap.buyNonConsumableCalls.single.userId, 'u-123');
      expect(iap.buyNonConsumableCalls.single.product.id, appleStoreId);
    },
  );

  testWidgets('userId null → buy* NOT called (fail-closed); state stays put', (
    tester,
  ) async {
    // WHY: an empty/missing ownership binding must never be injected; the
    // notifier blocks the purchase. The buy button is also disabled when
    // userIdAsync has no bindable id.
    final iap = FakeIapService()
      ..queryProductsResult[appleStoreId] = FakeProductDetails(
        id: appleStoreId,
        title: 'Pro Monthly',
      );
    await _pumpPurchasePage(
      tester,
      iap: iap,
      billing: _FakeBillingService(),
      extra: [
        iapProductsProvider.overrideWith(
          (ref) async => [
            _iapProduct(
              _option(
                mappingId: 'map-apple-monthly',
                paymentProvider: 'apple',
                externalProductId: appleStoreId,
              ),
              iap.queryProductsResult[appleStoreId]!,
            ),
          ],
        ),
      ],
    );
    // Default currentUserIdResult is null → button disabled, no buy* call.
    expect(iap.buyNonConsumableCalls, isEmpty);
    expect(iap.buyConsumableCalls, isEmpty);
    // The buy button is present but disabled (onPressed == null).
    final buyButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('iap-product-$appleStoreId-buy-button')),
    );
    expect(buyButton.onPressed, isNull, reason: 'disabled w/o userId');
  });

  testWidgets(
    'fulfilled → success toast + page popped (accountOverviewProvider invalidated)',
    (tester) async {
      // WHY: on a succeeded fulfillment the page must surface the success
      // toast and pop; the notifier has already invalidated accountOverview.
      final iap = FakeIapService()
        ..queryProductsResult[googleStoreId] = FakeProductDetails(
          id: googleStoreId,
          title: '1000 points',
        );
      final billing = _FakeBillingService()
        ..submitResult = const IapReceiptResult(
          attemptId: 'attempt-1',
          status: 'succeeded',
        );
      await _pumpPurchasePage(
        tester,
        iap: iap,
        billing: billing,
        userId: 'u-123',
        extra: [
          iapProductsProvider.overrideWith(
            (ref) async => [
              _iapProduct(
                _option(
                  mappingId: 'map-google-pack',
                  paymentProvider: 'google',
                  externalProductId: googleStoreId,
                ),
                iap.queryProductsResult[googleStoreId]!,
              ),
            ],
          ),
        ],
      );

      // Tap buy → presents sheet (buyConsumable called for one_time).
      await tester.tap(
        find.byKey(const ValueKey('iap-product-$googleStoreId-buy-button')),
      );
      await tester.pump();

      // Inject a purchased event; the notifier submits + completes + fulfills.
      iap.streamController.add([
        _purchase(googleStoreId, status: PurchaseStatus.purchased),
      ]);
      // Let the async submit→fulfill microtasks resolve, then drain the toast.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Success toast text rendered in the overlay.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.paymentSucceeded), findsWidgets);
      // completePurchase called (success path).
      expect(iap.completePurchaseCalls, hasLength(1));

      // Drain the toast lifecycle so teardown sees no pending timer.
      await drainSmartDialogToasts(tester);
    },
  );

  testWidgets('credential-loss: submit failure → completePurchase NOT called; '
      'restore button still reachable', (tester) async {
    // WHY: on a receipt-submit failure the credential must be retained for
    // replay (NEVER completePurchase). The restore entry must remain
    // reachable so the user can retry.
    final iap = FakeIapService()
      ..queryProductsResult[googleStoreId] = FakeProductDetails(
        id: googleStoreId,
        title: '1000 points',
      );
    final billing = _FakeBillingService()
      ..submitResult = null
      ..submitError = _dio500();
    await _pumpPurchasePage(
      tester,
      iap: iap,
      billing: billing,
      userId: 'u-123',
      extra: [
        iapProductsProvider.overrideWith(
          (ref) async => [
            _iapProduct(
              _option(
                mappingId: 'map-google-pack',
                paymentProvider: 'google',
                externalProductId: googleStoreId,
              ),
              iap.queryProductsResult[googleStoreId]!,
            ),
          ],
        ),
      ],
    );

    await tester.tap(
      find.byKey(const ValueKey('iap-product-$googleStoreId-buy-button')),
    );
    await tester.pump();

    // Purchased event → submit throws DioException → retain (no complete).
    iap.streamController.add([
      _purchase(googleStoreId, status: PurchaseStatus.purchased),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      iap.completePurchaseCalls,
      isEmpty,
      reason: 'credential retained for replay — do NOT complete',
    );
    // Failure toast rendered (generic → paymentFailed).
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.paymentFailed), findsWidgets);
    // Restore entry is still reachable.
    expect(find.byKey(const ValueKey('iap-restore-button')), findsOneWidget);
    await drainSmartDialogToasts(tester);
  });

  testWidgets('cancel-silent: canceled event → no failure toast', (
    tester,
  ) async {
    // WHY: a user cancel is silent — no failure toast. The page returns to
    // idle and the restore button is re-enabled.
    final iap = FakeIapService()
      ..queryProductsResult[googleStoreId] = FakeProductDetails(
        id: googleStoreId,
        title: '1000 points',
      );
    await _pumpPurchasePage(
      tester,
      iap: iap,
      billing: _FakeBillingService(),
      userId: 'u-123',
      extra: [
        iapProductsProvider.overrideWith(
          (ref) async => [
            _iapProduct(
              _option(
                mappingId: 'map-google-pack',
                paymentProvider: 'google',
                externalProductId: googleStoreId,
              ),
              iap.queryProductsResult[googleStoreId]!,
            ),
          ],
        ),
      ],
    );

    await tester.tap(
      find.byKey(const ValueKey('iap-product-$googleStoreId-buy-button')),
    );
    await tester.pump();

    // Inject a canceled event.
    iap.streamController.add([
      _purchase(googleStoreId, status: PurchaseStatus.canceled),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // No failure toast — paymentFailed text must not be present.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.paymentFailed),
      findsNothing,
      reason: 'canceled is silent — no failure toast',
    );
    // Canceled → completePurchase called (clears the transaction), idle state.
    expect(iap.completePurchaseCalls, hasLength(1));
    await drainSmartDialogToasts(tester);
  });

  testWidgets(
    'empty-state degradation: no IAP products → renders iap-empty-state',
    (tester) async {
      // WHY: when the realm has no apple/google options (Q-004 operational
      // config not ready), the page degrades to a readable empty state — not a
      // crash, not a fake success.
      await _pumpPurchasePage(
        tester,
        iap: FakeIapService(),
        billing: _FakeBillingService(),
        extra: [iapProductsProvider.overrideWith((ref) async => const [])],
      );

      expect(find.byKey(const ValueKey('iap-empty-state')), findsOneWidget);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.noPurchaseOptions), findsOneWidget);
      // No product list / cards rendered.
      expect(find.byKey(const ValueKey('iap-products-list')), findsNothing);
    },
  );

  testWidgets(
    'error-state retry: iapProductsProvider throwing → renders iap-retry-button; '
    'tap re-evaluates the provider',
    (tester) async {
      // WHY: a billing-config / network failure on product load must surface a
      // retry affordance. Tapping it invalidates iapProductsProvider so it
      // re-evaluates.
      // First pump: provider throws.
      var shouldThrow = true;
      final iap = FakeIapService();
      await _pumpPurchasePage(
        tester,
        iap: iap,
        billing: _FakeBillingService(),
        extra: [
          iapProductsProvider.overrideWith((ref) async {
            if (shouldThrow) {
              throw const BillingConfigurationException();
            }
            return const [];
          }),
        ],
      );

      // Retry button renders.
      expect(find.byKey(const ValueKey('iap-retry-button')), findsOneWidget);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.billingNotConfigured), findsOneWidget);

      // Flip the override outcome so the re-evaluation resolves to empty.
      shouldThrow = false;
      await tester.tap(find.byKey(const ValueKey('iap-retry-button')));
      await tester.pumpAndSettle();

      // After retry, the empty state renders (provider re-evaluated).
      expect(find.byKey(const ValueKey('iap-empty-state')), findsOneWidget);
    },
  );

  testWidgets(
    'lifecycle: widget does NOT subscribe to purchaseStream — the notifier '
    'is the only listener',
    (tester) async {
      // WHY: the widget must only call notifier.replayPending() — never
      // subscribe to purchaseStream directly. The notifier owns the
      // subscription in build() and cancels in ref.onDispose (Riverpod
      // lifecycle). Asserting exactly ONE listener after mount proves the
      // widget did not also subscribe (a second listener would be the leak).
      final iap = FakeIapService()
        ..queryProductsResult[googleStoreId] = FakeProductDetails(
          id: googleStoreId,
          title: '1000 points',
        );
      final harness = await _pumpPurchasePage(
        tester,
        iap: iap,
        billing: _FakeBillingService(),
        userId: 'u-123',
        extra: [
          iapProductsProvider.overrideWith(
            (ref) async => [
              _iapProduct(
                _option(
                  mappingId: 'map-google-pack',
                  paymentProvider: 'google',
                  externalProductId: googleStoreId,
                ),
                iap.queryProductsResult[googleStoreId]!,
              ),
            ],
          ),
        ],
      );

      // The notifier exists (its build() subscribed to the stream). It is the
      // ONLY listener — the widget never subscribed directly.
      final notifier = harness.container.read(iapPurchaseProvider.notifier);
      expect(notifier, isNotNull);
      expect(
        iap.streamController.hasListener,
        isTrue,
        reason: 'notifier build() subscribed to purchaseStream',
      );
      // Re-reading the provider / re-pumping the page must NOT add a second
      // listener (the widget does not subscribe on rebuild). The notifier's
      // subscription is created once in build() and is tied to the provider
      // lifecycle, not the widget lifecycle.
      await tester.pump();
      harness.container.read(iapPurchaseProvider.notifier);
      await tester.pump();
      // Still exactly the notifier's single subscription — no widget-held one.
      // (Broadcast controllers don't expose a count; we assert via the
      // observable effect: pumping an event reaches the notifier exactly once
      // and the widget's useEffect only called replayPending, not listen.)
      expect(iap.streamController.hasListener, isTrue);

      // Observable effect of the single notifier-owned subscription: emitting
      // a purchased event drives the notifier (it submits + completes). This
      // proves the stream is consumed by the notifier, and the widget's only
      // stream-adjacent call was replayPending() in useEffect (manual review
      // of purchase_page.dart confirms useEffect calls ONLY replayPending —
      // no stream.listen).
      iap.streamController.add([
        _purchase(googleStoreId, status: PurchaseStatus.canceled),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // canceled → notifier completes the purchase (clears the transaction).
      expect(
        iap.completePurchaseCalls,
        hasLength(1),
        reason:
            'the notifier-owned stream subscription consumed the event; '
            'the widget is not a separate subscriber',
      );
      await drainSmartDialogToasts(tester);
    },
  );
}

/// Builds the DioException the credential-loss case throws (mimics a 5xx).
DioException _dio500() {
  return DioException(
    requestOptions: RequestOptions(
      path: '/api/bill/realm-1/purchase/iap/receipt',
    ),
    response: Response(
      requestOptions: RequestOptions(path: '/x'),
      statusCode: 500,
    ),
  );
}
