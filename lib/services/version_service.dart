import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_upgrade_version/flutter_upgrade_version.dart';

class VersionService {
  static final VersionService _instance = VersionService._internal();
  factory VersionService() => _instance;
  VersionService._internal();

  bool _hasNewVersion = false;
  bool get hasNewVersion => _hasNewVersion;

  Future<void> checkVersion() async {
    if (Platform.isAndroid) {
      InAppUpdateManager manager = InAppUpdateManager();
      AppUpdateInfo? appUpdateInfo = await manager.checkForUpdate();
      if (appUpdateInfo == null) return; //Exception
      if (appUpdateInfo.immediateAllowed) {
        String? message = await manager.startAnUpdate(
          type: AppUpdateType.immediate,
        );

        ///message return null when run update success
      } else if (appUpdateInfo.flexibleAllowed) {
        _hasNewVersion = true;
      } else {
        debugPrint(
          'Update available. Immediate & Flexible Update Flow not allow',
        );
      }
    } else if (Platform.isIOS) {
      var _packageInfo = await PackageManager.getPackageInfo();
      VersionInfo? _versionInfo2 = await UpgradeVersion.getiOSStoreVersion(
        packageInfo: _packageInfo,
      );
      if (_versionInfo2.canUpdate) {
        _hasNewVersion = true;
      }
    }
  }

  Future<void> showUpgradeDialog() async {
    if (kIsWeb) return;
  }
}
