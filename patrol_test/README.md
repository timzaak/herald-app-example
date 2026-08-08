# patrol_test

Patrol 集成测试目录，覆盖重要用户用例与原生 UI 交互（权限弹窗、WebView、通知等）。

Patrol 只支持 **Android / iOS**，不支持 desktop/web。

## 前置准备

```bash
# 1. 安装 patrol_cli（与 patrol 包配套，见 pub.dev compatibility table）
dart pub global activate patrol_cli

# 2. 确认环境正常
patrol doctor

# 3. 确认设备已连接
flutter devices
```

确保 `~/.pub-cache/bin`（或 `%LOCALAPPDATA%\Pub\Cache\bin`）在 PATH 中，否则 `patrol` 命令找不到。

## 运行

```bash
# 单个测试文件
patrol test --target patrol_test/app_smoke_test.dart -d <device-id>

# 全部
patrol test
```

## 与 integration_test/ 的分工

| 目录 | 框架 | 用途 | 需要设备 |
|---|---|---|---|
| `patrol_test/` | Patrol (`patrolTest`) | 含原生 UI 自动化（权限、通知、WebView） | Android/iOS 真机或模拟器 |
| `integration_test/` | 官方 `integration_test` | 标准 Flutter 集成测试（无原生 UI 操作） | 任意 Flutter 平台 |

按 t-tool `guides/flutter/integration-testing.md` 约定，原生 UI 流程优先用 Patrol。

## Finder 规则

优先级：稳定 `ValueKey` > Semantics label > 稳定文案 > icon/type。
关键交互控件使用 `<domain>-<entity>-<action|field>` 命名的 `ValueKey`，
例如 `login-email-input`、`login-submit-button`。

## 测试命名约束

`patrolTest` 的描述字符串**不得含 `/`**。AndroidX Test Orchestrator 用完整测试名
（分组路径 + 描述）作为输出文件名，`/` 会被当作路径分隔符触发
`IllegalArgumentException: contains a path separator`，导致整个 instrumentation 崩溃、
`Total: 0`。需要并列时用顿号「、」或「与」代替斜杠。
