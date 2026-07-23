import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../account/password_page.dart';
import '../account/password_type.dart';
import '../../l10n/app_localizations.dart';
import '../../core/providers.dart';

class MyPage extends HookConsumerWidget {
  static const sName = 'my';

  const MyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    final packageInfoAsync = ref.watch(packageInfoProvider);
    final version = packageInfoAsync.maybeWhen(
      data: (info) => info.version,
      orElse: () => '',
    );

    // hasNewVersion 是 checkVersion() 异步写入服务内部状态的，
    // provider 不感知其变化，这里用本地 useState 持有副本，检查后手动刷新。
    final versionService = ref.read(versionServiceProvider);
    final hasNewVersion = useState<bool>(versionService.hasNewVersion);

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
      final l10n = AppLocalizations.of(context)!;
      // TODO: 实现登出逻辑（例如清除本地登录态、调用后端登出接口）
      SmartDialog.showToast(l10n.logout);
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
      SmartDialog.showToast(
        'Navigate to ${l10n.userAgreement} (Not Implemented)',
      );
    }

    void viewPrivacyPolicy(BuildContext context) {
      final l10n = AppLocalizations.of(context)!;
      SmartDialog.showToast(
        'Navigate to ${l10n.privacyPolicy} (Not Implemented)',
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myAccount)),
      body: ListView(
        children: <Widget>[
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
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.changePassword),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              GoRouter.of(context).pushNamed(
                ChangePasswordPage.sName,
                extra: ChangePasswordType.ResetPassword,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.logout),
            onTap: () => logout(context),
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
