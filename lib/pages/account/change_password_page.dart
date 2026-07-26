import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_providers.dart';
import '../../services/auth/account_security_service.dart';
import '../../util/validator.dart';

class AccountChangePasswordPage extends HookConsumerWidget {
  const AccountChangePasswordPage({super.key});

  static const sName = 'change-password';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final currentController = useTextEditingController();
    final newController = useTextEditingController();
    final confirmController = useTextEditingController();
    final loading = useState(false);

    String errorMessage(AccountSecurityErrorKind kind) {
      return switch (kind) {
        AccountSecurityErrorKind.wrongPassword => l10n.wrongCurrentPassword,
        AccountSecurityErrorKind.reauthExpired => l10n.reauthExpired,
        AccountSecurityErrorKind.passwordRejected => l10n.passwordPolicyHint,
        AccountSecurityErrorKind.network => l10n.unexpectedError('network'),
      };
    }

    Future<void> submit() async {
      if (loading.value || formKey.currentState?.validate() != true) return;
      loading.value = true;
      try {
        await ref
            .read(accountSecurityServiceProvider)
            .changePassword(
              currentPassword: currentController.text,
              newPassword: newController.text,
            );
        if (!context.mounted) return;
        SmartDialog.showToast(l10n.passwordChangedSuccess);
        context.pop();
      } on AccountSecurityException catch (error) {
        if (context.mounted) {
          SmartDialog.showToast(errorMessage(error.kind));
        }
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.changePassword)),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
          children: [
            TextFormField(
              key: const ValueKey('changePasswordCurrentField'),
              controller: currentController,
              obscureText: true,
              decoration: InputDecoration(hintText: l10n.currentPassword),
              validator: (value) =>
                  value?.isNotEmpty == true ? null : l10n.currentPassword,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('changePasswordNewField'),
              controller: newController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: l10n.enterNewPassword,
                helperText: l10n.passwordPolicyHint,
              ),
              validator: validatePassword,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('changePasswordConfirmField'),
              controller: confirmController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: l10n.enterConfirmNewPassword,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.enterConfirmNewPassword;
                }
                return value == newController.text
                    ? null
                    : l10n.passwordMismatch;
              },
            ),
            const SizedBox(height: 30),
            TextButton(
              key: const ValueKey('changePasswordSubmitButton'),
              onPressed: loading.value ? null : submit,
              style: TextButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                disabledBackgroundColor: Colors.blueAccent.withValues(
                  alpha: 0.5,
                ),
              ),
              child: Text(
                l10n.changePassword,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
