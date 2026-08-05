import 'dart:async';

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

/// Post-registration email-verification waiting page (design §4.4.2, FL-D04).
///
/// Receives [email] from `/register` via the route `extra` map. The resend
/// button calls `resendVerification` (which throws [AuthErrorException] on
/// failure per the FL-D02 binding) and mirrors `LoginPage`'s 60s countdown so
/// the user cannot spam the trigger.
class VerifyEmailPendingPage extends HookConsumerWidget {
  static const sName = 'verify-email-pending';

  final String email;

  const VerifyEmailPendingPage({super.key, required this.email});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final loading = useState<bool>(false);
    final codeController = useTextEditingController();
    final seconds = useState<int?>(null);
    final timer = useRef<Timer?>(null);

    useEffect(() {
      return () {
        timer.value?.cancel();
      };
    }, []);

    String errorForKind(AuthErrorKind kind) {
      switch (kind) {
        case AuthErrorKind.rateLimited:
          return l10n.rateLimited;
        case AuthErrorKind.configMissing:
          return l10n.unexpectedError('config');
        case AuthErrorKind.turnstileFailed:
          return l10n.turnstileFailed;
        case AuthErrorKind.verificationCodeInvalid:
          return l10n.verificationCodeInvalid;
        case AuthErrorKind.network:
          return l10n.unexpectedError('network');
        case AuthErrorKind.invalidCredentials:
        case AuthErrorKind.accountNotActivated:
        case AuthErrorKind.emailNotRegistered:
        case AuthErrorKind.emailAlreadyRegistered:
        case AuthErrorKind.resetCodeInvalid:
        case AuthErrorKind.consentRequired:
        case AuthErrorKind.sessionExpired:
        case AuthErrorKind.providerUnavailable:
        case AuthErrorKind.serviceUnavailable:
        case AuthErrorKind.cancelled:
          return l10n.unexpectedError(kind.name);
      }
    }

    void startCountdown() {
      seconds.value = 60;
      timer.value?.cancel();
      timer.value = Timer.periodic(const Duration(seconds: 1), (_) {
        if (seconds.value != null) {
          seconds.value = seconds.value! - 1;
          if (seconds.value == 0) {
            timer.value?.cancel();
            seconds.value = null;
          }
        }
      });
    }

    Future<void> resend() async {
      if (loading.value) return;
      if (seconds.value != null) return; // still counting down
      if (email.isEmpty) {
        SmartDialog.showToast(l10n.unexpectedError('email'));
        return;
      }
      loading.value = true;
      try {
        final turnstileToken = await ref
            .read(turnstileServiceProvider)
            .obtainToken();
        await ref
            .read(heraldAuthRepositoryProvider)
            .resendVerification(email: email, turnstileToken: turnstileToken);
        if (!context.mounted) return;
        SmartDialog.showToast(l10n.verificationEmailSent);
        startCountdown();
      } on AuthErrorException catch (e) {
        if (!context.mounted) return;
        SmartDialog.showToast(errorForKind(e.error.kind));
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    Future<void> verify() async {
      if (loading.value) return;
      final code = codeController.text.trim();
      final error = validateVerificationCode(code);
      if (error != null) {
        SmartDialog.showToast(error);
        return;
      }
      loading.value = true;
      try {
        await ref
            .read(heraldAuthRepositoryProvider)
            .confirmEmailVerification(code: code);
        if (!context.mounted) return;
        SmartDialog.showToast(l10n.emailVerificationSuccess);
        context.go('/login');
      } on AuthErrorException catch (e) {
        if (!context.mounted) return;
        SmartDialog.showToast(errorForKind(e.error.kind));
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.verifyEmailPendingTitle)),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.verifyEmailPendingNotice,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(email, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 32),
                TextFormField(
                  key: const ValueKey('verifyEmailCodeField'),
                  controller: codeController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: l10n.enterVerificationCode,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    key: const ValueKey('verifyEmailSubmitButton'),
                    onPressed: loading.value ? null : verify,
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
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    key: const ValueKey('verifyEmailResendButton'),
                    onPressed: loading.value || seconds.value != null
                        ? null
                        : resend,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      disabledBackgroundColor: Colors.blueAccent.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    child: Text(
                      seconds.value == null
                          ? l10n.resendVerificationEmail
                          : l10n.resendCode(seconds.value.toString()),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    key: const ValueKey('verifyEmailBackToLoginButton'),
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
    );
  }
}
