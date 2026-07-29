// Unit tests for InAppPurchaseIapService.
//
// The service only FORWARDS to the `in_app_purchase` plugin instance injected
// at construction (the frozen constructor
// `InAppPurchaseIapService(InAppPurchase, IapOwnershipBinding)`). The
// success-only `completePurchase` timing logic lives in `IapPurchaseNotifier`
// (covered by iap_providers_test.dart) — NOT here. This test asserts:
//   - ownership injection: the validated `userId` is carried as
//     `PurchaseParam.applicationUserName` (the iOS appAccountToken carrier
//     path);
//   - `canBindUserId` delegates to the binding;
//   - `buyNonConsumable`/`buyConsumable` delegate with the right
//     `autoConsume` default for consumables;
//   - `queryProducts` returns the matched set + surfaces notFoundIDs to the
//     log (no throw);
//   - `purchaseStream` wires to the plugin's stream;
//   - `completePurchase` / `restorePurchases` delegate (forwarding only);
//   - the `platformProviderOf` / `receiptOf` helpers.
//
// Approach: a constructor-injected test double `implements InAppPurchase`
// (the plugin's `InAppPurchase` is a concrete class with a private ctor — it
// cannot be subclassed, but `implements` works since all members are
// implicit). Platform-specific ownership binding is exercised via two
// hand-written `IapOwnershipBinding` subclasses (Apple-UUID-validate vs
// Google-string), NOT by mocking `dart:io Platform` — that keeps the test
// deterministic and free of platform-channel mocks.
import 'dart:async';

import 'package:app/services/iap/iap_models.dart';
import 'package:app/services/iap/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// `InAppPurchasePlatformAddition` is not re-exported by `in_app_purchase`;
// import the platform interface directly to type the unused
// `getPlatformAddition` override. It is a transitive dep of `in_app_purchase`
// (already a direct dep), so no new pubspec entry is warranted (mirrors the
// Riverpod-internals import convention in test/helpers/pump_herald_app.dart).
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Fake InAppPurchase (constructor-injected test double).
// ---------------------------------------------------------------------------

/// Recorded `buyNonConsumable` / `buyConsumable` call.
class _BuyCall {
  final PurchaseParam purchaseParam;
  final bool autoConsume;
  const _BuyCall({required this.purchaseParam, required this.autoConsume});
}

/// Constructor-injected test double that `implements InAppPurchase`. Records
/// the calls the service forwards and exposes a test-controlled
/// `purchaseStream` + `queryProductDetails` result.
///
/// `InAppPurchase` is a concrete class (private ctor) so it cannot be
/// extended; `implements` re-declares the public surface. Only the members
/// the service exercises are stubbed; the rest throw `UnimplementedError` so
/// an accidental new dependency surfaces loudly.
class _FakeInAppPurchase implements InAppPurchase {
  final List<_BuyCall> buyNonConsumableCalls = [];
  final List<_BuyCall> buyConsumableCalls = [];
  final List<PurchaseDetails> completePurchaseCalls = [];
  final List<String> restorePurchasesCalls = [];

  /// Test-controlled purchase-event stream (broadcast so the test can add
  /// after the listener subscribes).
  final StreamController<List<PurchaseDetails>> purchaseStreamController =
      StreamController<List<PurchaseDetails>>.broadcast();

  /// Products returned by `queryProductDetails`, keyed by store id. notFoundIDs
  /// is computed as the requested ids absent from this map.
  final Map<String, ProductDetails> productDetails = {};

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      purchaseStreamController.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) {
    final matched = <ProductDetails>[];
    final notFound = <String>[];
    for (final id in identifiers) {
      final p = productDetails[id];
      if (p != null) {
        matched.add(p);
      } else {
        notFound.add(id);
      }
    }
    return Future.value(
      ProductDetailsResponse(productDetails: matched, notFoundIDs: notFound),
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyNonConsumableCalls.add(
      _BuyCall(purchaseParam: purchaseParam, autoConsume: false),
    );
    return true;
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    buyConsumableCalls.add(
      _BuyCall(purchaseParam: purchaseParam, autoConsume: autoConsume),
    );
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completePurchaseCalls.add(purchase);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restorePurchasesCalls.add(applicationUserName ?? '');
  }

  // ---- Unused by the service; stubbed defensively. ----
  @override
  Future<String> countryCode() => throw UnimplementedError();

  @override
  T getPlatformAddition<T extends InAppPurchasePlatformAddition?>() =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Hand-written IapOwnershipBinding subclasses (platform isolation).
// ---------------------------------------------------------------------------

/// Apple-style binding: `canBind` validates the userId is a UUID (StoreKit
/// requires `appAccountToken` to be a UUID). Mirrors the
/// `PlatformIapOwnershipBinding` iOS branch.
class _AppleOwnershipBinding implements IapOwnershipBinding {
  const _AppleOwnershipBinding();

  @override
  bool canBind(String userId) => Uuid.isValidUUID(fromString: userId);
}

/// Google-style binding: `canBind` accepts any non-empty string (Play Billing
/// `obfuscatedExternalAccountId` is a plain string). Mirrors the
/// `PlatformIapOwnershipBinding` Android branch.
class _GoogleOwnershipBinding implements IapOwnershipBinding {
  const _GoogleOwnershipBinding();

  @override
  bool canBind(String userId) => userId.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

ProductDetails _product(String id) {
  return ProductDetails(
    id: id,
    title: 'T',
    description: 'desc',
    price: '\$0.99',
    rawPrice: 0.99,
    currencyCode: 'USD',
  );
}

PurchaseDetails _purchase(
  String productID, {
  String source = 'app_store',
  String local = 'jws',
  String server = 'token',
}) {
  return PurchaseDetails(
    productID: productID,
    status: PurchaseStatus.purchased,
    transactionDate: '0',
    verificationData: PurchaseVerificationData(
      localVerificationData: local,
      serverVerificationData: server,
      source: source,
    ),
  );
}

void main() {
  // A stable Apple-style v4 UUID userId (ownership binding). Must
  // satisfy uuid's strictRFC9562 validator (version nibble 4, variant 8-b) —
  // `PlatformIapOwnershipBinding.canBind` uses the default strict mode.
  const appleUserId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

  group('ownership injection', () {
    test(
      'Apple UUID path: canBind true for a UUID; buyNonConsumable carries the '
      'binding as PurchaseParam.applicationUserName',
      () async {
        // WHY: on iOS the Herald userId MUST be a valid UUID — StoreKit
        // rejects a non-UUID appAccountToken and the backend's UUID compare
        // would mismatch. The service injects the validated `userId` into
        // applicationUserName (the iOS appAccountToken carrier path).
        final fake = _FakeInAppPurchase();
        final service = InAppPurchaseIapService(
          fake,
          const _AppleOwnershipBinding(),
        );
        final product = _product('com.example.pro.monthly');

        expect(service.canBindUserId(appleUserId), isTrue);
        expect(service.canBindUserId('not-a-uuid'), isFalse);
        expect(service.canBindUserId(''), isFalse);

        await service.buyNonConsumable(product: product, userId: appleUserId);

        expect(fake.buyNonConsumableCalls, hasLength(1));
        final param = fake.buyNonConsumableCalls.single.purchaseParam;
        expect(param.productDetails, same(product));
        expect(
          param.applicationUserName,
          appleUserId,
          reason:
              'iOS appAccountToken carrier path: the validated UUID is '
              'injected as applicationUserName',
        );
      },
    );

    test(
      'Google string path: canBind true for non-empty; buyConsumable carries '
      'the raw string + autoConsume defaults to true',
      () async {
        // WHY: on Android the Herald userId is injected verbatim as the
        // obfuscatedExternalAccountId (plain string compare). Consumables
        // default to autoConsume=true (matches the points-pack replay
        // contract).
        final fake = _FakeInAppPurchase();
        final service = InAppPurchaseIapService(
          fake,
          const _GoogleOwnershipBinding(),
        );
        final product = _product('com.example.points1000');

        expect(service.canBindUserId('u-123'), isTrue);
        expect(
          service.canBindUserId(''),
          isFalse,
          reason: 'empty userId fails',
        );

        await service.buyConsumable(product: product, userId: 'u-123');

        expect(fake.buyConsumableCalls, hasLength(1));
        final call = fake.buyConsumableCalls.single;
        expect(call.purchaseParam.productDetails, same(product));
        expect(
          call.purchaseParam.applicationUserName,
          'u-123',
          reason:
              'Google obfuscatedExternalAccountId path: the raw userId '
              'string is injected as applicationUserName',
        );
        expect(
          call.autoConsume,
          isTrue,
          reason: 'consumable autoConsume defaults to true',
        );
      },
    );

    test(
      'canBind false → buy* throws IapOwnershipBindingException (fail-closed '
      'backstop; notifier blocks upstream)',
      () async {
        // WHY: the service's `_purchaseParam` asserts canBind before injecting
        // — a defensive backstop so an invalid binding never reaches StoreKit
        // / Play (the notifier must already block).
        final fake = _FakeInAppPurchase();
        final service = InAppPurchaseIapService(
          fake,
          const _AppleOwnershipBinding(),
        );
        final product = _product('com.example.pro.monthly');

        expect(
          () => service.buyNonConsumable(product: product, userId: 'bad'),
          throwsA(isA<IapOwnershipBindingException>()),
        );
        expect(fake.buyNonConsumableCalls, isEmpty);
      },
    );
  });

  group('queryProducts', () {
    test(
      'returns the matched set; unmatched ids are logged (no throw)',
      () async {
        // WHY: the service surfaces `notFoundIDs` via debugPrint and returns the
        // matched set; iapProductsProvider skips unmatched backend options.
        final fake = _FakeInAppPurchase()
          ..productDetails['com.example.a'] = _product('com.example.a')
          ..productDetails['com.example.b'] = _product('com.example.b');
        final service = InAppPurchaseIapService(
          fake,
          const _GoogleOwnershipBinding(),
        );

        final result = await service.queryProducts({
          'com.example.a',
          'com.example.missing',
        });

        expect(result, hasLength(1));
        expect(result.single.id, 'com.example.a');
      },
    );
  });

  group('purchaseStream wiring', () {
    test('service.purchaseStream forwards the plugin stream', () async {
      // WHY: the notifier subscribes to service.purchaseStream; it MUST wire to
      // the underlying plugin stream (cold-start / restore events flow here).
      final fake = _FakeInAppPurchase();
      final service = InAppPurchaseIapService(
        fake,
        const _GoogleOwnershipBinding(),
      );

      final received = <List<PurchaseDetails>>[];
      final sub = service.purchaseStream.listen(received.add);
      addTearDown(sub.cancel);

      fake.purchaseStreamController.add([_purchase('com.example.points1000')]);
      // Broadcast stream delivers synchronously on add; pump one microtask.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.single.productID, 'com.example.points1000');
    });
  });

  group('completePurchase + restorePurchases delegation', () {
    test('completePurchase forwards to the plugin (no submit-result gating '
        'here — that lives in the notifier)', () async {
      // WHY: the service is a thin forwarder; the success-only timing logic is
      // in IapPurchaseNotifier (covered by iap_providers_test.dart). This test
      // only asserts delegation.
      final fake = _FakeInAppPurchase();
      final service = InAppPurchaseIapService(
        fake,
        const _GoogleOwnershipBinding(),
      );
      final purchase = _purchase('com.example.points1000');

      await service.completePurchase(purchase);

      expect(fake.completePurchaseCalls, hasLength(1));
      expect(
        fake.completePurchaseCalls.single.productID,
        'com.example.points1000',
      );
    });

    test('restorePurchases forwards to the plugin', () async {
      // WHY: restore triggers the platform to surface historical / unfinished
      // transactions on purchaseStream (plugin contract); the service only
      // forwards the call.
      final fake = _FakeInAppPurchase();
      final service = InAppPurchaseIapService(
        fake,
        const _GoogleOwnershipBinding(),
      );

      await service.restorePurchases();

      expect(fake.restorePurchasesCalls, hasLength(1));
    });
  });

  group('platformProviderOf / receiptOf helpers', () {
    test(
      'platformProviderOf: google for google_play source, apple otherwise',
      () {
        // WHY: the receipt-request `provider` field is derived from the purchase
        // verification source — google_play → 'google', else 'apple' (StoreKit).
        final googlePurchase = _purchase('p', source: 'google_play');
        final applePurchase = _purchase('p', source: 'app_store');

        expect(platformProviderOf(googlePurchase), 'google');
        expect(platformProviderOf(applePurchase), 'apple');
      },
    );

    test('receiptOf: serverVerificationData for google, localVerificationData '
        'for apple', () {
      // WHY: Google receipts use the purchaseToken (serverVerificationData);
      // Apple receipts use the StoreKit 2 jwsRepresentation
      // (localVerificationData).
      final googlePurchase = _purchase(
        'p',
        source: 'google_play',
        local: 'google-local',
        server: 'google-purchase-token',
      );
      final applePurchase = _purchase(
        'p',
        source: 'app_store',
        local: 'apple-jws',
        server: 'apple-server',
      );

      expect(receiptOf(googlePurchase), 'google-purchase-token');
      expect(receiptOf(applePurchase), 'apple-jws');
    });
  });
}
