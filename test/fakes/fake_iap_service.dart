// Hand-rolled fake of [IapService] for the IAP widget + service unit tests
// (guides/flutter/testing.md "fake 优先").
//
// Why a hand-rolled fake (not mockito): guides/flutter/testing.md prefers
// fakes over call-count-based mocking for stable, intent-revealing tests, and
// the item pins this ("fake 优先"). This fake records every call's args
// into exposed `*Calls` lists and returns queued `*Result` values set by the
// test. It is the ONLY fake point at the widget layer — the `in_app_purchase`
// plugin is never mocked at the widget layer (that is the iap_service unit
// test's job, via a constructor-injected double).
//
// Contract honored (the frozen [IapService] surface):
// - `queryProducts(Set<String>)` returns the products queued via
//   [queryProductsResult] (keyed by store id). Unmatched ids are silently
//   absent from the returned set (`iapProductsProvider` skips them).
// - `buyNonConsumable` / `buyConsumable` record `{product, userId}` and return
//   a completed future. The system purchase sheet is platform behavior — this
//   fake does NOT open it. The test injects the `purchased` / `canceled` /
//   `error` event via [streamController].
// - `restorePurchases` records the call; the test injects `restored` events
//   via [streamController].
// - `completePurchase` records the purchase.
// - `canBindUserId` returns [canBindResult] (default true) so the
//   iOS-non-UUID fail-closed path can be exercised.
//
// Lifecycle: the [streamController] is a broadcast controller created in the
// constructor and exposed for the test to `add` events. [dispose] closes it;
// tests SHOULD call it in tearDown (or rely on `addTearDown`).
import 'dart:async';

import 'package:app/services/iap/iap_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Single recorded call to `buyNonConsumable` / `buyConsumable`.
class IapBuyCall {
  final ProductDetails product;
  final String userId;
  const IapBuyCall({required this.product, required this.userId});
}

/// A [ProductDetails] subclass with settable fields, for `queryProducts` and
/// widget rendering. The base [ProductDetails] constructor requires several
/// fields; this subclass just re-exposes them as settable named constructor
/// params with sensible defaults.
class FakeProductDetails extends ProductDetails {
  FakeProductDetails({
    required super.id,
    super.title = '',
    super.description = '',
    super.price = '',
    super.rawPrice = 0,
    super.currencyCode = 'USD',
    super.currencySymbol = '',
  });
}

/// Hand-rolled [IapService] fake. See file doc.
///
/// Per-test isolation: create a fresh instance per test in `setUp`
/// (or inline). Do NOT share mutable fake state across tests — the
/// `*Calls` lists and `streamController` accumulate.
class FakeIapService implements IapService {
  FakeIapService();

  /// Test-controlled broadcast stream of purchase events. Tests `add` lists
  /// of [PurchaseDetails] to drive the notifier's stream listener.
  ///
  /// Broadcast so multiple listeners (the notifier's `build()` subscription,
  /// plus any test-only assertions) can coexist without state loss.
  final StreamController<List<PurchaseDetails>> streamController =
      StreamController<List<PurchaseDetails>>.broadcast();

  // ---- Argument-recording lists (test assertions read these). ----
  final List<IapBuyCall> buyNonConsumableCalls = [];
  final List<IapBuyCall> buyConsumableCalls = [];
  final List<PurchaseDetails> completePurchaseCalls = [];
  final List<void> restorePurchasesCalls = [];

  // ---- Queued return values (test sets these before pumping/tapping). ----

  /// Products returned by `queryProducts`, keyed by store id. The fake returns
  /// `queryProductsResult.values.toSet()`. Tests seed this with
  /// [FakeProductDetails] instances whose `id` matches the backend
  /// `externalProductId` they want matched (and omit ids they want skipped).
  final Map<String, ProductDetails> queryProductsResult = {};

  /// Result returned by [canBindUserId]. Defaults to
  /// true (Android-style string binding always succeeds). Set to false to
  /// exercise the iOS non-UUID fail-closed path.
  bool canBindResult = true;

  // ---- IapService implementation ----

  @override
  Future<Set<ProductDetails>> queryProducts(Set<String> storeIds) async {
    // Return only the queued products whose id was requested. The
    // `iapProductsProvider` merges and skips unmatched backend options, so
    // an id absent here surfaces as "skipped" upstream — matching the
    // mismatch risk row.
    return {
      for (final id in storeIds)
        if (queryProductsResult.containsKey(id)) queryProductsResult[id]!,
    };
  }

  @override
  Future<void> buyNonConsumable({
    required ProductDetails product,
    required String userId,
  }) async {
    buyNonConsumableCalls.add(IapBuyCall(product: product, userId: userId));
  }

  @override
  Future<void> buyConsumable({
    required ProductDetails product,
    required String userId,
  }) async {
    buyConsumableCalls.add(IapBuyCall(product: product, userId: userId));
  }

  @override
  Future<void> restorePurchases() async {
    restorePurchasesCalls.add(null);
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => streamController.stream;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completePurchaseCalls.add(purchase);
  }

  @override
  bool canBindUserId(String userId) => canBindResult;

  /// Closes the [streamController]. Tests should call this in tearDown so the
  /// post-test `!timersPending` invariant holds.
  void dispose() {
    streamController.close();
  }
}
