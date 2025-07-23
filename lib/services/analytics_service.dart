import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static FirebaseAnalyticsObserver observer = FirebaseAnalyticsObserver(analytics: _analytics);

  // 初始化 Analytics
  static Future<void> initialize() async {
    // 设置用户属性
    await setUserProperties(userID: null, userRole: null);
    
    // 设置分析收集启用/禁用
    await setAnalyticsCollectionEnabled(true);
  }

  // 设置分析收集启用/禁用
  static Future<void> setAnalyticsCollectionEnabled(bool enabled) async {
    await _analytics.setAnalyticsCollectionEnabled(enabled);
  }

  // 设置用户属性
  static Future<void> setUserProperties({String? userID, String? userRole}) async {
    if (userID != null) {
      await _analytics.setUserId(id: userID);
    }
    
    if (userRole != null) {
      await _analytics.setUserProperty(name: 'user_role', value: userRole);
    }
  }

  // 记录登录事件
  static Future<void> logLogin({String? loginMethod}) async {
    await _analytics.logLogin(loginMethod: loginMethod);
  }

  // 记录注册事件
  static Future<void> logSignUp({String? signUpMethod}) async {
    await _analytics.logSignUp(signUpMethod: signUpMethod);
  }

  // 记录页面访问
  static Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    await _analytics.logScreenView(
      screenName: screenName,
      screenClass: screenClass,
    );
  }

  // 记录搜索事件
  static Future<void> logSearch({required String searchTerm}) async {
    await _analytics.logSearch(searchTerm: searchTerm);
  }

  // 记录自定义事件
  static Future<void> logEvent({
    required String name,
    Map<String, dynamic>? parameters,
  }) async {
    await _analytics.logEvent(
      name: name,
      parameters: parameters,
    );
  }

  // 记录内容查看事件
  static Future<void> logViewContent({
    required String contentType,
    required String itemId,
    String? itemName,
  }) async {
    await _analytics.logViewItem(
      items: [
        AnalyticsEventItem(
          itemId: itemId,
          itemName: itemName,
          itemCategory: contentType,
        ),
      ],
    );
  }

  // 记录分享事件
  static Future<void> logShare({
    required String contentType,
    required String itemId,
    String? method,
  }) async {
    await _analytics.logShare(
      contentType: contentType,
      itemId: itemId,
      method: method,
    );
  }

  // 记录添加到购物车事件
  static Future<void> logAddToCart({
    required String itemId,
    required String itemName,
    required double price,
    required int quantity,
  }) async {
    await _analytics.logAddToCart(
      items: [
        AnalyticsEventItem(
          itemId: itemId,
          itemName: itemName,
          price: price,
          quantity: quantity,
        ),
      ],
      value: price * quantity,
      currency: 'CNY',
    );
  }

  // 记录购买事件
  static Future<void> logPurchase({
    required String transactionId,
    required double value,
    required List<AnalyticsEventItem> items,
    String currency = 'CNY',
  }) async {
    await _analytics.logPurchase(
      transactionId: transactionId,
      value: value,
      currency: currency,
      items: items,
    );
  }

  // 记录应用内错误
  static Future<void> logAppError({
    required String errorCode,
    required String errorMessage,
  }) async {
    await _analytics.logEvent(
      name: 'app_error',
      parameters: {
        'error_code': errorCode,
        'error_message': errorMessage,
      },
    );
  }
}