import 'package:flutter/foundation.dart';
import 'package:upgrader/upgrader.dart';

class VersionService {
  static final VersionService _instance = VersionService._internal();
  factory VersionService() => _instance;
  VersionService._internal();

  /// 复用 upgrader 包的全局单例，使 UpgradeAlert widget（也默认用该单例）
  /// 与本服务的检测结果共享同一状态，避免重复查询商店。
  Upgrader get upgrader => Upgrader.sharedInstance;

  bool _hasNewVersion = false;
  bool get hasNewVersion => _hasNewVersion;

  /// 查询商店最新版本并比对，结果写入 [_hasNewVersion]。
  /// 跨平台：Android 走 Google Play 爬取，iOS 走 iTunes Lookup。
  /// 静默失败：网络异常或商店不可达时不阻塞调用方。
  Future<void> checkVersion() async {
    if (kIsWeb) return;
    try {
      await upgrader.initialize();
      _hasNewVersion = upgrader.isUpdateAvailable();
    } catch (_) {
      // 商店查询失败时不改变已有状态，避免误报
    }
  }

  Future<void> showUpgradeDialog() async {
    // 升级 UI 由 main.dart 中包裹根 widget 的 UpgradeAlert 接管，
    // 此处保留空实现以兼容 my_page.dart 现有调用。
    if (kIsWeb) return;
  }
}
