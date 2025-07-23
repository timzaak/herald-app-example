import 'dart:async';

import 'package:app/api/dio_util.dart';
import 'package:app/services/version_service.dart';
import 'package:app/services/fcm_service.dart';
import 'package:app/services/analytics_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:logging/logging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import './routes.dart';
import 'l10n/app_localizations.dart';

void main() {

  FlutterError.onError = (FlutterErrorDetails details) async {
    Zone.current.handleUncaughtError(details.exception, details.stack!);
  };

  runZonedGuarded<Future<Null>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // 检查 是否时网页
    if (!kIsWeb) {
      await Firebase.initializeApp();
      
      // 设置后台消息处理器
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      
      // 初始化FCM
      await FCMService.initialize();
      
      // 初始化Firebase Analytics
      await AnalyticsService.initialize();
      
      // 检查版本更新
      await VersionService().checkVersion();
    }
    initLogger();
    runApp(const MyApp());
    ///屏幕刷新率和显示率不一致时的优化，必须挪动到 runApp 之后
    GestureBinding.instance.resamplingEnabled = true;
  }, (exception, stackTrace) async {
    // FlutterBugly.init(
    //   androidAppId: "your android app id",
    //   iOSAppId: "your iOS app id",
    // );
    //FlutterBugly.uploadException(message: exception.toString(),detail: stackTrace.toString());
  });
}

initLogger() {
  if(!kReleaseMode){
    Logger.root.level = Level.FINE;
    DioUtil.getInstance().openLog();
  } else {
    Logger.root.level = Level.WARNING;
  }

  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  Logger.root.fine('Starting app');
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) {
        return MaterialApp.router(
          title: 'Space',
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          debugShowCheckedModeBanner: kDebugMode,
          theme: ThemeData(
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.white,
              iconTheme: IconThemeData(color: Colors.blue),
              elevation: 0,
            ),
            scaffoldBackgroundColor: Colors.white,
            primaryColor: Colors.blue,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            colorScheme:
            ColorScheme.fromSwatch().copyWith(secondary: Colors.white),
          ),
          routerConfig: appRouter,
          // 添加Firebase Analytics观察者
          navigatorObservers: [
            if (!kIsWeb) AnalyticsService.observer,
          ],
        );
      },
    );

  }
}
