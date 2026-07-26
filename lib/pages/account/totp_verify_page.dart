import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_providers.dart';
import '../../services/auth/auth_error.dart';
import '../../services/auth/auth_redirect.dart';
import '../../services/auth/auth_result.dart';
import '../../util/validator.dart';

/// TOTP second-factor verification (design §4.4.2).
///
/// Receives [tempToken] / [secondFactors] from `/login` (or, defensively,
/// from `/consent` replay failures) via the route `extra` map. On submit:
/// - [AuthSuccess] → navigate to the preserved post-login destination
///   (`/index` by default).
/// - [AuthConsentRequired] → route to `/consent`, replaying the TOTP flow.
/// - [AuthFailure] with [AuthErrorKind.sessionExpired] → tempToken expired /
///   locked; surface a toast and bounce to `/login`.
/// - other [AuthFailure] → surface the mapped message and stay on the page.
///
/// Cancel never establishes a session → returns to `/login`.
class TotpVerifyPage extends HookConsumerWidget {
  static const sName = 'totp-verify';

  final String tempToken;
  final List<String> secondFactors;
  final String? returnTo;

  const TotpVerifyPage({
    super.key,
    required this.tempToken,
    required this.secondFactors,
    this.returnTo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final codeController = useTextEditingController();
    final loading = useState<bool>(false);
    final useBackupCode = useState<bool>(false);

    String errorForKind(AuthErrorKind kind) {
      switch (kind) {
        case AuthErrorKind.sessionExpired:
          return l10n.totpExpired;
        case AuthErrorKind.rateLimited:
          return l10n.rateLimited;
        case AuthErrorKind.configMissing:
          return l10n.unexpectedError('config');
        default:
          return l10n.unexpectedError(kind.name);
      }
    }

    Future<void> submit() async {
      if (loading.value) return;
      if (formKey.currentState?.validate() != true) return;
      loading.value = true;
      try {
        final submittedCode = codeController.text.trim();
        final backupCode = useBackupCode.value
            ? submittedCode.toUpperCase()
            : null;
        final result = await ref
            .read(authStateProvider.notifier)
            .verifyTotp(
              tempToken: tempToken,
              code: useBackupCode.value ? null : submittedCode,
              backupCode: backupCode,
            );
        switch (result) {
          case AuthSuccess():
            if (context.mounted) {
              context.go(safeAuthDestination(returnTo));
            }
          case AuthConsentRequired(:final agreements):
            if (context.mounted) {
              context.go(
                '/consent',
                extra: {
                  'agreements': agreements,
                  'originalFlow': {
                    'kind': 'totp',
                    'tempToken': tempToken,
                    'code': useBackupCode.value ? null : submittedCode,
                    'backupCode': backupCode,
                    'returnTo': returnTo,
                  },
                },
              );
            }
          case AuthRequiresTotp():
            // Not expected on the TOTP endpoint; defensively route back to
            // /login rather than silently looping.
            SmartDialog.showToast(l10n.sessionExpired);
            if (context.mounted) context.go('/login');
          case AuthFailure(:final error):
            if (error.kind == AuthErrorKind.sessionExpired) {
              SmartDialog.showToast(l10n.totpExpired);
              if (context.mounted) context.go('/login');
            } else {
              SmartDialog.showToast(errorForKind(error.kind));
            }
        }
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.totpVerifyTitle)),
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
                  Text(
                    useBackupCode.value
                        ? l10n.enterBackupCode
                        : l10n.enterTotpCode,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('totpCodeField'),
                    controller: codeController,
                    keyboardType: useBackupCode.value
                        ? TextInputType.text
                        : TextInputType.number,
                    textCapitalization: useBackupCode.value
                        ? TextCapitalization.characters
                        : TextCapitalization.none,
                    inputFormatters: useBackupCode.value
                        ? [
                            FilteringTextInputFormatter.allow(
                              RegExp('[a-zA-Z0-9]'),
                            ),
                            LengthLimitingTextInputFormatter(8),
                            _UpperCaseTextFormatter(),
                          ]
                        : [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: useBackupCode.value
                          ? 'XXXXXXXX'
                          : l10n.enterVerificationCode,
                    ),
                    validator: useBackupCode.value
                        ? (value) => value?.trim().length == 8
                              ? null
                              : l10n.invalidBackupCode
                        : validateVerificationCode,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('totpCodeModeButton'),
                      onPressed: loading.value
                          ? null
                          : () {
                              codeController.clear();
                              useBackupCode.value = !useBackupCode.value;
                            },
                      child: Text(
                        useBackupCode.value
                            ? l10n.useTotpCode
                            : l10n.useBackupCode,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      key: const ValueKey('totpVerifyButton'),
                      onPressed: loading.value ? null : submit,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        disabledBackgroundColor: Colors.blueAccent.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      child: Text(
                        l10n.totpVerify,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      key: const ValueKey('totpCancelButton'),
                      onPressed: loading.value
                          ? null
                          : () => context.go('/login'),
                      child: Text(l10n.cancel),
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

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
