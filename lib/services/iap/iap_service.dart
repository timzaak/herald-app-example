import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'iap_models.dart';

/// Encapsulates the `in_app_purchase` plugin: product query, purchase (with
/// ownership binding), restore, unfinished-transaction stream, and purchase
/// completion. Platform differences (Apple `appAccountToken` vs Google
/// `obfuscatedAccountId`) are isolated in the [IapOwnershipBinding].
abstract class IapService {
  /// Queries the store for [ProductDetails] by store product id. Returns the
  /// matched set (store lookups dedupe by id). Unmatched ids are surfaced via
  /// `response.notFoundIDs` and logged; `iapProductsProvider` merges the
  /// result and skips unmatched backend options.
  Future<Set<ProductDetails>> queryProducts(Set<String> storeIds);

  /// Initiates a non-consumable purchase (recurring subscription). The Herald
  /// `userId` is injected via the platform binding
  /// (`applicationUserName` = the iOS `appAccountToken` carrier path).
  ///
  /// Throws [IapOwnershipBindingException] if [IapOwnershipBinding.canBind]
  /// returns false for [userId] (fail-closed guard; the purchase notifier is
  /// expected to have already blocked upstream).
  Future<void> buyNonConsumable({
    required ProductDetails product,
    required String userId,
  });

  /// Initiates a consumable purchase (one-time points pack). See
  /// [buyNonConsumable] for the ownership-binding contract.
  Future<void> buyConsumable({
    required ProductDetails product,
    required String userId,
  });

  /// Triggers the platform to surface historical / unfinished transactions on
  /// [purchaseStream] (Apple requires an explicit restore entry for
  /// subscription audit). The listener owns per-purchase receipt submission.
  Future<void> restorePurchases();

  /// Real-time purchase updates, including cold-start unfinished transactions.
  /// The purchase page and restore entry share this stream.
  Stream<List<PurchaseDetails>> get purchaseStream;

  /// Marks a purchase finished so the platform stops re-delivering it. Called
  /// only after fulfillment success OR an unrecoverable failure/error/cancel
  /// (never after a receipt-submission transient failure — the purchase is
  /// retained for replay; backend idempotency guarantees no double-charge).
  Future<void> completePurchase(PurchaseDetails purchase);

  /// Thin pass-through to [IapOwnershipBinding.canBind]. The purchase notifier
  /// reads this before initiating a purchase so an invalid/empty ownership
  /// binding is never injected (iOS fails closed when `userId` is not a valid
  /// UUID). Binding logic lives in [IapOwnershipBinding] — do not duplicate it.
  bool canBindUserId(String userId);
}

class InAppPurchaseIapService implements IapService {
  InAppPurchaseIapService(this._iap, this._binding);

  final InAppPurchase _iap;
  final IapOwnershipBinding _binding;

  @override
  Future<Set<ProductDetails>> queryProducts(Set<String> storeIds) async {
    final response = await _iap.queryProductDetails(storeIds);
    final notFound = response.notFoundIDs;
    if (notFound.isNotEmpty) {
      debugPrint('IapService.queryProducts: not found store ids: $notFound');
    }
    return response.productDetails.toSet();
  }

  @override
  Future<void> buyNonConsumable({
    required ProductDetails product,
    required String userId,
  }) => _buy(product, userId, consumable: false);

  @override
  Future<void> buyConsumable({
    required ProductDetails product,
    required String userId,
  }) => _buy(product, userId, consumable: true);

  /// Builds the [PurchaseParam] with the ownership binding injected as
  /// `applicationUserName` = the validated [userId], then dispatches the
  /// platform purchase. Defensive: asserts [IapOwnershipBinding.canBind] before
  /// injecting so an invalid/empty binding is never sent to StoreKit / Play
  /// (the notifier must already block, but keep this backstop).
  Future<void> _buy(
    ProductDetails product,
    String userId, {
    required bool consumable,
  }) async {
    final param = _purchaseParam(product, userId);
    if (consumable) {
      // autoConsume defaults to true — matches the points-pack replay contract.
      await _iap.buyConsumable(purchaseParam: param, autoConsume: true);
    } else {
      await _iap.buyNonConsumable(purchaseParam: param);
    }
  }

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);

  @override
  bool canBindUserId(String userId) => _binding.canBind(userId);

  PurchaseParam _purchaseParam(ProductDetails product, String userId) {
    if (!_binding.canBind(userId)) {
      throw IapOwnershipBindingException(userId);
    }
    return PurchaseParam(
      productDetails: product,
      // iOS appAccountToken carrier path: the validated UUID is injected
      // verbatim as `applicationUserName`; Android uses the raw userId string
      // as obfuscatedExternalAccountId.
      applicationUserName: userId,
    );
  }
}

/// The receipt-request `provider` value for a purchase:
/// `'google'` when the purchase originated from Google Play, otherwise
/// `'apple'` (StoreKit).
///
/// The `in_app_purchase` interface exposes `source` as a plain `String`
/// (`'google_play'` on Android, `'app_store'` on iOS) — not an enum — so we
/// compare the string literal here.
String platformProviderOf(PurchaseDetails purchase) {
  return purchase.verificationData.source == 'google_play' ? 'google' : 'apple';
}

/// The receipt payload string for a purchase:
/// - Google → `serverVerificationData` (the Play Billing `purchaseToken`).
/// - Apple → `localVerificationData` (the StoreKit 2 `jwsRepresentation` JWS).
String receiptOf(PurchaseDetails purchase) {
  return purchase.verificationData.source == 'google_play'
      ? purchase.verificationData.serverVerificationData
      : purchase.verificationData.localVerificationData;
}
