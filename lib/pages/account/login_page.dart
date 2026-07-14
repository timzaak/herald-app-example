import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../util/validator.dart';
import '../../util/turnstile_util.dart';
import '../../l10n/app_localizations.dart';

import 'password_page.dart';
import 'password_type.dart';

class LoginPage extends HookConsumerWidget {
  static const sName = 'login';

  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final emailController = useTextEditingController();
    final codeController = useTextEditingController();
    final passwordController = useTextEditingController();
    final seconds = useState<int?>(null);
    final agreeDeal = useState<bool>(false);
    final tabController = useTabController(initialLength: 2, initialIndex: 0);
    final timer = useRef<Timer?>(null);

    useEffect(() {
      return () {
        timer.value?.cancel();
      };
    }, []);

    void _getCode() async {
      if (seconds.value == null) {
        var v = validateEmail(emailController.text.trim());
        if (v != null) {
          SmartDialog.showToast(v);
        }
        seconds.value = 60;
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
    }

    void _handleLogin() async {
      final token = await getTurnstileToken();
      if (token == null) {
        SmartDialog.showToast(l10n.loginFailed('Captcha verification failed'));
        return;
      }

      if (formKey.currentState?.validate() == true) {
        if (agreeDeal.value) {
          if (tabController.index == 1) {
            // TODO: 执行验证码登录（使用 emailController/codeController，调用后端接口）
            SmartDialog.showToast(l10n.loginSuccess);
          } else {
            // TODO: 执行密码登录（使用 emailController/passwordController，调用后端接口）
            SmartDialog.showToast(l10n.loginSuccess);
          }
        } else {
          SmartDialog.showToast(l10n.pleaseAgreeToTerms);
        }
      }
    }

    void _goPdf(String name, String path) {
      // Navigator.of(context).pushNamed(PdfViewerPage.sName,
      //     arguments: PdfViewerPageArg(url: '???', name: name));
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
                    TabBar(
                      controller: tabController,
                      tabs: [
                        Tab(text: l10n.passwordLogin),
                        Tab(text: l10n.verificationCodeLogin)
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
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
                        children: [
                          TextFormField(
                            controller: passwordController,
                            obscureText: true,
                            keyboardType: TextInputType.visiblePassword,
                            decoration: InputDecoration(
                              hintText: l10n.enterPassword,
                            ),
                            validator: validatePassword,
                          ),
                          TextFormField(
                            controller: codeController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: l10n.enterVerificationCode,
                              suffixIcon: TextButton(
                                onPressed: _getCode,
                                child: Text(
                                  seconds.value == null
                                      ? l10n.getVerificationCode
                                      : l10n.resendCode(seconds.value.toString()),
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
                                  onChanged:
                                      (_) => agreeDeal.value = !agreeDeal.value,
                                ),
                              ),
                            ),
                            TextSpan(text: '${l10n.iHaveReadAndAgree} '),
                            TextSpan(
                              text: l10n.userAgreement,
                              recognizer:
                                  TapGestureRecognizer()
                                    ..onTap =
                                        () => _goPdf(l10n.userAgreement, 'user_deal.pdf'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(text: ' ${l10n.and} '),
                            TextSpan(
                              text: l10n.privacyPolicy,
                              recognizer:
                                  TapGestureRecognizer()
                                    ..onTap =
                                        () => _goPdf(
                                          l10n.privacyPolicy,
                                          'privacy_protect.pdf',
                                        ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(text: '，${l10n.unregisteredEmailWillCreateAccount}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _handleLogin,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: Text(
                          l10n.login,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
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
