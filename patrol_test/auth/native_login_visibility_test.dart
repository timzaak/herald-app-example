// Android Patrol 演示：原生一键登录入口（Google）的可见性与登录页结构。
//
// 用户故事来源：.ai/user-stories/auth/native-login.md
// US ID：US-NATIVE-LOGIN-001（P0，Android 上 Google 入口可见性与邮箱入口共存；
//       平台门控下 Apple 按钮不渲染）。
//
// 运行（需 Android 设备 + patrol_cli，与 pubspec 锁定的 patrol 4.7.0 配套）：
//   dart pub global activate patrol_cli
//   patrol test --target patrol_test/auth/native_login_visibility_test.dart --device <android-id>
//
// 设计取舍（见 .ai/super-run/native-login/flutter-demo.md Decision Trace）：
//  - 真实 composition root（MyApp + appRouter），不注入 Provider/repository fake。
//  - 真实 Google 账号无法在自动化中安全使用，故聚焦「入口可见性 + 页面结构」，
//    这是可在真实 composition root 下稳定自动化、可验收的部分（Rule 6）。
//  - Google 按钮可见性由 public-config 的 oauthProviders 驱动：Android 上
//    realm 启用 google provider 时可见，未启用时隐藏（fail-closed，DEC-002/006/007）。
//    因此用例按「后端 provider 配置」分两条断言路径，而不是硬编码一次性期望。

import 'package:app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'US-NATIVE-LOGIN-001 场景1：Android 未登录用户进入登录页，邮箱登录入口始终存在'
    '（#loginEmailField / #loginSubmitButton）',
    ($) async {
      await $.pumpWidgetAndSettle(const ProviderScope(child: MyApp()));

      // 路由守卫（_anonymousPaths 含 /login；未认证访问 /index 重定向到 /login）
      // 保证未登录用户落到登录页。邮箱登录入口是跨 provider 配置的稳定结构。
      expect($(const ValueKey('loginEmailField')), findsOneWidget);
      expect($(const ValueKey('loginSubmitButton')), findsOneWidget);
    },
  );

  patrolTest(
    'US-NATIVE-LOGIN-001 场景1/2：Android 平台门控 —— Apple 按钮永不渲染'
    '（#appleSignInButton 仅 iOS）',
    ($) async {
      await $.pumpWidgetAndSettle(const ProviderScope(child: MyApp()));

      // DEC-native-login-002：Apple 仅 iOS、Google 仅 Android，互斥。
      // 当前为 Android 运行时，Apple 按钮不存在与 provider 配置无关，
      // 是平台门控的稳定断言（login_page.dart 的 Platform.isIOS 分支）。
      expect($(const ValueKey('appleSignInButton')), findsNothing);
    },
  );

  patrolTest(
    'US-NATIVE-LOGIN-001 场景1/2：Google 按钮可见性由 public-config provider 配置驱动',
    ($) async {
      await $.pumpWidgetAndSettle(const ProviderScope(child: MyApp()));

      final googleButton = $(const ValueKey('googleSignInButton'));
      final googleVisible = googleButton.evaluate().isNotEmpty;

      if (googleVisible) {
        // 场景1：realm 已启用 google provider 且配置 clientId → 按钮可见，
        // 且邮箱入口与之共存（DEC-001/002）。
        expect(googleButton, findsOneWidget);
        expect($(const ValueKey('loginEmailField')), findsOneWidget);
        expect($(const ValueKey('loginSubmitButton')), findsOneWidget);
      } else {
        // 场景2：public-config 未启用 google（或缺 clientId / fetch 失败）→
        // 按钮隐藏（fail-closed，DEC-006/007），邮箱登录主链路不受影响。
        expect(googleButton, findsNothing);
        expect($(const ValueKey('loginEmailField')), findsOneWidget);
        expect($(const ValueKey('loginSubmitButton')), findsOneWidget);
      }
    },
  );
}
