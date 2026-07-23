import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/settings.dart';
import 'dio_auth_interceptor.dart';
import 'dio_interceptors.dart';
import '../services/auth/token_store.dart';

class DioUtil {
  static DioUtil? _instance;
  static Dio _dio = Dio();
  static Dio get dio => _dio;

  /// The Bearer session interceptor (design §4.1 single Authorization source).
  /// Mounted on [_dio] during [_init] with no-op defaults so this file compiles
  /// standalone; FL-D02's main.dart wiring calls [bindAuth] to swap in the
  /// provider-backed TokenStore / refreshFn / onSessionEnd.
  static final DioAuthInterceptor authInterceptor = DioAuthInterceptor(
    TokenStore(),
    () async => false,
    () async {},
  );

  DioUtil._internal() {
    _instance = this;
    _instance!._init();
  }

  factory DioUtil() => _instance ?? DioUtil._internal();

  static DioUtil getInstance() {
    return _instance ?? DioUtil._internal();
  }

  /// FL-D02 (main.dart wiring) calls this to inject the real TokenStore,
  /// refresh callback, and session-end callback into the mounted interceptor.
  static void bindAuth({
    required TokenStore tokenStore,
    required Future<bool> Function() refreshFn,
    required Future<void> Function() onSessionEnd,
  }) {
    authInterceptor.rebind(
      tokenStore: tokenStore,
      refreshFn: refreshFn,
      onSessionEnd: onSessionEnd,
    );
  }

  _init() {
    /// 初始化基本选项
    BaseOptions options = BaseOptions(
      baseUrl: Settings.heraldBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    );

    /// 初始化dio
    _dio = Dio(options);

    authInterceptor.attachDio(_dio);

    /// 添加拦截器
    _dio.interceptors.add(DioInterceptors());

    /// 添加 Bearer 会话拦截器（单一 Authorization 来源，design §4.1）
    _dio.interceptors.add(authInterceptor);

    /// 开启日志打印
  }

  void openLog() {
    _dio.interceptors.add(PrettyDioLogger(responseBody: true));
  }
}
