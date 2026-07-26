import 'dart:async';

import 'package:app/api/dio_util.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:app/services/version_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import './routes.dart';
import 'l10n/app_localizations.dart';

/// Top-level Riverpod container (design §4.1 / frozen contract).
///
/// This is a top-level `final` so `lib/routes.dart`'s redirect guard (FL-D03)
/// can read login state synchronously via
/// `heraldContainer.read(authStateProvider).status`. Seeded with the startup
/// `checkStatus()` result before [runApp].
final ProviderContainer heraldContainer = ProviderContainer();

void main() {
  FlutterError.onError = (FlutterErrorDetails details) async {
    Zone.current.handleUncaughtError(details.exception, details.stack!);
  };

  runZonedGuarded<Future<Null>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // 检查 是否时网页
      if (!kIsWeb) {
        // 检查版本更新
        await VersionService().checkVersion();
      }
      initLogger();

      // Herald session bootstrap (design §4.1, FL-D02). The ApiClient singleton
      // is constructed lazily by apiClientProvider using DioUtil.dio (the shared
      // Dio with DioAuthInterceptor mounted) and an empty interceptors list so
      // the generated client skips its default BearerAuthInterceptor. Reading it
      // here forces construction before any auth call and matches the frozen
      // FL-D01 contract: ApiClient(dio: DioUtil.dio, basePathOverride:
      // Settings.heraldBaseUrl, interceptors: []).
      //
      // Explicitly construct the shared Dio first: DioUtil.dio is a bare Dio()
      // until _init() runs (which mounts baseUrl + DioAuthInterceptor and calls
      // attachDio). Do not rely on initLogger()'s openLog() side effect to do it.
      DioUtil.getInstance();
      heraldContainer.read(apiClientProvider);

      final bindings = buildSessionBindings(heraldContainer);
      DioUtil.bindAuth(
        tokenStore: heraldContainer.read(tokenStoreProvider),
        refreshFn: bindings.refreshFn,
        onSessionEnd: bindings.onSessionEnd,
      );

      // Startup login-state probe. checkStatus never throws; 401 (after the
      // interceptor's single refresh attempt has failed) ⇒ false.
      final authenticated = await heraldContainer
          .read(heraldAuthRepositoryProvider)
          .checkStatus();
      heraldContainer
          .read(authStateProvider.notifier)
          .seedAuthenticated(authenticated);

      runApp(
        UncontrolledProviderScope(
          container: heraldContainer,
          child: const MyApp(),
        ),
      );

      ///屏幕刷新率和显示率不一致时的优化，必须挪动到 runApp 之后
      GestureBinding.instance.resamplingEnabled = true;
    },
    (exception, stackTrace) async {
      // FlutterBugly.init(
      //   androidAppId: "your android app id",
      //   iOSAppId: "your iOS app id",
      // );
      //FlutterBugly.uploadException(message: exception.toString(),detail: stackTrace.toString());
    },
  );
}

initLogger() {
  if (!kReleaseMode) {
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
            colorScheme: ColorScheme.fromSwatch().copyWith(
              secondary: Colors.white,
            ),
          ),
          routerConfig: appRouter,
        );
      },
    );
  }
}
