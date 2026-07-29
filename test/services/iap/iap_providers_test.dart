// Embedded ProviderContainer unit tests for the IAP state layer.
// Covers the three providers + notifier happy / fail-closed /
// credential-loss paths. The full `test/fakes/fake_iap_service.dart` is the
// flutter/test slot's job; the fakes here are inline and minimal.
//
// Why fakes (not mockito): guides/flutter/testing.md prefers fakes over
// call-count-based mocking, and the item pins this. The inline
// `_FakeIapService` records `buyNonConsumable`/`buyConsumable`/`completePurchase`
// calls and exposes a `StreamController` the test pumps `purchaseStream`
// events through. `_FakeBillingService` records `submitIapReceipt` calls and
// returns the queued result (or throws the queued error).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/providers/account_providers.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:app/providers/iap_providers.dart';
import 'package:app/services/account/account_service.dart';
import 'package:app/services/auth/herald_auth_repository.dart';
import 'package:app/services/billing/billing_service.dart';
import 'package:app/services/iap/iap_models.dart';
import 'package:app/services/iap/iap_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// Riverpod 3 does not publicly export the `Override` type (it lives in
// `package:riverpod/src/internals.dart`); `ProviderContainer(overrides:)` and
// `List<Override>` need it. Mirrors test/helpers/pump_herald_app.dart.
// ignore: depend_on_referenced_packages
import 'package:riverpod/src/internals.dart' show Override;

// ---------------------------------------------------------------------------
// Inline fakes.
// ---------------------------------------------------------------------------

class _BuyNonConsumableCall {
  final ProductDetails product;
  final String userId;
  const _BuyNonConsumableCall(this.product, this.userId);
}

class _BuyConsumableCall {
  final ProductDetails product;
  final String userId;
  const _BuyConsumableCall(this.product, this.userId);
}

class _SubmitIapReceiptCall {
  final IapReceiptInput input;
  const _SubmitIapReceiptCall(this.input);
}

/// Minimal IapService fake. Records buy/complete/restore calls and exposes a
/// `StreamController` the test pumps `purchaseStream` events through.
class _FakeIapService implements IapService {
  final StreamController<List<PurchaseDetails>> _controller =
      StreamController<List<PurchaseDetails>>.broadcast();

  final List<_BuyNonConsumableCall> buyNonConsumableCalls = [];
  final List<_BuyConsumableCall> buyConsumableCalls = [];
  final List<PurchaseDetails> completePurchaseCalls = [];
  final List<void> restorePurchasesCalls = [];

  /// Set by the test to control `canBindUserId`. Defaults to always-true
  /// (Android-style string binding).
  bool Function(String userId) canBindPredicate = (_) => true;

  @override
  Future<Set<ProductDetails>> queryProducts(Set<String> storeIds) async {
    // iapProductsProvider tests override iapServiceProvider entirely, so this
    // default is only a safety net.
    return const <ProductDetails>{};
  }

  @override
  Future<void> buyNonConsumable({
    required ProductDetails product,
    required String userId,
  }) async {
    buyNonConsumableCalls.add(_BuyNonConsumableCall(product, userId));
  }

  @override
  Future<void> buyConsumable({
    required ProductDetails product,
    required String userId,
  }) async {
    buyConsumableCalls.add(_BuyConsumableCall(product, userId));
  }

  @override
  Future<void> restorePurchases() async {
    restorePurchasesCalls.add(null);
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completePurchaseCalls.add(purchase);
  }

  @override
  bool canBindUserId(String userId) => canBindPredicate(userId);

  /// Test helper: pumps an event into [purchaseStream].
  void emit(List<PurchaseDetails> purchases) {
    _controller.add(purchases);
  }

  void dispose() => _controller.close();
}

/// Minimal BillingService fake. Only [submitIapReceipt] is exercised by the
/// notifier; the other methods return benign defaults (the notifier never
/// calls them).
class _FakeBillingService implements BillingService {
  final List<_SubmitIapReceiptCall> submitCalls = [];

  /// Queued result returned by [submitIapReceipt]. When non-null, returned
  /// as-is; when null, [submitError] is thrown (if non-null); otherwise a
  /// generic succeeded result is returned.
  IapReceiptResult? submitResult;
  Object? submitError;

  @override
  Future<IapReceiptResult> submitIapReceipt(IapReceiptInput input) async {
    submitCalls.add(_SubmitIapReceiptCall(input));
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
  Future<PaymentAttempt> createPaymentAttempt(PurchaseOption option) async {
    throw UnimplementedError();
  }

  @override
  Future<PaymentAttemptStatus> getPaymentAttemptStatus(String attemptId) async {
    throw UnimplementedError();
  }
}

/// Minimal HeraldAuthRepository that only implements [currentUserId]. Other
/// methods are unreachable from the IAP provider graph; [noSuchMethod] returns
/// null/throws defensively.
class _FakeHeraldAuthRepository implements HeraldAuthRepository {
  _FakeHeraldAuthRepository(this._userId);
  final String? _userId;

  @override
  Future<String?> currentUserId() async => _userId;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

/// Minimal AccountService fake so `accountOverviewProvider` is safe to
/// invalidate / observe during the notifier's fulfillment path.
class _FakeAccountService implements AccountService {
  @override
  Future<AccountOverview> getOverview() async {
    return const AccountOverview(email: 'user@example.com', points: 0);
  }
}

// ---------------------------------------------------------------------------
// Helpers to build in_app_purchase value objects.
// ---------------------------------------------------------------------------

ProductDetails _productDetails(
  String id, {
  String title = 'T',
  String price = '\$0.99',
}) {
  return ProductDetails(
    id: id,
    title: title,
    description: 'desc',
    price: price,
    rawPrice: 0.99,
    currencyCode: 'USD',
  );
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

PurchaseOption _option({
  required String mappingId,
  required String paymentProvider,
  String? externalProductId,
  String billingType = 'one_time',
  bool alreadyOwned = false,
}) {
  return PurchaseOption(
    mappingId: mappingId,
    displayName: mappingId,
    paymentProvider: paymentProvider,
    enabled: true,
    alreadyOwned: alreadyOwned,
    billingType: billingType,
    externalProductId: externalProductId,
  );
}

IapProduct _iapProduct(PurchaseOption option, String storeId) {
  return IapProduct(option: option, storeProduct: _productDetails(storeId));
}

/// Wires the inline fakes into a fresh [ProviderContainer]. The caller owns
/// the container's lifecycle (dispose in tear-down).
({
  ProviderContainer container,
  _FakeIapService iap,
  _FakeBillingService billing,
})
_container({
  required String? userId,
  _FakeIapService? iap,
  _FakeBillingService? billing,
  List<Override> extra = const [],
}) {
  final iapFake = iap ?? _FakeIapService();
  final billingFake = billing ?? _FakeBillingService();
  final container = ProviderContainer(
    overrides: [
      iapServiceProvider.overrideWithValue(iapFake),
      billingServiceProvider.overrideWithValue(billingFake),
      heraldAuthRepositoryProvider.overrideWithValue(
        _FakeHeraldAuthRepository(userId),
      ),
      accountServiceProvider.overrideWithValue(_FakeAccountService()),
      ...extra,
    ],
  );
  return (container: container, iap: iapFake, billing: billingFake);
}

// ---------------------------------------------------------------------------
// A 4xx/5xx-capable scripted adapter (mirrors the iap_receipt_test one)
// used by the iapProductsProvider test, which exercises the real
// HeraldBillingService via a scripted dio.
// ---------------------------------------------------------------------------

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(List<Map<String, dynamic>> responses)
    : _responses = responses;

  final List<Map<String, dynamic>> _responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      _responses.isEmpty ? '{}' : jsonEncode(_responses.removeAt(0)),
      200,
      headers: const {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_ScriptedAdapter adapter) {
  return Dio(BaseOptions(baseUrl: 'https://herald.test'))
    ..httpClientAdapter = adapter;
}

void main() {
  group('iapProductsProvider', () {
    test(
      'filters to apple/google, drops stripe, skips unmatched store id',
      () async {
        // WHY: hide stripe/creem + do NOT filter on alreadyOwned
        // + mismatch risk (skip unmatched).
        // The provider must keep the alreadyOwned apple row AND the unmatched
        // externalProductId is silently skipped.
        final optionsAdapter = _ScriptedAdapter([
          {
            'items': [
              {
                'mappingId': 'map-apple-monthly',
                'displayName': 'Pro Monthly',
                'paymentProvider': 'apple',
                'enabled': true,
                'alreadyOwned': false,
                'externalProductId': 'com.example.pro.monthly',
                'billingType': 'recurring',
              },
              {
                // alreadyOwned=true MUST still be kept.
                'mappingId': 'map-google-pack',
                'displayName': '1000 points',
                'paymentProvider': 'google',
                'enabled': true,
                'alreadyOwned': true,
                'externalProductId': 'com.example.points1000',
                'billingType': 'one_time',
              },
              {
                // stripe MUST be dropped.
                'mappingId': 'map-stripe',
                'displayName': 'Stripe pack',
                'paymentProvider': 'stripe',
                'enabled': true,
                'alreadyOwned': false,
                'externalProductId': 'stripe_pack_id',
                'billingType': 'one_time',
              },
              {
                // creem MUST be dropped.
                'mappingId': 'map-creem',
                'displayName': 'Creem pack',
                'paymentProvider': 'creem',
                'enabled': true,
                'alreadyOwned': false,
                'externalProductId': 'creem_pack_id',
                'billingType': 'one_time',
              },
              {
                // apple with an externalProductId that won't match a store
                // ProductDetails — silently skipped (mismatch risk).
                'mappingId': 'map-apple-unmatched',
                'displayName': 'Legacy pack',
                'paymentProvider': 'apple',
                'enabled': true,
                'alreadyOwned': false,
                'externalProductId': 'com.example.legacy.unmatched',
                'billingType': 'one_time',
              },
            ],
          },
        ]);
        final dio = _dio(optionsAdapter);

        // The fake IapService resolves only the two matched store ids; the
        // unmatched 'com.example.legacy.unmatched' is what iapProductsProvider
        // must silently skip (no ProductDetails returned for it).
        final matchedIds = {
          'com.example.pro.monthly',
          'com.example.points1000',
        };
        final wrapped = _ScopedIapService(
          _FakeIapService(),
          queryProductsImpl: (ids) async => {
            for (final id in matchedIds) _productDetails(id),
          },
        );

        final container = ProviderContainer(
          overrides: [
            billingServiceProvider.overrideWithValue(
              HeraldBillingService(
                dio,
                realmId: 'realm-1',
                clientAppUuid: 'client-uuid',
              ),
            ),
            iapServiceProvider.overrideWithValue(wrapped),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(iapProductsProvider.future);

        expect(
          result,
          hasLength(2),
          reason:
              'apple-monthly + google-pack kept; stripe/creem dropped; unmatched skipped',
        );
        final storeIds = result.map((p) => p.storeId).toSet();
        expect(storeIds, {'com.example.pro.monthly', 'com.example.points1000'});
        // the alreadyOwned google pack is present.
        final googlePack = result.firstWhere(
          (p) => p.storeId == 'com.example.points1000',
        );
        expect(
          googlePack.option.alreadyOwned,
          isTrue,
          reason:
              'iapProductsProvider must NOT filter on alreadyOwned',
        );
        // each IapProduct carries the store ProductDetails.
        expect(googlePack.storeProduct.id, 'com.example.points1000');
        expect(googlePack.storeProduct.price, '\$0.99');
      },
    );

    test(
      'returns empty list when backend has no apple/google options',
      () async {
        final optionsAdapter = _ScriptedAdapter([
          {
            'items': [
              {
                'mappingId': 'map-stripe',
                'displayName': 'Stripe',
                'paymentProvider': 'stripe',
                'enabled': true,
                'alreadyOwned': false,
                'externalProductId': 'stripe_id',
                'billingType': 'one_time',
              },
            ],
          },
        ]);
        final dio = _dio(optionsAdapter);
        final container = ProviderContainer(
          overrides: [
            billingServiceProvider.overrideWithValue(
              HeraldBillingService(
                dio,
                realmId: 'realm-1',
                clientAppUuid: 'client-uuid',
              ),
            ),
            iapServiceProvider.overrideWithValue(
              _ScopedIapService(_FakeIapService()),
            ),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(iapProductsProvider.future);
        expect(result, isEmpty);
      },
    );
  });

  group('currentUserIdProvider', () {
    test('non-null userId is surfaced', () async {
      final harness = _container(userId: 'u-123');
      addTearDown(harness.container.dispose);

      expect(
        await harness.container.read(currentUserIdProvider.future),
        'u-123',
      );
    });

    test('null userId is surfaced (notifier will block purchase)', () async {
      final harness = _container(userId: null);
      addTearDown(harness.container.dispose);

      expect(
        await harness.container.read(currentUserIdProvider.future),
        isNull,
      );
    });
  });

  group('IapPurchaseNotifier.buy', () {
    test(
      'happy path: userId non-null + canBind → buyConsumable called; purchased '
      'event → submit → 200 succeeded → completePurchase + accountOverview '
      'invalidated + state Fulfilled',
      () async {
        final product = _iapProduct(
          _option(
            mappingId: 'mapping-uuid-1',
            paymentProvider: 'apple',
            externalProductId: 'com.example.points1000',
            billingType: 'one_time',
          ),
          'com.example.points1000',
        );
        final harness = _container(
          userId: 'u-123',
          extra: [
            iapProductsProvider.overrideWith((ref) async => [product]),
          ],
        );
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(iapPurchaseProvider.notifier);
        // Let the override resolve so the product list is available for the
        // event-time lookup in _submitAndAdvance.
        await harness.container.read(iapProductsProvider.future);

        harness.billing.submitResult = const IapReceiptResult(
          attemptId: 'attempt-1',
          status: 'succeeded',
        );

        // buy → presents sheet (buyConsumable called); state Purchasing.
        await notifier.buy(product);
        expect(harness.iap.buyConsumableCalls, hasLength(1));
        expect(
          harness.container.read(iapPurchaseProvider),
          isA<IapPurchasePurchasing>(),
        );

        // Pump a purchased event.
        harness.iap.emit([
          _purchase('com.example.points1000', status: PurchaseStatus.purchased),
        ]);
        // Let the async _submitAndAdvance microtask run.
        await Future<void>.delayed(Duration.zero);

        expect(harness.billing.submitCalls, hasLength(1));
        final input = harness.billing.submitCalls.single.input;
        expect(input.productId, 'com.example.points1000');
        expect(input.targetId, 'mapping-uuid-1');
        expect(input.targetType, 'entitlement_mapping');
        expect(input.provider, 'apple'); // source=app_store → apple
        expect(input.receipt, 'jws'); // apple → localVerificationData

        expect(
          harness.iap.completePurchaseCalls,
          hasLength(1),
          reason: 'success → completePurchase',
        );
        expect(
          harness.iap.completePurchaseCalls.single.productID,
          'com.example.points1000',
        );

        final state = harness.container.read(iapPurchaseProvider);
        expect(state, isA<IapPurchaseFulfilled>());
        expect((state as IapPurchaseFulfilled).result.status, 'succeeded');

        // accountOverviewProvider invalidated — observed by reading it once;
        // it must not throw.
        await harness.container.read(accountOverviewProvider.future);
      },
    );

    test(
      'recurring billingType → buyNonConsumable (subscription = non-consumable)',
      () async {
        final product = _iapProduct(
          _option(
            mappingId: 'mapping-recurring',
            paymentProvider: 'google',
            externalProductId: 'com.example.pro.monthly',
            billingType: 'recurring',
          ),
          'com.example.pro.monthly',
        );
        final harness = _container(userId: 'u-123');
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(iapPurchaseProvider.notifier);

        await notifier.buy(product);

        expect(harness.iap.buyNonConsumableCalls, hasLength(1));
        expect(
          harness.iap.buyNonConsumableCalls.single.product.id,
          'com.example.pro.monthly',
        );
        expect(harness.iap.buyConsumableCalls, isEmpty);
      },
    );

    test(
      'userId null → state Failed(generic); buy* NOT called (fail-closed)',
      () async {
        final product = _iapProduct(
          _option(
            mappingId: 'mapping-uuid-1',
            paymentProvider: 'apple',
            externalProductId: 'com.example.points1000',
          ),
          'com.example.points1000',
        );
        final harness = _container(userId: null);
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(iapPurchaseProvider.notifier);

        await notifier.buy(product);

        expect(harness.iap.buyConsumableCalls, isEmpty);
        expect(harness.iap.buyNonConsumableCalls, isEmpty);
        final state = harness.container.read(iapPurchaseProvider);
        expect(state, isA<IapPurchaseFailed>());
        expect((state as IapPurchaseFailed).reason, IapFailureReason.generic);
      },
    );

    test(
      'canBind false (iOS non-UUID) → state Failed(ownershipMismatch); buy* NOT called',
      () async {
        final product = _iapProduct(
          _option(
            mappingId: 'mapping-uuid-1',
            paymentProvider: 'apple',
            externalProductId: 'com.example.points1000',
          ),
          'com.example.points1000',
        );
        final harness = _container(userId: 'not-a-uuid');
        harness.iap.canBindPredicate = (_) => false; // iOS non-UUID fail-closed
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(iapPurchaseProvider.notifier);

        await notifier.buy(product);

        expect(harness.iap.buyConsumableCalls, isEmpty);
        expect(harness.iap.buyNonConsumableCalls, isEmpty);
        final state = harness.container.read(iapPurchaseProvider);
        expect(state, isA<IapPurchaseFailed>());
        expect(
          (state as IapPurchaseFailed).reason,
          IapFailureReason.ownershipMismatch,
        );
      },
    );
  });

  group('IapPurchaseNotifier credential-loss', () {
    test(
      'submitIapReceipt throws DioException (5xx) → state Failed; completePurchase '
      'NOT called; _pendingReplay retains (replayPending re-submits)',
      () async {
        final product = _iapProduct(
          _option(
            mappingId: 'mapping-uuid-1',
            paymentProvider: 'apple',
            externalProductId: 'com.example.points1000',
          ),
          'com.example.points1000',
        );
        final harness = _container(
          userId: 'u-123',
          billing: _FakeBillingService(),
          extra: [
            iapProductsProvider.overrideWith((ref) async => [product]),
          ],
        );
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(iapPurchaseProvider.notifier);
        await harness.container.read(iapProductsProvider.future);

        // First submit throws a 5xx DioException (network/5xx → retain for replay).
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 500,
          ),
        );
        harness.billing
          ..submitResult = null
          ..submitError = dioError;

        // Pump a purchased event (no buy() — direct stream, as a cold-start
        // unfinished transaction would).
        harness.iap.emit([
          _purchase('com.example.points1000', status: PurchaseStatus.purchased),
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(harness.billing.submitCalls, hasLength(1));
        expect(
          harness.iap.completePurchaseCalls,
          isEmpty,
          reason: 'NEVER completePurchase on failure — retain for replay',
        );
        final state = harness.container.read(iapPurchaseProvider);
        expect(state, isA<IapPurchaseFailed>());
        expect(
          (state as IapPurchaseFailed).reason,
          IapFailureReason.generic,
          reason: '5xx / network → generic',
        );

        // _pendingReplay retains the purchase (assert via replayPending
        // re-submitting it).
        expect(
          notifier.pendingReplayCount,
          1,
          reason: 'credential-loss retain: the purchase is held for replay',
        );

        // Now make the backend succeed and replay.
        harness.billing
          ..submitError = null
          ..submitResult = const IapReceiptResult(
            attemptId: 'attempt-1',
            status: 'succeeded',
          );
        await notifier.replayPending();
        await Future<void>.delayed(Duration.zero);

        // Re-submitted, now succeeded → completePurchase called, retained dropped.
        expect(
          harness.billing.submitCalls,
          hasLength(2),
          reason: 'replayPending re-submits the retained purchase',
        );
        expect(
          harness.iap.completePurchaseCalls,
          hasLength(1),
          reason: 'success on replay → completePurchase',
        );
        expect(notifier.pendingReplayCount, 0);
      },
    );

    test(
      '200 status=failed → state Failed(verificationFailed); completePurchase NOT '
      'called; retained',
      () async {
        final product = _iapProduct(
          _option(
            mappingId: 'mapping-uuid-1',
            paymentProvider: 'apple',
            externalProductId: 'com.example.points1000',
          ),
          'com.example.points1000',
        );
        final harness = _container(
          userId: 'u-123',
          extra: [
            iapProductsProvider.overrideWith((ref) async => [product]),
          ],
        );
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(iapPurchaseProvider.notifier);
        await harness.container.read(iapProductsProvider.future);

        harness.billing.submitResult = const IapReceiptResult(
          attemptId: 'attempt-2',
          status: 'failed',
          failureReason: 'verification_failed',
        );

        harness.iap.emit([
          _purchase('com.example.points1000', status: PurchaseStatus.purchased),
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(
          harness.iap.completePurchaseCalls,
          isEmpty,
          reason: '200-failed is a failure → retain, do NOT complete',
        );
        final state = harness.container.read(iapPurchaseProvider);
        expect(state, isA<IapPurchaseFailed>());
        expect(
          (state as IapPurchaseFailed).reason,
          IapFailureReason.verificationFailed,
        );
        expect(notifier.pendingReplayCount, 1);
      },
    );

    test(
      'PurchaseStatus.canceled → completePurchase + Idle (silent, no failure)',
      () async {
        final product = _iapProduct(
          _option(
            mappingId: 'mapping-uuid-1',
            paymentProvider: 'apple',
            externalProductId: 'com.example.points1000',
          ),
          'com.example.points1000',
        );
        final harness = _container(
          userId: 'u-123',
          extra: [
            iapProductsProvider.overrideWith((ref) async => [product]),
          ],
        );
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(iapPurchaseProvider.notifier);
        await harness.container.read(iapProductsProvider.future);

        harness.iap.emit([
          _purchase('com.example.points1000', status: PurchaseStatus.canceled),
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(harness.iap.completePurchaseCalls, hasLength(1));
        expect(
          harness.billing.submitCalls,
          isEmpty,
          reason: 'canceled → no receipt submission',
        );
        expect(
          harness.container.read(iapPurchaseProvider),
          isA<IapPurchaseIdle>(),
        );
        expect(notifier.pendingReplayCount, 0);
      },
    );

    test('PurchaseStatus.error → completePurchase + Failed(generic)', () async {
      final product = _iapProduct(
        _option(
          mappingId: 'mapping-uuid-1',
          paymentProvider: 'apple',
          externalProductId: 'com.example.points1000',
        ),
        'com.example.points1000',
      );
      final harness = _container(
        userId: 'u-123',
        extra: [
          iapProductsProvider.overrideWith((ref) async => [product]),
        ],
      );
      addTearDown(harness.container.dispose);
      // Read the notifier to trigger build() (starts the stream listener).
      harness.container.read(iapPurchaseProvider.notifier);
      await harness.container.read(iapProductsProvider.future);

      harness.iap.emit([
        _purchase('com.example.points1000', status: PurchaseStatus.error),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(harness.iap.completePurchaseCalls, hasLength(1));
      final state = harness.container.read(iapPurchaseProvider);
      expect(state, isA<IapPurchaseFailed>());
      expect((state as IapPurchaseFailed).reason, IapFailureReason.generic);
    });
  });

  group('IapPurchaseNotifier.restore', () {
    test('no restored events → lastRestoreWasEmpty true; state Idle', () async {
      final harness = _container(userId: 'u-123');
      addTearDown(harness.container.dispose);
      final notifier = harness.container.read(iapPurchaseProvider.notifier);

      await notifier.restore();

      expect(harness.iap.restorePurchasesCalls, hasLength(1));
      expect(notifier.lastRestoreWasEmpty, isTrue);
      expect(
        harness.container.read(iapPurchaseProvider),
        isA<IapPurchaseIdle>(),
      );
    });
  });
}

/// Wraps a [_FakeIapService] to allow per-test `queryProducts` overrides
/// without subclassing the whole interface.
class _ScopedIapService implements IapService {
  _ScopedIapService(this._inner, {this.queryProductsImpl});

  final _FakeIapService _inner;
  final Future<Set<ProductDetails>> Function(Set<String>)? queryProductsImpl;

  @override
  Future<Set<ProductDetails>> queryProducts(Set<String> storeIds) {
    final impl = queryProductsImpl;
    if (impl != null) return impl(storeIds);
    return _inner.queryProducts(storeIds);
  }

  @override
  Future<void> buyNonConsumable({
    required ProductDetails product,
    required String userId,
  }) => _inner.buyNonConsumable(product: product, userId: userId);

  @override
  Future<void> buyConsumable({
    required ProductDetails product,
    required String userId,
  }) => _inner.buyConsumable(product: product, userId: userId);

  @override
  Future<void> restorePurchases() => _inner.restorePurchases();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _inner.purchaseStream;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _inner.completePurchase(purchase);

  @override
  bool canBindUserId(String userId) => _inner.canBindUserId(userId);
}
