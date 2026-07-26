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

/// Account registration with email verification (design §4.4.2, FL-D04).
///
/// On submit the repository throws [AuthErrorException] on failure (FL-D02
/// binding); the UI catches and maps `error.kind` to a localized toast.
/// `register` returns [RegisterResult] on success — `verificationRequired`
/// decides between `/verify-email-pending` and a "you can log in" toast back
/// to `/login`.
///
/// The backend's `email_already_exists` business code is classified separately
/// from transport failures, so only that case receives the login/reset hint.
class RegisterPage extends HookConsumerWidget {
  static const sName = 'register';

  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final confirmController = useTextEditingController();
    final loading = useState<bool>(false);
    final registrationEnabled = ref.watch(registrationEnabledProvider);

    String errorForKind(AuthErrorKind kind) {
      switch (kind) {
        case AuthErrorKind.rateLimited:
          return l10n.rateLimited;
        case AuthErrorKind.configMissing:
          return l10n.unexpectedError('config');
        case AuthErrorKind.emailAlreadyRegistered:
          return l10n.emailAlreadyRegistered;
        case AuthErrorKind.network:
          return l10n.unexpectedError('network');
        case AuthErrorKind.turnstileFailed:
          return l10n.turnstileFailed;
        case AuthErrorKind.invalidCredentials:
        case AuthErrorKind.accountNotActivated:
        case AuthErrorKind.emailNotRegistered:
        case AuthErrorKind.verificationCodeInvalid:
        case AuthErrorKind.resetCodeInvalid:
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
        final email = emailController.text.trim();
        final password = passwordController.text;
        final turnstileToken = await ref
            .read(turnstileServiceProvider)
            .obtainToken();
        final result = await ref
            .read(heraldAuthRepositoryProvider)
            .register(
              email: email,
              password: password,
              turnstileToken: turnstileToken,
            );
        if (!context.mounted) return;
        if (result.verificationRequired) {
          context.go('/verify-email-pending', extra: {'email': email});
        } else {
          SmartDialog.showToast(l10n.registerSuccess);
          if (context.mounted) context.go('/login');
        }
      } on AuthErrorException catch (e) {
        if (!context.mounted) return;
        final kind = e.error.kind;
        if (kind == AuthErrorKind.emailAlreadyRegistered) {
          SmartDialog.showToast(
            '${l10n.emailAlreadyRegistered} ${l10n.emailAlreadyRegisteredHint}',
          );
        } else {
          SmartDialog.showToast(errorForKind(kind));
        }
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    if (registrationEnabled.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.registerTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (registrationEnabled.value != true) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.registerTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.registrationDisabledTitle,
                  key: const ValueKey('registrationDisabledTitle'),
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.registrationDisabledDescription,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  key: const ValueKey('registrationDisabledBackButton'),
                  onPressed: () => context.go('/login'),
                  child: Text(l10n.backToLogin),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.registerTitle)),
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
                    key: const ValueKey('registerEmailField'),
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(hintText: l10n.enterEmail),
                    validator: validateEmail,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('registerPasswordField'),
                    controller: passwordController,
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      hintText: l10n.enterPassword,
                      helperText: l10n.passwordPolicyHint,
                    ),
                    validator: validatePassword,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('registerConfirmPasswordField'),
                    controller: confirmController,
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      hintText: l10n.enterConfirmPassword,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.enterConfirmPassword;
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
                      key: const ValueKey('registerSubmitButton'),
                      onPressed: loading.value ? null : submit,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        disabledBackgroundColor: Colors.blueAccent.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      child: Text(
                        l10n.register,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      key: const ValueKey('registerBackToLoginButton'),
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
