// 最简 Patrol 冒烟测试：验证 app 能启动并渲染未登录入口。
//
// 不调用 main()：其内部 VersionService.checkVersion() 依赖网络与 SharedPreferences，
// 会引入不稳定副作用，改为直接 pumpWidgetAndSettle(MyApp())。
//
// 运行（需 Android/iOS 设备 + patrol_cli）：
//   dart pub global activate patrol_cli
//   patrol test --target patrol_test/app_smoke_test.dart -d <device-id>

import 'package:app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('app 启动后未登录用户进入登录页', ($) async {
    await $.pumpWidgetAndSettle(const ProviderScope(child: MyApp()));

    expect($(#loginEmailField), findsOneWidget, reason: '未登录用户应被路由守卫重定向到登录页');
    expect($(#loginSubmitButton), findsOneWidget, reason: '登录页应提供登录提交按钮');
  });
}
