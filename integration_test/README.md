# integration_test

Flutter 官方 `integration_test` 用例目录，覆盖重要用户用例（登录、扫码、视频播放等）的端到端集成测试。

## 运行

```bash
flutter devices
flutter test integration_test/<file>_test.dart -d <device-id>
```

Web 目标需配合 ChromeDriver 与 `flutter drive`，详见
t-tool `guides/flutter/integration-testing.md`。

## Finder 规则

优先级：稳定 `ValueKey` > Semantics label > 稳定文案 > icon/type。
关键交互控件使用 `<domain>-<entity>-<action|field>` 命名的 `ValueKey`，
例如 `login-email-input`、`login-submit-button`。
