import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/account_providers.dart';
import '../../services/billing/billing_service.dart';

class PurchasePage extends HookConsumerWidget {
  const PurchasePage({super.key});

  static const sName = 'purchase';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final options = ref.watch(purchaseOptionsProvider);
    final activeAttemptId = useState<String?>(null);
    final checkingPayment = useState(false);
    final purchasingMappingId = useState<String?>(null);
    final pollTimer = useRef<Timer?>(null);

    useEffect(
      () =>
          () => pollTimer.value?.cancel(),
      const [],
    );

    Future<void> checkPayment() async {
      final attemptId = activeAttemptId.value;
      if (attemptId == null || checkingPayment.value) return;
      checkingPayment.value = true;
      try {
        final status = await ref
            .read(billingServiceProvider)
            .getPaymentAttemptStatus(attemptId);
        if (!context.mounted) return;
        if (status.succeeded) {
          pollTimer.value?.cancel();
          activeAttemptId.value = null;
          ref.invalidate(accountOverviewProvider);
          SmartDialog.showToast(l10n.paymentSucceeded);
          Navigator.of(context).pop();
        } else if (status.finished) {
          pollTimer.value?.cancel();
          activeAttemptId.value = null;
          SmartDialog.showToast(l10n.paymentFailed);
        }
      } on Object {
        if (context.mounted) SmartDialog.showToast(l10n.paymentStatusFailed);
      } finally {
        if (context.mounted) checkingPayment.value = false;
      }
    }

    Future<void> purchase(PurchaseOption option) async {
      if (purchasingMappingId.value != null) return;
      purchasingMappingId.value = option.mappingId;
      try {
        final attempt = await ref
            .read(billingServiceProvider)
            .createPaymentAttempt(option);
        activeAttemptId.value = attempt.id;
        final launched = await launchUrl(
          attempt.checkoutUrl,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) throw StateError('Could not launch checkout');
        pollTimer.value?.cancel();
        pollTimer.value = Timer.periodic(
          const Duration(seconds: 2),
          (_) => checkPayment(),
        );
      } on Object {
        if (context.mounted) SmartDialog.showToast(l10n.purchaseFailed);
      } finally {
        if (context.mounted) purchasingMappingId.value = null;
      }
    }

    String price(PurchaseOption option) {
      final amount = option.amount;
      final currency = option.currency;
      if (amount == null || currency == null) return l10n.priceUnavailable;
      return '$currency ${(amount / 100).toStringAsFixed(2)}';
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.purchasePoints)),
      body: options.when(
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
                  onPressed: () => ref.invalidate(purchaseOptionsProvider),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.noPurchaseOptions));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length + (activeAttemptId.value == null ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == items.length) {
                return Card(
                  child: ListTile(
                    leading: checkingPayment.value
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.receipt_long),
                    title: Text(l10n.waitingForPayment),
                    subtitle: Text(l10n.paymentWebhookHint),
                    trailing: TextButton(
                      onPressed: checkingPayment.value ? null : checkPayment,
                      child: Text(l10n.checkPayment),
                    ),
                  ),
                );
              }
              final option = items[index];
              final busy = purchasingMappingId.value == option.mappingId;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (option.points != null) ...[
                        const SizedBox(height: 6),
                        Text(l10n.pointsAmount(option.points!)),
                      ],
                      const SizedBox(height: 6),
                      Text('${price(option)} · ${option.paymentProvider}'),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: option.purchasable && !busy
                              ? () => purchase(option)
                              : null,
                          child: Text(
                            option.alreadyOwned
                                ? l10n.alreadyOwned
                                : busy
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
          );
        },
      ),
    );
  }
}
