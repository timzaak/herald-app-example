import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_providers.dart';
import '../../services/auth/auth_error.dart';
import '../../services/auth/herald_auth_repository.dart';
import '../../util/validator.dart';

/// Recover-password confirm step (design §4.4.2, FL-D04).
///
/// The reset code is the one emailed to the user after `/password`'s
/// request step ( Herald always returns 200 there to prevent enumeration, so
/// reaching this page does not imply the email existed). On submit the
/// repository throws [AuthErrorException] on failure; the UI maps `error.kind`
/// to a localized toast and stays on the page (except on success → `/login`).
///
/// Invalid/expired reset codes are classified separately from configuration
/// and transport failures, so the page does not mislabel server outages.
class ResetPasswordConfirmPage extends HookConsumerWidget {
  static const sName = 'reset-password-confirm';

  final String email;

  const ResetPasswordConfirmPage({super.key, required this.email});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final codeController = useTextEditingController();
    final passwordController = useTextEditingController();
    final confirmController = useTextEditingController();
    final loading = useState<bool>(false);

    String errorForKind(AuthErrorKind kind) {
      switch (kind) {
        case AuthErrorKind.rateLimited:
          return l10n.rateLimited;
        case AuthErrorKind.turnstileFailed:
          return l10n.turnstileFailed;
        case AuthErrorKind.resetCodeInvalid:
          return l10n.resetCodeInvalid;
        case AuthErrorKind.network:
          return l10n.unexpectedError('network');
        case AuthErrorKind.configMissing:
          return l10n.unexpectedError('config');
        case AuthErrorKind.invalidCredentials:
        case AuthErrorKind.accountNotActivated:
        case AuthErrorKind.emailNotRegistered:
        case AuthErrorKind.emailAlreadyRegistered:
        case AuthErrorKind.verificationCodeInvalid:
        case AuthErrorKind.consentRequired:
        case AuthErrorKind.sessionExpired:
          return l10n.unexpectedError(kind.name);
      }
    }

    Future<void> submit() async {
      if (loading.value) return;
      if (formKey.currentState?.validate() != true) return;
      loading.value = true;
      try {
        final code = codeController.text.trim();
        final newPass = passwordController.text;
        final turnstileToken = await ref
            .read(turnstileServiceProvider)
            .obtainToken();
        await ref
            .read(heraldAuthRepositoryProvider)
            .confirmResetPassword(
              code: code,
              newPass: newPass,
              turnstileToken: turnstileToken,
            );
        if (!context.mounted) return;
        SmartDialog.showToast(l10n.passwordResetSuccess);
        if (context.mounted) context.go('/login');
      } on AuthErrorException catch (e) {
        if (!context.mounted) return;
        SmartDialog.showToast(errorForKind(e.error.kind));
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.resetPasswordConfirmTitle)),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const ValueKey('resetConfirmCodeField'),
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(hintText: l10n.enterResetCode),
                    validator: validateVerificationCode,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('resetConfirmPasswordField'),
                    controller: passwordController,
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      hintText: l10n.enterNewPassword,
                      helperText: l10n.passwordPolicyHint,
                    ),
                    validator: validatePassword,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('resetConfirmNewPasswordField'),
                    controller: confirmController,
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      hintText: l10n.enterConfirmNewPassword,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.enterConfirmNewPassword;
                      }
                      if (value != passwordController.text) {
                        return l10n.passwordMismatch;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      key: const ValueKey('resetConfirmSubmitButton'),
                      onPressed: loading.value ? null : submit,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        disabledBackgroundColor: Colors.blueAccent.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      child: Text(
                        l10n.submit,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      key: const ValueKey('resetConfirmBackToLoginButton'),
                      onPressed: loading.value
                          ? null
                          : () => context.go('/login'),
                      child: Text(l10n.backToLogin),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
