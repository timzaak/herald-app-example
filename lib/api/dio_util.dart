import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

// import '../config/app_config.dart';
import 'dio_interceptors.dart';
import 'dio_token_interceptor.dart';

class DioUtil {


  static DioUtil? _instance;
  static Dio _dio = Dio();
  static Dio get dio => _dio;


  DioUtil._internal() {
    _instance = this;
    _instance!._init();
  }

  factory DioUtil() => _instance ?? DioUtil._internal();

  static DioUtil getInstance() {
    return _instance ?? DioUtil._internal();
  }


  _init() {
    /// 初始化基本选项
    BaseOptions options = BaseOptions(
      baseUrl: "",
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    );

    /// 初始化dio
    _dio = Dio(options);

    DioTokenInterceptors token_interceptor = DioTokenInterceptors();

    /// 添加拦截器
    _dio.interceptors.add(DioInterceptors());

    /// 添加转换器
    // _dio.transformer = DioTransformer();

    /// 添加cookie管理器
    //_dio.interceptors.add(CookieManager(cookieJar));

    /// 刷新token拦截器(lock/unlock)
    _dio.interceptors.add(token_interceptor);

    /// 添加缓存拦截器
    //_dio.interceptors.add(DioCacheInterceptors());

    /// 开启日志打印
  }

  void openLog() {
    _dio.interceptors.add(PrettyDioLogger(responseBody: true));
  }
}