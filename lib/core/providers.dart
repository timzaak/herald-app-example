import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/version_service.dart';

/// 应用包信息（版本号等），全局只读。
///
/// Web 平台无法通过 [PackageInfo.fromPlatform] 获取真实信息，返回占位值。
final packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  if (kIsWeb) {
    return PackageInfo(
      appName: '',
      packageName: '',
      version: '',
      buildNumber: '',
      buildSignature: '',
      installerStore: null,
    );
  }
  return PackageInfo.fromPlatform();
});

/// 注意：`hasNewVersion` 是 `checkVersion()` 异步执行后写入服务内部状态的，
/// provider 不会自动感知其变化 —— 调用方需在 `checkVersion()` 之后自行刷新 UI。
final versionServiceProvider = Provider<VersionService>((ref) {
  return VersionService();
});
