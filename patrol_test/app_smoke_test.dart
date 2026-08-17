// 最简 Patrol 冒烟测试：验证 app 能启动并渲染未登录入口。
// 非用户故事 demo，不映射 US ID；仅验证启动 + 路由守卫（未登录 → /login）。
//
// 不调用 main()：其内部 VersionService.checkVersion() 依赖网络与 SharedPreferences，
// 会引入不稳定副作用，改为直接 pumpWidgetAndSettle(MyApp())。
//
// 运行（需 Android/iOS 设备 + patrol_cli，与 pubspec 锁定的 patrol 版本配套）：
//   dart pub global activate patrol_cli
//   patrol test --target patrol_test/app_smoke_test.dart -d <device-id>

import 'package:app/main.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('app 启动后未登录用户进入登录页', ($) async {
    // 显式 seed 未登录态：appRouter 守卫直接读 top-level heraldContainer
    // （lib/main.dart），不读 widget 树 scope；用同一容器包裹 widget 树以对齐
    // 生产 composition root（UncontrolledProviderScope(container: heraldContainer)），
    // seed 表明未登录是确定输入而非默认巧合（Rule 8：断言意图）。
    heraldContainer.read(authStateProvider.notifier).seedAuthenticated(false);
    await $.pumpWidgetAndSettle(
      UncontrolledProviderScope(container: heraldContainer, child: const MyApp()),
    );

    expect($(#loginEmailField), findsOneWidget, reason: '未登录用户应被路由守卫重定向到登录页');
    expect($(#loginSubmitButton), findsOneWidget, reason: '登录页应提供登录提交按钮');
  });
}
