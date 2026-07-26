import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_providers.dart';
import '../../services/auth/auth_error.dart';
import '../../services/auth/auth_redirect.dart';
import '../../services/auth/auth_result.dart';
import 'agreement_web_view_page.dart';

/// Pre-session consent gate (design §4.4.2).
///
/// Receives the [agreements] to render and the [originalFlow] context needed to
/// replay the originating auth call with the accepted agreements appended.
/// `originalFlow.kind` is `'password'` / `'email-otp'` / `'totp'` and carries
/// the inputs to replay (`email`/`password`, `email`/`code`, or `tempToken`/
/// `code`).
///
/// - Accept → re-obtain a FRESH Turnstile token (prior tokens are single-use),
///   replay the flow with [agreements], then navigate on success.
/// - Reject → return to `/login`; no session is ever established from this
///   page.
class ConsentGatePage extends HookConsumerWidget {
  static const sName = 'consent';

  final List<AgreementView> agreements;
  final Map<String, dynamic> originalFlow;

  const ConsentGatePage({
    super.key,
    required this.agreements,
    required this.originalFlow,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final loading = useState<bool>(false);

    String errorForKind(AuthErrorKind kind) {
      switch (kind) {
        case AuthErrorKind.rateLimited:
          return l10n.rateLimited;
        case AuthErrorKind.turnstileFailed:
          return l10n.turnstileFailed;
        case AuthErrorKind.sessionExpired:
          return l10n.sessionExpired;
        default:
          return l10n.unexpectedError(kind.name);
      }
    }

    /// Maps UI [AgreementView]s back to the wire [AuthConsentAgreement] the
    /// Herald accept flow expects.
    List<AuthConsentAgreement> toWire() {
      return agreements
          .map(
            (a) => AuthConsentAgreement(
              (b) => b
                ..agreementType = a.agreementType
                ..versionId = a.id,
            ),
          )
          .toList(growable: false);
    }

    Future<Object> replay() async {
      final notifier = ref.read(authStateProvider.notifier);
      final wire = toWire();
      final kind = originalFlow['kind'];
      switch (kind) {
        case 'password':
          final email = (originalFlow['email'] as String?) ?? '';
          final password = (originalFlow['password'] as String?) ?? '';
          final turnstileToken = await ref
              .read(turnstileServiceProvider)
              .obtainToken();
          return notifier.loginWithPassword(
            email: email,
            password: password,
            turnstileToken: turnstileToken,
            agreements: wire,
          );
        case 'email-otp':
          final email = (originalFlow['email'] as String?) ?? '';
          final turnstileToken = await ref
              .read(turnstileServiceProvider)
              .obtainToken();
          if (originalFlow['stage'] == 'send') {
            return notifier.sendEmailOtp(
              email: email,
              turnstileToken: turnstileToken,
              agreements: wire,
            );
          }
          final code = (originalFlow['code'] as String?) ?? '';
          return notifier.loginWithEmailOtp(
            email: email,
            code: code,
            turnstileToken: turnstileToken,
            agreements: wire,
          );
        case 'totp':
          final tempToken = (originalFlow['tempToken'] as String?) ?? '';
          final code = originalFlow['code'] as String?;
          final backupCode = originalFlow['backupCode'] as String?;
          // TOTP replay does not take a Turnstile token (the session is already
          // half-established via tempToken); the notifier signature has no
          // turnstile param on verifyTotp.
          return notifier.verifyTotp(
            tempToken: tempToken,
            code: code,
            backupCode: backupCode,
            agreements: wire,
          );
        default:
          // Unknown originalFlow shape — surface a generic failure without
          // calling the repository.
          return AuthFailure(
            AuthError(AuthErrorKind.network, 'unknown originalFlow.kind'),
          );
      }
    }

    Future<void> accept() async {
      if (loading.value) return;
      loading.value = true;
      try {
        final result = await replay();
        switch (result) {
          case SendEmailOtpResult(:final sent, :final expiresInSeconds):
            if (sent) {
              if (context.mounted) {
                context.go(
                  '/login',
                  extra: {
                    'email': (originalFlow['email'] as String?) ?? '',
                    'emailOtpSent': true,
                    'emailOtpExpiresInSeconds': expiresInSeconds,
                    'returnTo': originalFlow['returnTo'] as String?,
                  },
                );
              }
            } else if (result.agreements != null) {
              SmartDialog.showToast(l10n.consentRequired);
            } else if (result.error case final error?) {
              SmartDialog.showToast(errorForKind(error.kind));
            }
          case AuthSuccess():
            if (context.mounted) {
              context.go(
                safeAuthDestination(originalFlow['returnTo'] as String?),
              );
            }
          case AuthConsentRequired():
            // Server still requires consent (shouldn't happen after accept);
            // stay on the page so the user can retry.
            SmartDialog.showToast(l10n.consentRequired);
          case AuthRequiresTotp():
            if (context.mounted) context.go('/login');
          case AuthFailure(:final error):
            if (error.kind == AuthErrorKind.sessionExpired) {
              SmartDialog.showToast(l10n.sessionExpired);
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
      appBar: AppBar(title: Text(l10n.consentTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.consentRequired,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < agreements.length; i++)
                _AgreementCard(agreement: agreements[i]),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: const ValueKey('consentAcceptButton'),
                  onPressed: loading.value ? null : accept,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    disabledBackgroundColor: Colors.blueAccent.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  child: Text(
                    l10n.consentAccept,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: const ValueKey('consentRejectButton'),
                  onPressed: loading.value ? null : () => context.go('/login'),
                  child: Text(l10n.consentReject),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One agreement card: title, optional summary, optional external link. The
/// link opens a lightweight [WebView] (design §4.4.2: "render externalUrl as a
/// tappable link to webview_flutter ... do NOT auto-open"). The WebView is
/// pushed via the root [Navigator] (not goRouter) to stay out of the route
/// table and the anonymous-path whitelist.
class _AgreementCard extends StatelessWidget {
  const _AgreementCard({required this.agreement});

  final AgreementView agreement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(agreement.title, style: theme.textTheme.titleMedium),
            if (agreement.summary != null && agreement.summary!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(agreement.summary!, style: theme.textTheme.bodyMedium),
            ],
            if (agreement.externalUrl != null &&
                agreement.externalUrl!.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                key: ValueKey('consentLink_${agreement.id}'),
                onTap: () => _openUrl(context, agreement.externalUrl!),
                child: Text(
                  agreement.externalUrl!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openUrl(BuildContext context, String url) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => AgreementWebViewPage(url: url, title: agreement.title),
      ),
    );
  }
}
