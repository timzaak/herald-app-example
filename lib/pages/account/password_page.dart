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
import 'password_type.dart';

/// Shared email + (reset) code page (design §4.4.2, FL-D04).
///
/// Two variants share this widget via [ChangePasswordType]:
/// - [ChangePasswordType.ForgotPassword] — the recover-password **request**
///   entry. The user enters their email and taps "get code" to fire
///   `reset_password/request`; "submit" then navigates to
///   `/reset-password-confirm` where the emailed code + new password are
///   collected. Per design §4.4.2 the code input is hidden for this variant
///   (confirmation happens on the confirm page, not here).
/// - [ChangePasswordType.ResetPassword] — out of scope this iteration; the
///   code input + its validator still render so the shared page is not broken.
///
/// `ChangePasswordType` plumbing is unchanged so `password_type.dart` stays
/// untouched. Only the `ForgotPassword` flow is wired to the repository in this
/// iteration; `ResetPassword` keeps its existing skeleton behavior.
class ChangePasswordPage extends HookConsumerWidget {
  static const sName = 'password';
  final ChangePasswordType type;

  const ChangePasswordPage({super.key, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final emailController = useTextEditingController();
    final codeController = useTextEditingController();
    final formKey = useMemoized(() => GlobalKey<FormState>());

    final countdown = useState(0);
    final isCounting = useState(false);
    final loading = useState<bool>(false);

    final bool isForgot = type == ChangePasswordType.ForgotPassword;

    String errorForKind(AuthErrorKind kind) {
      switch (kind) {
        case AuthErrorKind.rateLimited:
          return l10n.rateLimited;
        case AuthErrorKind.configMissing:
          return l10n.unexpectedError('config');
        case AuthErrorKind.turnstileFailed:
          return l10n.turnstileFailed;
        case AuthErrorKind.network:
          return l10n.unexpectedError('network');
        case AuthErrorKind.invalidCredentials:
        case AuthErrorKind.accountNotActivated:
        case AuthErrorKind.emailNotRegistered:
        case AuthErrorKind.emailAlreadyRegistered:
        case AuthErrorKind.verificationCodeInvalid:
        case AuthErrorKind.resetCodeInvalid:
        case AuthErrorKind.consentRequired:
        case AuthErrorKind.sessionExpired:
        case AuthErrorKind.providerUnavailable:
        case AuthErrorKind.serviceUnavailable:
        case AuthErrorKind.cancelled:
          return l10n.unexpectedError(kind.name);
      }
    }

    void startTimer() {
      countdown.value = 60;
      isCounting.value = true;
      Future.doWhile(() async {
        await Future.delayed(const Duration(seconds: 1));
        if (countdown.value > 0) {
          countdown.value--;
        }
        if (countdown.value == 0) {
          isCounting.value = false;
          return false; // stop the timer
        }
        return true; // continue the timer
      });
    }

    Future<void> getCode() async {
      if (loading.value) return;
      if (isCounting.value) return;
      final email = emailController.text.trim();
      final emailError = validateEmail(email);
      if (emailError != null) {
        SmartDialog.showToast(emailError);
        return;
      }
      loading.value = true;
      try {
        final turnstileToken = await ref
            .read(turnstileServiceProvider)
            .obtainToken();
        await ref
            .read(heraldAuthRepositoryProvider)
            .requestResetPassword(email: email, turnstileToken: turnstileToken);
        if (!context.mounted) return;
        // Herald always returns 200 to prevent enumeration — do NOT branch on
        // email existence. Start the countdown regardless and let the user
        // proceed.
        startTimer();
      } on AuthErrorException catch (e) {
        if (!context.mounted) return;
        SmartDialog.showToast(errorForKind(e.error.kind));
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    Future<void> submit() async {
      if (loading.value) return;
      if (formKey.currentState?.validate() != true) return;
      final email = emailController.text.trim();
      if (!context.mounted) return;
      if (isForgot) {
        // Recover-password flow: the code + new password are collected on the
        // confirm page. Carry the email forward for context.
        context.go('/reset-password-confirm', extra: {'email': email});
      }
      // ChangePasswordType.ResetPassword is out of scope this iteration; the
      // existing skeleton leaves submit as a no-op for that variant.
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isForgot ? l10n.forgotPassword : l10n.changePassword),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextFormField(
                  key: const ValueKey('passwordEmailField'),
                  controller: emailController,
                  decoration: InputDecoration(labelText: l10n.enterEmail),
                  validator: validateEmail,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16.0),
                // Conditional build (design §4.4.2 / Work §5): render the code
                // input + validator only for ResetPassword. For ForgotPassword
                // hide it — confirmation happens on /reset-password-confirm.
                if (!isForgot)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('passwordCodeField'),
                          controller: codeController,
                          decoration: InputDecoration(
                            labelText: l10n.enterVerificationCode,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.enterVerificationCode;
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Flexible(
                        child: TextButton(
                          key: const ValueKey('passwordGetCodeButton'),
                          onPressed: isCounting.value || loading.value
                              ? null
                              : getCode,
                          child: Text(
                            isCounting.value
                                ? l10n.resendCode(countdown.value.toString())
                                : l10n.getVerificationCode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (isForgot)
                  // ForgotPassword keeps an explicit get-code affordance below
                  // the email (the recover-password request trigger).
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('passwordGetCodeButtonForgot'),
                      onPressed: isCounting.value || loading.value
                          ? null
                          : getCode,
                      child: Text(
                        isCounting.value
                            ? l10n.resendCode(countdown.value.toString())
                            : l10n.getVerificationCode,
                      ),
                    ),
                  ),
                const SizedBox(height: 24.0),
                ElevatedButton(
                  key: const ValueKey('passwordSubmitButton'),
                  onPressed: loading.value ? null : submit,
                  child: Text(l10n.submit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
