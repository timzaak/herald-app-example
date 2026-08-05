import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_providers.dart';
import '../../services/auth/auth_error.dart';
import '../../services/auth/auth_redirect.dart';
import '../../services/auth/auth_result.dart';
import '../../util/validator.dart';
import '../../l10n/app_localizations.dart';

import 'legal_agreement_page.dart';
import 'password_page.dart';
import 'password_type.dart';

class LoginPage extends HookConsumerWidget {
  static const sName = 'login';

  final String initialEmail;
  final bool initialEmailOtpSent;
  final int? initialEmailOtpExpiresInSeconds;
  final String? initialReturnTo;

  const LoginPage({
    super.key,
    this.initialEmail = '',
    this.initialEmailOtpSent = false,
    this.initialEmailOtpExpiresInSeconds,
    this.initialReturnTo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    // Debug-only convenience: pre-fill the demo account from the Herald README
    // so manual sign-in during development doesn't require typing it every time.
    // Release builds keep the empty defaults.
    final emailController = useTextEditingController(
      text: initialEmail.isEmpty && kDebugMode
          ? 'admin@fornetcode.com'
          : initialEmail,
    );
    final codeController = useTextEditingController();
    final passwordController = useTextEditingController(
      text: kDebugMode ? 'Herald@2026Admin' : '',
    );
    final seconds = useState<int?>(null);
    final agreeDeal = useState<bool>(false);
    final loading = useState<bool>(false);
    final emailOtpEnabled =
        ref.watch(emailOtpEnabledProvider).value ?? initialEmailOtpSent;
    final registrationEnabled =
        ref.watch(registrationEnabledProvider).value == true;
    final nativeAvailability =
        ref.watch(nativeLoginAvailabilityProvider).value ??
        const NativeLoginAvailability();
    final tabController = useTabController(
      initialLength: 2,
      initialIndex: initialEmailOtpSent ? 1 : 0,
    );
    final timer = useRef<Timer?>(null);

    useEffect(() {
      if (initialEmailOtpSent) {
        seconds.value = initialEmailOtpExpiresInSeconds ?? 60;
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
      return () {
        timer.value?.cancel();
      };
    }, []);

    /// Maps an [AuthErrorKind] to a user-facing localized message.
    String errorForKind(AuthErrorKind kind) {
      switch (kind) {
        case AuthErrorKind.invalidCredentials:
          return l10n.loginFailed(l10n.enterPassword);
        case AuthErrorKind.accountNotActivated:
          return l10n.accountNotActivated;
        case AuthErrorKind.emailNotRegistered:
          return l10n.emailOtpNotRegistered;
        case AuthErrorKind.verificationCodeInvalid:
          return l10n.verificationCodeInvalid;
        case AuthErrorKind.consentRequired:
          return l10n.consentRequired;
        case AuthErrorKind.rateLimited:
          return l10n.rateLimited;
        case AuthErrorKind.turnstileFailed:
          return l10n.turnstileFailed;
        case AuthErrorKind.configMissing:
          return l10n.unexpectedError('config');
        case AuthErrorKind.sessionExpired:
          return l10n.sessionExpired;
        case AuthErrorKind.network:
          return l10n.loginFailed(l10n.unexpectedError('network'));
        case AuthErrorKind.emailAlreadyRegistered:
        case AuthErrorKind.resetCodeInvalid:
          return l10n.unexpectedError(kind.name);
        case AuthErrorKind.providerUnavailable:
          return l10n.loginFailed(l10n.unexpectedError('provider'));
        case AuthErrorKind.serviceUnavailable:
          return l10n.loginServiceUnavailable;
        case AuthErrorKind.cancelled:
          return l10n.nativeSignInCancelled;
      }
    }

    /// Reads the optional `returnTo` query param set by the router redirect
    /// guard (design §4.4.3). Null → fall back to `/index`.
    String? returnTo() =>
        GoRouterState.of(context).uri.queryParameters['returnTo'] ??
        initialReturnTo;

    void startCountdown([int duration = 60]) {
      seconds.value = duration;
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

    Future<void> getCode() async {
      if (loading.value) return;
      if (seconds.value != null) return; // still counting down
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
        final result = await ref
            .read(authStateProvider.notifier)
            .sendEmailOtp(email: email, turnstileToken: turnstileToken);
        if (!context.mounted) return;
        if (result.sent) {
          startCountdown(result.expiresInSeconds ?? 60);
          return;
        }
        if (result.agreements != null) {
          // consent_required on send — route to /consent and replay email-otp.
          context.go(
            '/consent',
            extra: {
              'agreements': result.agreements,
              'originalFlow': {
                'kind': 'email-otp',
                'stage': 'send',
                'email': email,
                'returnTo': returnTo(),
              },
            },
          );
          return;
        }
        final error = result.error;
        if (error != null) {
          SmartDialog.showToast(errorForKind(error.kind));
        }
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    /// Native one-tap login (Apple on iOS / Google on Android). The native
    /// direct-session path never returns totp/consent branches (DEC-native-login-005),
    /// so only AuthSuccess / AuthFailure are handled.
    Future<void> submitNative(Future<AuthResult> Function() run) async {
      if (loading.value) return;
      loading.value = true;
      try {
        final result = await run();
        if (!context.mounted) return;
        switch (result) {
          case AuthSuccess():
            context.go(safeAuthDestination(returnTo()));
          case AuthRequiresTotp():
          case AuthConsentRequired():
            // Not produced by the native direct-session path; stay put.
            break;
          case AuthFailure(:final error):
            SmartDialog.showToast(errorForKind(error.kind));
        }
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    Future<void> submitPassword(String email, String password) async {
      final turnstileToken = await ref
          .read(turnstileServiceProvider)
          .obtainToken();
      final result = await ref
          .read(authStateProvider.notifier)
          .loginWithPassword(
            email: email,
            password: password,
            turnstileToken: turnstileToken,
          );
      if (!context.mounted) return;
      switch (result) {
        case AuthSuccess():
          context.go(safeAuthDestination(returnTo()));
        case AuthRequiresTotp(:final tempToken, :final secondFactors):
          context.go(
            '/totp-verify',
            extra: {
              'tempToken': tempToken,
              'secondFactors': secondFactors,
              'returnTo': returnTo(),
            },
          );
        case AuthConsentRequired(:final agreements):
          context.go(
            '/consent',
            extra: {
              'agreements': agreements,
              'originalFlow': {
                'kind': 'password',
                'email': email,
                'password': password,
                'returnTo': returnTo(),
              },
            },
          );
        case AuthFailure(:final error):
          SmartDialog.showToast(errorForKind(error.kind));
      }
    }

    Future<void> submitEmailOtp(String email, String code) async {
      final turnstileToken = await ref
          .read(turnstileServiceProvider)
          .obtainToken();
      final result = await ref
          .read(authStateProvider.notifier)
          .loginWithEmailOtp(
            email: email,
            code: code,
            turnstileToken: turnstileToken,
          );
      if (!context.mounted) return;
      switch (result) {
        case AuthSuccess():
          context.go(safeAuthDestination(returnTo()));
        case AuthRequiresTotp(:final tempToken, :final secondFactors):
          // Not expected on the email-otp verify endpoint, but handled
          // defensively — route to /totp-verify.
          context.go(
            '/totp-verify',
            extra: {
              'tempToken': tempToken,
              'secondFactors': secondFactors,
              'returnTo': returnTo(),
            },
          );
        case AuthConsentRequired(:final agreements):
          context.go(
            '/consent',
            extra: {
              'agreements': agreements,
              'originalFlow': {
                'kind': 'email-otp',
                'stage': 'verify',
                'email': email,
                'code': code,
                'returnTo': returnTo(),
              },
            },
          );
        case AuthFailure(:final error):
          SmartDialog.showToast(errorForKind(error.kind));
      }
    }

    Future<void> handleLogin() async {
      if (loading.value) return;
      if (formKey.currentState?.validate() != true) return;
      // Agreement checkbox is required only on the password tab (item §3).
      if (tabController.index == 0 && !agreeDeal.value) {
        SmartDialog.showToast(l10n.pleaseAgreeToTerms);
        return;
      }
      loading.value = true;
      try {
        final email = emailController.text.trim();
        if (tabController.index == 0) {
          await submitPassword(email, passwordController.text);
        } else {
          await submitEmailOtp(email, codeController.text.trim());
        }
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    void openAgreement(String title, String agreementType) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              LegalAgreementPage(agreementType: agreementType, title: title),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.login)),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 26,
                  right: 26,
                  top: 0,
                  bottom: 50,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),
                    if (nativeAvailability.apple ||
                        nativeAvailability.google) ...[
                      if (nativeAvailability.apple)
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            key: const ValueKey('appleSignInButton'),
                            onPressed: loading.value
                                ? null
                                : () => submitNative(
                                    () => ref
                                        .read(authStateProvider.notifier)
                                        .loginWithApple(),
                                  ),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.black,
                              disabledBackgroundColor: Colors.black.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            child: Text(
                              l10n.signInWithApple,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      if (nativeAvailability.google) ...[
                        if (nativeAvailability.apple)
                          const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            key: const ValueKey('googleSignInButton'),
                            onPressed: loading.value
                                ? null
                                : () => submitNative(
                                    () => ref
                                        .read(authStateProvider.notifier)
                                        .loginWithGoogleOneTap(),
                                  ),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey,
                              side: const BorderSide(color: Colors.grey),
                            ),
                            child: Text(
                              l10n.signInWithGoogle,
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              l10n.orUseEmail,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (emailOtpEnabled)
                      TabBar(
                        controller: tabController,
                        tabs: [
                          Tab(text: l10n.passwordLogin),
                          Tab(text: l10n.verificationCodeLogin),
                        ],
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('loginEmailField'),
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(hintText: l10n.enterEmail),
                      validator: (text) {
                        return validateEmail(text);
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 60,
                      child: TabBarView(
                        controller: tabController,
                        physics: emailOtpEnabled
                            ? null
                            : const NeverScrollableScrollPhysics(),
                        children: [
                          TextFormField(
                            key: const ValueKey('loginPasswordField'),
                            controller: passwordController,
                            obscureText: true,
                            keyboardType: TextInputType.visiblePassword,
                            decoration: InputDecoration(
                              hintText: l10n.enterPassword,
                            ),
                            validator: validatePassword,
                          ),
                          TextFormField(
                            key: const ValueKey('loginCodeField'),
                            controller: codeController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: l10n.enterVerificationCode,
                              suffixIcon: TextButton(
                                key: const ValueKey('loginGetCodeButton'),
                                onPressed: loading.value ? null : getCode,
                                child: Text(
                                  seconds.value == null
                                      ? l10n.getVerificationCode
                                      : l10n.resendCode(
                                          seconds.value.toString(),
                                        ),
                                ),
                              ),
                            ),
                            validator: validateVerificationCode,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          GoRouter.of(context).pushNamed(
                            ChangePasswordPage.sName,
                            extra: ChangePasswordType.ForgotPassword,
                          );
                        },
                        child: Text(l10n.forgotPassword),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => agreeDeal.value = !agreeDeal.value,
                      child: Text.rich(
                        textAlign: TextAlign.start,
                        style: const TextStyle(height: 1.5, fontSize: 12),
                        TextSpan(
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Transform.scale(
                                scale: 0.7,
                                child: Checkbox(
                                  value: agreeDeal.value,
                                  shape: const CircleBorder(),
                                  visualDensity: const VisualDensity(
                                    horizontal: VisualDensity.minimumDensity,
                                    vertical: VisualDensity.minimumDensity,
                                  ),
                                  onChanged: (_) =>
                                      agreeDeal.value = !agreeDeal.value,
                                ),
                              ),
                            ),
                            TextSpan(text: '${l10n.iHaveReadAndAgree} '),
                            TextSpan(
                              text: l10n.userAgreement,
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => openAgreement(
                                  l10n.userAgreement,
                                  'terms_of_service',
                                ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(text: ' ${l10n.and} '),
                            TextSpan(
                              text: l10n.privacyPolicy,
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => openAgreement(
                                  l10n.privacyPolicy,
                                  'privacy_policy',
                                ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '，${l10n.unregisteredEmailWillCreateAccount}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        key: const ValueKey('loginSubmitButton'),
                        onPressed: loading.value ? null : handleLogin,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          disabledBackgroundColor: Colors.blueAccent.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        child: Text(
                          l10n.login,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    if (registrationEnabled) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          key: const ValueKey('loginRegisterButton'),
                          onPressed: loading.value
                              ? null
                              : () => context.go('/register'),
                          child: Text(l10n.register),
                        ),
                      ),
                    ],
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
