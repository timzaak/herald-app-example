import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../providers/account_providers.dart';
import '../providers/auth_providers.dart';
import '../services/billing/billing_service.dart';
import '../services/iap/iap_models.dart';
import '../services/iap/iap_service.dart';

final iapServiceProvider = Provider<IapService>((ref) {
  return InAppPurchaseIapService(
    InAppPurchase.instance,
    PlatformIapOwnershipBinding(),
  );
});

/// Current Herald `user_id` (ownership-binding preflight). Reads
/// `GET /api/auth/status` `userId`. The notifier gates `buy()` on this —
/// null blocks the purchase fail-closed.
final currentUserIdProvider = FutureProvider<String?>((ref) async {
  return ref.watch(heraldAuthRepositoryProvider).currentUserId();
});

/// IAP products = backend `purchase-options` (filtered to apple/google) aligned
/// with store `ProductDetails`.
///
/// - Display price comes from `storeProduct.price` (the store-resolved
///   `ProductDetails`); the purchase page reads it off each [IapProduct].
/// - Keeps `option.alreadyOwned` rows so restored transactions can still
///   resolve their mapping. The purchase page and notifier block a new buy for
///   those rows.
/// - Options whose store `ProductDetails` is missing (mismatch between backend
///   `externalProductId` and App Store Connect / Play Console ids) are silently
///   skipped — the list is just shorter.
final iapProductsProvider = FutureProvider<List<IapProduct>>((ref) async {
  final options = await ref.watch(purchaseOptionsProvider.future);
  final iapOptions = options
      .where(
        (o) =>
            (o.paymentProvider == 'apple' || o.paymentProvider == 'google') &&
            o.externalProductId != null &&
            o.externalProductId!.isNotEmpty,
      )
      .toList();
  if (iapOptions.isEmpty) return const <IapProduct>[];
  final storeIds = iapOptions.map((o) => o.externalProductId!).toSet();
  final products = await ref.watch(iapServiceProvider).queryProducts(storeIds);
  final byId = {for (var p in products) p.id: p};
  return [
    for (final o in iapOptions)
      if (byId.containsKey(o.externalProductId))
        IapProduct(option: o, storeProduct: byId[o.externalProductId]!),
  ];
});

/// Purchase / restore transaction state. Hand-written sealed class hierarchy
/// (matches the codebase convention — no freezed).
sealed class IapPurchaseState {
  const IapPurchaseState();
}

class IapPurchaseIdle extends IapPurchaseState {
  const IapPurchaseIdle();
}

class IapPurchasePurchasing extends IapPurchaseState {
  const IapPurchasePurchasing();
}

class IapPurchaseRestoring extends IapPurchaseState {
  const IapPurchaseRestoring();
}

/// Fulfillment succeeded. [result] is the backend `IapReceiptResponse`
/// projection (`status == 'succeeded'`). The notifier has already invalidated
/// `accountOverviewProvider` — the UI MUST NOT double-invalidate.
class IapPurchaseFulfilled extends IapPurchaseState {
  const IapPurchaseFulfilled(this.result);
  final IapReceiptResult result;
}

/// Fulfillment / purchase failed. [reason] drives the l10n key (mapping
/// documented on [IapFailureReason]).
class IapPurchaseFailed extends IapPurchaseState {
  const IapPurchaseFailed(this.reason);
  final IapFailureReason reason;
}

/// Purchase / restore state machine.
///
/// Stream ownership: the notifier subscribes to [IapService.purchaseStream] in
/// [build] and cancels in `ref.onDispose`. The UI does NOT subscribe — it only
/// calls [replayPending] in a `useEffect` on page-visible to drive cold-start
/// / unfinished-transaction replay. Owning the subscription in the notifier
/// (not the widget) keeps it tied to the provider lifecycle and avoids a
/// widget-rebuild leak.
class IapPurchaseNotifier extends Notifier<IapPurchaseState> {
  StreamSubscription<List<PurchaseDetails>>? _streamSub;

  /// Unfinished transactions retained for replay. Keyed by
  /// `purchase.productID`. NEVER [IapService.completePurchase] on a failure —
  /// the credential is retained and resubmitted on next replay (backend
  /// idempotency guarantees no double-charge).
  final Map<String, PurchaseDetails> _pendingReplay = {};

  /// Set true when [restore] completes without any `restored` event surfacing
  /// (the UI surfaces `iapRestoreNothing`). Reset to false on the next [buy].
  bool lastRestoreWasEmpty = false;

  @override
  IapPurchaseState build() {
    _streamSub = ref
        .read(iapServiceProvider)
        .purchaseStream
        .listen(_handlePurchases);
    ref.onDispose(() {
      _streamSub?.cancel();
      _streamSub = null;
    });

    return const IapPurchaseIdle();
  }

  /// Initiates a purchase for [product].
  ///
  /// - `currentUserIdProvider` null → [IapPurchaseFailed]([IapFailureReason.generic]);
  ///   `buy*` NOT called (fail-closed — never inject an empty binding).
  /// - [IapService.canBindUserId] false (iOS non-UUID) →
  ///   [IapPurchaseFailed]([IapFailureReason.ownershipMismatch]); `buy*` NOT called.
  /// - one-time with points → [IapService.buyConsumable].
  /// - points-less one-time buyout / recurring / non-renewing →
  ///   [IapService.buyNonConsumable].
  /// - already-owned or unknown billing type → fail closed; `buy*` NOT called.
  ///
  /// Does NOT flip to fulfilled here — the `purchaseStream` listener drives
  /// fulfillment. The `buy*` call returns once the system purchase sheet is
  /// presented.
  Future<void> buy(IapProduct product) async {
    lastRestoreWasEmpty = false;
    state = const IapPurchasePurchasing();

    if (!product.option.purchasable) {
      state = const IapPurchaseFailed(IapFailureReason.productUnavailable);
      return;
    }

    final userId = await ref.read(currentUserIdProvider.future);
    if (userId == null) {
      // Fail-closed: block — do NOT inject an empty binding.
      state = const IapPurchaseFailed(IapFailureReason.generic);
      return;
    }

    final iap = ref.read(iapServiceProvider);
    if (!iap.canBindUserId(userId)) {
      // iOS non-UUID userId — StoreKit and the backend would both reject.
      state = const IapPurchaseFailed(IapFailureReason.ownershipMismatch);
      return;
    }

    try {
      if (product.option.isConsumable) {
        await iap.buyConsumable(product: product.storeProduct, userId: userId);
      } else if (product.option.isNonConsumable) {
        await iap.buyNonConsumable(
          product: product.storeProduct,
          userId: userId,
        );
      } else {
        // `purchasable` already rejects this branch. Keep the defensive
        // backstop local to the purchase boundary.
        state = const IapPurchaseFailed(IapFailureReason.productUnavailable);
      }
      // State stays Purchasing — the stream listener advances to fulfilled /
      // failed / idle when the platform reports the transaction outcome.
    } on Object catch (e) {
      // The plugin threw synchronously presenting the sheet (rare). Surface a
      // generic failure; no purchase was created so nothing to retain/complete.
      debugPrint('IapPurchaseNotifier.buy: $e');
      state = const IapPurchaseFailed(IapFailureReason.generic);
    }
  }

  /// Initiates a restore. The platform surfaces historical / unfinished
  /// transactions on `purchaseStream` as `restored` events, which flow through
  /// [_handlePurchases] (same submit exit). If no events arrive before
  /// `restorePurchases()` completes, sets [lastRestoreWasEmpty] for the UI to
  /// surface `iapRestoreNothing`.
  Future<void> restore() async {
    lastRestoreWasEmpty = false;
    state = const IapPurchaseRestoring();
    try {
      await ref.read(iapServiceProvider).restorePurchases();
      // The platform surfaces `restored` events asynchronously after this
      // Future completes; if none arrived, the UI reads lastRestoreWasEmpty.
      // (We do NOT race a timer here — the UI reads this flag once the user
      // has observed the restore settle; events that arrive later flip state
      // to fulfilled / failed as usual.)
      // Mark empty only if still restoring (no event flipped state) — the
      // simplest reliable signal: state is still Restoring.
      if (state is IapPurchaseRestoring) {
        lastRestoreWasEmpty = true;
        state = const IapPurchaseIdle();
      }
    } on Object catch (e) {
      debugPrint('IapPurchaseNotifier.restore: $e');
      state = const IapPurchaseFailed(IapFailureReason.generic);
    }
  }

  /// Replays retained unfinished transactions. Called by the UI in a
  /// `useEffect` on page-visible (cold start / re-entry). Each retained
  /// purchase is re-submitted via [_submitAndAdvance]; backend idempotency
  /// guarantees no double-charge.
  Future<void> replayPending() async {
    if (_pendingReplay.isEmpty) return;
    // Snapshot the keys — _submitAndAdvance mutates _pendingReplay on success.
    final pending = _pendingReplay.values.toList(growable: false);
    for (final purchase in pending) {
      await _submitAndAdvance(purchase);
    }
  }

  /// Dispatches a `purchaseStream` event.
  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // A restored event clears the restore-empty flag.
          lastRestoreWasEmpty = false;
          _submitAndAdvance(purchase);
        case PurchaseStatus.error:
          // Unrecoverable — complete so the platform stops re-delivering, then
          // surface a generic failure.
          _safeComplete(purchase);
          state = const IapPurchaseFailed(IapFailureReason.generic);
        case PurchaseStatus.canceled:
          // Silent — complete and return to idle, no failure toast.
          _safeComplete(purchase);
          state = const IapPurchaseIdle();
        case PurchaseStatus.pending:
          // No state change — the platform will surface a follow-up event.
          break;
      }
    }
  }

  /// Resolves the [IapProduct] for a store purchase id by reading the current
  /// product list on demand (purchase events are rare — one per transaction —
  /// so a linear scan avoids retaining a shadow lookup map that has to be kept
  /// in sync with [iapProductsProvider]). Returns null when products haven't
  /// resolved yet or the product is no longer listed.
  IapProduct? _productFor(String storeId) {
    final products =
        ref.read(iapProductsProvider).value ?? const <IapProduct>[];
    for (final p in products) {
      if (p.storeId == storeId) return p;
    }
    return null;
  }

  /// Builds the receipt input and submits it; advances state on the result.
  ///
  /// Credential-loss retain (critical contract):
  /// - `result.succeeded` → [IapService.completePurchase], drop from
  ///   [_pendingReplay], invalidate `accountOverviewProvider`, state Fulfilled.
  /// - 200 `status == 'failed'` OR `DioException` (4xx/5xx/network) OR other
  ///   `Object` → retain in [_pendingReplay] (DO NOT complete), state Failed.
  Future<void> _submitAndAdvance(PurchaseDetails purchase) async {
    final product = _productFor(purchase.productID);
    if (product == null) {
      // No mapping — e.g. a restore of a product no longer in the current
      // list. Cannot fulfill without a targetId; complete to stop re-delivery
      // and surface a generic failure.
      debugPrint(
        'IapPurchaseNotifier: no IapProduct for storeId ${purchase.productID}; '
        'completing unrecoverable purchase',
      );
      _safeComplete(purchase);
      _pendingReplay.remove(purchase.productID);
      state = const IapPurchaseFailed(IapFailureReason.noMapping);
      return;
    }

    final input = IapReceiptInput(
      provider: platformProviderOf(purchase),
      receipt: receiptOf(purchase),
      productId: purchase.productID,
      targetId: product.option.mappingId,
    );

    try {
      final result = await ref
          .read(billingServiceProvider)
          .submitIapReceipt(input);
      if (result.succeeded) {
        await ref.read(iapServiceProvider).completePurchase(purchase);
        _pendingReplay.remove(purchase.productID);
        ref.invalidate(accountOverviewProvider);
        state = IapPurchaseFulfilled(result);
      } else {
        // 200-channel failure (only verification_failed possible) — retain
        // for replay; DO NOT complete.
        _pendingReplay[purchase.productID] = purchase;
        state = IapPurchaseFailed(classifyIapFailure(result: result));
      }
    } on DioException catch (e) {
      // 4xx / 5xx / network — retain for replay; DO NOT complete.
      debugPrint('IapPurchaseNotifier: submitIapReceipt DioException: $e');
      _pendingReplay[purchase.productID] = purchase;
      state = IapPurchaseFailed(classifyIapFailure(dioError: e));
    } on Object catch (e) {
      // Unexpected — retain for replay; DO NOT complete.
      debugPrint('IapPurchaseNotifier: submitIapReceipt error: $e');
      _pendingReplay[purchase.productID] = purchase;
      state = const IapPurchaseFailed(IapFailureReason.generic);
    }
  }

  /// Completes a purchase best-effort (never throws — a completePurchase
  /// failure on an unrecoverable purchase should not mask the primary state).
  Future<void> _safeComplete(PurchaseDetails purchase) async {
    try {
      await ref.read(iapServiceProvider).completePurchase(purchase);
    } on Object catch (e) {
      debugPrint(
        'IapPurchaseNotifier: completePurchase failed (suppressed): $e',
      );
    }
  }

  /// Test-visible accessor for the retained-replay count (the credential-loss
  /// assertions assert against it).
  @visibleForTesting
  int get pendingReplayCount => _pendingReplay.length;
}

final iapPurchaseProvider =
    NotifierProvider<IapPurchaseNotifier, IapPurchaseState>(
      IapPurchaseNotifier.new,
    );
