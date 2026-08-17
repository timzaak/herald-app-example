import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/iap_providers.dart';
import '../../services/billing/billing_service.dart';
import '../../services/iap/iap_models.dart';

class PurchasePage extends HookConsumerWidget {
  const PurchasePage({super.key});

  static const sName = 'purchase';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final products = ref.watch(iapProductsProvider);
    final purchaseState = ref.watch(iapPurchaseProvider);
    final userIdAsync = ref.watch(currentUserIdProvider);

    // Holds the storeId of the product whose purchase sheet is currently open,
    // so the matching buy button shows the `openingCheckout` label.
    final activeStoreId = useState<String?>(null);

    // Cold-start / unfinished-transaction replay. The notifier owns the
    // purchaseStream subscription (its build() subscribes, ref.onDispose
    // cancels — see IapPurchaseNotifier). The widget must NOT subscribe to
    // purchaseStream directly; replayPending() is the only stream-adjacent
    // call, fired once on mount.
    useEffect(() {
      ref.read(iapPurchaseProvider.notifier).replayPending();
      return null;
    }, const []);

    // State-driven feedback. Riverpod's `ref.listen` fires the callback only
    // on an actual state change (the notifier's hand-written immutable state
    // subtypes compare by identity), so each transition reacts exactly once —
    // no double-toast on rebuild.
    //
    // - Fulfilled → success toast + pop (notifier already invalidated
    //   accountOverviewProvider — do NOT double-invalidate).
    // - Failed(reason) → reason toast.
    // - Idle / Purchasing / Restoring → no toast.
    //   (Cancel returns to Idle silently — no failure toast. A restore that
    //   settled empty surfaces `iapRestoreNothing` via the flag below.)
    ref.listen(iapPurchaseProvider, (previous, next) {
      switch (next) {
        case IapPurchaseFulfilled():
          SmartDialog.showToast(l10n.paymentSucceeded);
          Navigator.of(context).pop();
        case IapPurchaseFailed(:final reason):
          SmartDialog.showToast(_l10nForReason(l10n, reason));
        case IapPurchaseIdle():
          // Returning to idle after a restore that surfaced nothing.
          if (ref.read(iapPurchaseProvider.notifier).lastRestoreWasEmpty) {
            SmartDialog.showToast(l10n.iapRestoreNothing);
          }
          activeStoreId.value = null;
        case IapPurchasePurchasing() || IapPurchaseRestoring():
          break;
      }
    });

    Future<void> purchase(IapProduct product) async {
      // The notifier guards userId-null + canBind (fail-closed) and flips
      // state. No try/catch toast here — state-driven UI handles feedback.
      activeStoreId.value = product.storeId;
      await ref.read(iapPurchaseProvider.notifier).buy(product);
    }

    Future<void> restore() async {
      await ref.read(iapPurchaseProvider.notifier).restore();
    }

    final isPurchasing = purchaseState is IapPurchasePurchasing;
    final isRestoring = purchaseState is IapPurchaseRestoring;
    // Disable buy when there is no bindable user (preflight mirrored in UI).
    // The notifier is the fail-closed authority; this is a best-effort UX hint.
    final canBuy = userIdAsync.maybeWhen(
      data: (id) => id != null && id.isNotEmpty,
      orElse: () => false,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.purchasePoints)),
      body: products.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error is BillingConfigurationException
                      ? l10n.billingNotConfigured
                      : l10n.purchaseOptionsFailed,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  // iap-retry-button: widget + integration test finder anchor.
                  key: const ValueKey('iap-retry-button'),
                  onPressed: () => ref.invalidate(iapProductsProvider),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              // iap-empty-state: widget + integration test finder anchor
              // (integration_test/README.md `ValueKey('<domain>-<entity>-<action>')`).
              key: const ValueKey('iap-empty-state'),
              child: Text(l10n.noPurchaseOptions),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  // iap-products-list: widget + integration test finder anchor.
                  key: const ValueKey('iap-products-list'),
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final product = items[index];
                    final option = product.option;
                    final store = product.storeProduct;
                    // Display price from the store ProductDetails; fall back to
                    // option.amount/currency only when the store field is empty.
                    final priceText = _displayPrice(product, l10n);
                    final thisBusy =
                        isPurchasing && activeStoreId.value == product.storeId;
                    return Card(
                      // iap-product-<storeId>-card: per-product finder anchor.
                      // Uses the stable storeId (externalProductId) suffix so
                      // failures can be debugged by key name.
                      key: ValueKey('iap-product-${product.storeId}-card'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              store.title.isNotEmpty
                                  ? store.title
                                  : option.displayName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (store.description.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(store.description),
                            ],
                            if (option.points != null) ...[
                              const SizedBox(height: 6),
                              Text(l10n.pointsAmount(option.points!)),
                            ],
                            const SizedBox(height: 6),
                            Text('$priceText · ${option.paymentProvider}'),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                // iap-product-<storeId>-buy-button: per-product
                                // buy finder anchor.
                                key: ValueKey(
                                  'iap-product-${product.storeId}-buy-button',
                                ),
                                onPressed:
                                    (option.purchasable &&
                                        canBuy &&
                                        !isPurchasing &&
                                        !isRestoring)
                                    ? () => purchase(product)
                                    : null,
                                child: Text(
                                  option.alreadyOwned
                                      ? l10n.alreadyOwned
                                      : thisBusy
                                      ? l10n.openingCheckout
                                      : l10n.buyNow,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // SafeArea 防止 iOS 手势条/安卓导航条遮挡恢复购买按钮。
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isRestoring)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      TextButton(
                        // iap-restore-button: widget + integration test finder
                        // anchor.
                        key: const ValueKey('iap-restore-button'),
                        onPressed: isRestoring || isPurchasing ? null : restore,
                        child: Text(l10n.restorePurchase),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Prefer the store-resolved `ProductDetails.price` (localized
  /// authoritative); fall back to the backend `amount`/`currency` only when the
  /// store field is empty.
  static String _displayPrice(IapProduct product, AppLocalizations l10n) {
    final storePrice = product.storeProduct.price;
    if (storePrice.isNotEmpty) return storePrice;
    final amount = product.option.amount;
    final currency = product.option.currency;
    if (amount == null || currency == null) return l10n.priceUnavailable;
    return '$currency ${(amount / 100).toStringAsFixed(2)}';
  }

  /// Maps an [IapFailureReason] to its l10n key. Canceled is NOT a failed
  /// state (returns to Idle, silent).
  static String _l10nForReason(AppLocalizations l10n, IapFailureReason reason) {
    switch (reason) {
      case IapFailureReason.verificationFailed:
        return l10n.iapVerificationFailed;
      case IapFailureReason.ownershipMismatch:
        return l10n.iapOwnershipMismatch;
      case IapFailureReason.alreadyConsumed:
        return l10n.iapAlreadyConsumed;
      case IapFailureReason.noMapping:
      case IapFailureReason.productUnavailable:
        return l10n.iapProductUnavailable;
      case IapFailureReason.generic:
        return l10n.paymentFailed;
    }
  }
}
