// 最简 Patrol 冒烟测试：验证 app 能启动并渲染首页初始数据。
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
  patrolTest(
    'app 启动后首页显示 Infinite Scroll 与初始列表项',
    ($) async {
      await $.pumpWidgetAndSettle(const ProviderScope(child: MyApp()));

      expect($('Infinite Scroll'), findsOneWidget,
          reason: '首页 AppBar 标题应为 Infinite Scroll');
      expect($('Item 1'), findsOneWidget, reason: '初始数据加载后应显示 Item 1');
    },
  );
}
