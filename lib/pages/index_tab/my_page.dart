import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../core/providers.dart';
import '../../providers/account_providers.dart';
import '../../providers/auth_providers.dart';
import '../account/change_password_page.dart';
import '../account/legal_agreement_page.dart';
import '../billing/purchase_page.dart';

class MyPage extends HookConsumerWidget {
  static const sName = 'my';

  const MyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    final packageInfoAsync = ref.watch(packageInfoProvider);
    final overview = ref.watch(accountOverviewProvider);
    final version = packageInfoAsync.maybeWhen(
      data: (info) => info.version,
      orElse: () => '',
    );

    // hasNewVersion 是 checkVersion() 异步写入服务内部状态的，
    // provider 不感知其变化，这里用本地 useState 持有副本，检查后手动刷新。
    final versionService = ref.read(versionServiceProvider);
    final hasNewVersion = useState<bool>(versionService.hasNewVersion);
    final loggingOut = useState<bool>(false);

    Future<void> checkVersion() async {
      if (!kIsWeb) {
        await versionService.checkVersion();
        hasNewVersion.value = versionService.hasNewVersion;
        if (versionService.hasNewVersion) {
          await versionService.showUpgradeDialog();
        } else {
          SmartDialog.showToast('当前已是最新版本');
        }
      }
    }

    Future<void> logout(BuildContext context) async {
      if (loggingOut.value) return;
      loggingOut.value = true;
      try {
        await ref.read(authStateProvider.notifier).logout();
      } finally {
        if (context.mounted) loggingOut.value = false;
      }
    }

    Future<void> deleteAccount(BuildContext context) async {
      final l10n = AppLocalizations.of(context)!;
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(l10n.deleteAccount),
            content: Text(l10n.deleteAccountConfirm),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  l10n.delete,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          );
        },
      );

      if (confirmed == true) {
        // TODO: 实现注销账号逻辑（例如调用后端注销接口）
        SmartDialog.showToast(l10n.deleteAccount);
      }
    }

    void viewUserAgreement(BuildContext context) {
      final l10n = AppLocalizations.of(context)!;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => LegalAgreementPage(
            agreementType: 'terms_of_service',
            title: l10n.userAgreement,
          ),
        ),
      );
    }

    void viewPrivacyPolicy(BuildContext context) {
      final l10n = AppLocalizations.of(context)!;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => LegalAgreementPage(
            agreementType: 'privacy_policy',
            title: l10n.privacyPolicy,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myAccount)),
      body: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: overview.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(l10n.accountOverviewFailed),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.invalidate(accountOverviewProvider),
                  ),
                ),
                data: (account) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.nickname?.isNotEmpty == true
                            ? account.nickname!
                            : account.email,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (account.nickname?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(account.email),
                      ],
                      const SizedBox(height: 20),
                      Text(l10n.pointsBalance),
                      const SizedBox(height: 4),
                      Text(
                        account.points.toString(),
                        key: const ValueKey('pointsBalance'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 20),
                      // Membership display (evidence-limited). getOverview()
                      // currently leaves `membership` null — the null branch
                      // (membershipNone + the purchase tile below) is the live
                      // path. The non-null branch renders a lastFulfillment
                      // snapshot, NOT a verified entitlement.
                      Text(l10n.membershipLabel),
                      const SizedBox(height: 4),
                      Text(
                        key: const ValueKey('membershipStatus'),
                        account.membership != null
                            ? '${l10n.membershipActive}: '
                                  '${account.membership!.entitlementKey} '
                                  '(${account.membership!.billingType})'
                            : l10n.membershipNone,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('purchasePointsTile'),
            leading: const Icon(Icons.shopping_cart_checkout),
            title: Text(l10n.purchasePoints),
            subtitle: Text(l10n.iapCheckoutSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(PurchasePage.sName),
          ),
          const Divider(),
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('版本信息'),
              subtitle: Text(version),
              trailing: Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: checkVersion,
                  ),
                  if (hasNewVersion.value)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.policy),
            title: Text(l10n.userAgreement),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => viewUserAgreement(context),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: Text(l10n.privacyPolicy),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => viewPrivacyPolicy(context),
          ),
          const Divider(),
          ListTile(
            key: const ValueKey('changePasswordTile'),
            leading: const Icon(Icons.password),
            title: Text(l10n.changePassword),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AccountChangePasswordPage.sName),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.logout),
            enabled: !loggingOut.value,
            onTap: loggingOut.value ? null : () => logout(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: Text(
              l10n.deleteAccount,
              style: const TextStyle(color: Colors.red),
            ),
            onTap: () => deleteAccount(context),
          ),
        ],
      ),
    );
  }
}
