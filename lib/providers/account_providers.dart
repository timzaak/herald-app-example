import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../api/dio_util.dart';
import '../services/account/account_service.dart';
import '../services/billing/billing_service.dart';

final accountServiceProvider = Provider<AccountService>((ref) {
  return HeraldAccountService(DioUtil.dio);
});

final accountOverviewProvider = FutureProvider<AccountOverview>((ref) {
  return ref.watch(accountServiceProvider).getOverview();
});

final billingServiceProvider = Provider<BillingService>((ref) {
  return HeraldBillingService(DioUtil.dio);
});

final purchaseOptionsProvider = FutureProvider<List<PurchaseOption>>((ref) {
  return ref.watch(billingServiceProvider).listPurchaseOptions();
});
