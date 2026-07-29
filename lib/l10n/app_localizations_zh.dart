// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get login => '登录';

  @override
  String get passwordLogin => '密码登录';

  @override
  String get verificationCodeLogin => '验证码登录';

  @override
  String get enterEmail => '请输入邮箱';

  @override
  String get enterPassword => '请输入密码';

  @override
  String get enterVerificationCode => '请输入验证码';

  @override
  String get getVerificationCode => '获取验证码';

  @override
  String resendCode(Object seconds) {
    return '重新发送($seconds)';
  }

  @override
  String get forgotPassword => '忘记密码？';

  @override
  String get submit => '提交';

  @override
  String get changePassword => '修改密码';

  @override
  String get currentPassword => '当前密码';

  @override
  String get wrongCurrentPassword => '当前密码不正确。';

  @override
  String get reauthExpired => '验证已过期，请重试。';

  @override
  String get passwordChangedSuccess => '密码修改成功。';

  @override
  String get resetPassword => '重置密码';

  @override
  String get userAgreement => '用户协议';

  @override
  String get privacyPolicy => '隐私保护协议';

  @override
  String get iHaveReadAndAgree => '我已阅读并同意';

  @override
  String get and => '和';

  @override
  String get unregisteredEmailWillCreateAccount => '未注册的邮箱验证后自动创建账号';

  @override
  String get myAccount => '我的账号';

  @override
  String get logout => '退出登录';

  @override
  String get deleteAccount => '删除账号';

  @override
  String get deleteAccountConfirm => '您确定要删除账号吗？此操作无法撤销。';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get deletingAccount => '正在删除账号...';

  @override
  String get accountDeletedSuccess => '账号已成功删除。';

  @override
  String get requiresRecentLogin => '此操作较为敏感，需要重新登录验证。请重新登录后再试。';

  @override
  String unexpectedError(Object error) {
    return '发生意外错误：$error';
  }

  @override
  String get videoError => '视频错误';

  @override
  String get initializingPlayer => '正在初始化播放器...';

  @override
  String get noVideosFound => '未找到视频';

  @override
  String get videoList => '视频列表';

  @override
  String time(Object time) {
    return '时间：$time';
  }

  @override
  String device(Object name) {
    return '设备：$name';
  }

  @override
  String get myDevices => '我的设备';

  @override
  String get scanQrToAddDevice => '扫描二维码添加设备';

  @override
  String get infiniteScroll => '无限滚动';

  @override
  String get noMoreItems => '没有更多内容';

  @override
  String get loginSuccess => '登录成功';

  @override
  String loginFailed(Object error) {
    return '登录失败：$error';
  }

  @override
  String logoutFailed(Object error) {
    return '退出登录失败：$error';
  }

  @override
  String get googleLoginSuccess => 'Google登录成功';

  @override
  String googleLoginFailed(Object error) {
    return 'Google登录失败：$error';
  }

  @override
  String get facebookLoginSuccess => 'Facebook登录成功';

  @override
  String facebookLoginFailed(Object error) {
    return 'Facebook登录失败：$error';
  }

  @override
  String get pleaseAgreeToTerms => '请阅读并同意用户协议和隐私保护协议';

  @override
  String get totpVerifyTitle => '二次验证';

  @override
  String get enterTotpCode => '请输入验证器应用中的 6 位动态码';

  @override
  String get enterBackupCode => '请输入一个 8 位备用恢复码';

  @override
  String get useBackupCode => '改用备用恢复码';

  @override
  String get useTotpCode => '改用验证器动态码';

  @override
  String get invalidBackupCode => '请输入 8 位备用恢复码';

  @override
  String get totpExpired => '验证码已过期或会话被锁定，请重新登录。';

  @override
  String get totpVerify => '验证';

  @override
  String get consentTitle => '阅读并同意';

  @override
  String get consentAccept => '同意并继续';

  @override
  String get consentReject => '拒绝';

  @override
  String get consentRequired => '请阅读并同意以下协议以继续。';

  @override
  String get emailOtpNotRegistered => '该邮箱尚未注册。';

  @override
  String get emailOtpNotRegisteredHint => '是否前往注册新账号？';

  @override
  String get rateLimited => '请求过于频繁，请稍后再试。';

  @override
  String get turnstileFailed => '人机校验失败，请重试。';

  @override
  String get accountNotActivated => '您的账号尚未激活。';

  @override
  String get resendActivation => '重新发送激活邮件';

  @override
  String get sessionExpired => '会话已过期，请重新登录。';

  @override
  String get register => '注册';

  @override
  String get registerTitle => '创建账号';

  @override
  String get registrationDisabledTitle => '注册已关闭';

  @override
  String get registrationDisabledDescription => '当前域暂不接受新账号注册。';

  @override
  String get enterConfirmPassword => '请确认密码';

  @override
  String get passwordMismatch => '两次输入的密码不一致';

  @override
  String get passwordPolicyHint => '密码长度需在 8~24 位之间，且需同时包含大小写字母和数字。';

  @override
  String get registerSuccess => '注册成功，您现在可以登录了。';

  @override
  String get registerSuccessLoginHint => '点击下方链接返回登录。';

  @override
  String get emailAlreadyRegistered => '该邮箱已被注册。';

  @override
  String get verificationCodeInvalid => '验证码无效或已过期。';

  @override
  String get emailAlreadyRegisteredHint => '请尝试登录或找回密码。';

  @override
  String get verifyEmailPendingTitle => '验证您的邮箱';

  @override
  String get verifyEmailPendingNotice => '验证邮件已发送，请打开邮件以激活您的账号。';

  @override
  String get resendVerificationEmail => '重新发送验证邮件';

  @override
  String get verificationEmailSent => '验证邮件已发送。';

  @override
  String get emailVerificationSuccess => '邮箱验证成功。';

  @override
  String get resetPasswordConfirmTitle => '设置新密码';

  @override
  String get enterResetCode => '请输入重置码';

  @override
  String get enterNewPassword => '请输入新密码';

  @override
  String get enterConfirmNewPassword => '请确认新密码';

  @override
  String get passwordResetSuccess => '密码已重置，请重新登录。';

  @override
  String get resetCodeInvalid => '重置码无效或已过期。';

  @override
  String get backToLogin => '返回登录';

  @override
  String get pointsBalance => '积分余额';

  @override
  String get accountOverviewFailed => '无法加载账号信息。';

  @override
  String get purchasePoints => '购买积分';

  @override
  String get stripeCreemCheckout => '通过 Stripe 或 Creem 安全结账';

  @override
  String get billingNotConfigured =>
      '购买功能尚未配置，请为当前构建设置 HERALD_CLIENT_APP_UUID。';

  @override
  String get purchaseOptionsFailed => '无法加载购买选项。';

  @override
  String get retry => '重试';

  @override
  String get noPurchaseOptions => '暂无可购买的选项。';

  @override
  String pointsAmount(Object points) {
    return '$points 积分';
  }

  @override
  String get priceUnavailable => '价格暂不可用';

  @override
  String get alreadyOwned => '已拥有';

  @override
  String get openingCheckout => '正在打开结账页面……';

  @override
  String get buyNow => '立即购买';

  @override
  String get waitingForPayment => '等待付款确认';

  @override
  String get paymentWebhookHint => '仅在服务端确认支付平台 Webhook 后才会发放积分。';

  @override
  String get checkPayment => '检查状态';

  @override
  String get paymentSucceeded => '付款已确认，积分已更新。';

  @override
  String get paymentFailed => '付款未完成。';

  @override
  String get paymentStatusFailed => '暂时无法查询付款状态，请重试。';

  @override
  String get purchaseFailed => '无法打开结账页面，请重试。';

  @override
  String get iapCheckoutSubtitle => '通过 App Store / Google Play 购买';

  @override
  String get restorePurchase => '恢复购买';

  @override
  String get iapVerificationFailed => '购买验证失败，请尝试恢复。';

  @override
  String get iapOwnershipMismatch => '购买归属校验未通过，请重新购买。';

  @override
  String get iapAlreadyConsumed => '该购买已被使用。';

  @override
  String get iapProductUnavailable => '该商品暂不可购买。';

  @override
  String get iapRestoreNothing => '未发现可恢复的购买。';

  @override
  String get iapPurchaseCancelHint => '购买已取消，您可以稍后恢复。';

  @override
  String get membershipLabel => '会员';

  @override
  String get membershipActive => '已开通';

  @override
  String get membershipNone => '暂无会员';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get login => '登入';

  @override
  String get passwordLogin => '密碼登入';

  @override
  String get verificationCodeLogin => '驗證碼登入';

  @override
  String get enterEmail => '請輸入電子郵件';

  @override
  String get enterPassword => '請輸入密碼';

  @override
  String get enterVerificationCode => '請輸入驗證碼';

  @override
  String get getVerificationCode => '獲取驗證碼';

  @override
  String resendCode(Object seconds) {
    return '重新發送($seconds)';
  }

  @override
  String get forgotPassword => '忘記密碼？';

  @override
  String get submit => '提交';

  @override
  String get changePassword => '修改密碼';

  @override
  String get currentPassword => '目前密碼';

  @override
  String get wrongCurrentPassword => '目前密碼不正確。';

  @override
  String get reauthExpired => '驗證已過期，請重試。';

  @override
  String get passwordChangedSuccess => '密碼修改成功。';

  @override
  String get resetPassword => '重設密碼';

  @override
  String get userAgreement => '用戶協議';

  @override
  String get privacyPolicy => '隱私保護協議';

  @override
  String get iHaveReadAndAgree => '我已閱讀並同意';

  @override
  String get and => '和';

  @override
  String get unregisteredEmailWillCreateAccount => '未註冊的電子郵件驗證後自動創建帳號';

  @override
  String get myAccount => '我的帳號';

  @override
  String get logout => '登出';

  @override
  String get deleteAccount => '刪除帳號';

  @override
  String get deleteAccountConfirm => '您確定要刪除帳號嗎？此操作無法撤銷。';

  @override
  String get cancel => '取消';

  @override
  String get delete => '刪除';

  @override
  String get deletingAccount => '正在刪除帳號...';

  @override
  String get accountDeletedSuccess => '帳號已成功刪除。';

  @override
  String get requiresRecentLogin => '此操作較為敏感，需要重新登入驗證。請重新登入後再試。';

  @override
  String unexpectedError(Object error) {
    return '發生意外錯誤：$error';
  }

  @override
  String get videoError => '視頻錯誤';

  @override
  String get initializingPlayer => '正在初始化播放器...';

  @override
  String get noVideosFound => '未找到視頻';

  @override
  String get videoList => '視頻列表';

  @override
  String time(Object time) {
    return '時間：$time';
  }

  @override
  String device(Object name) {
    return '設備：$name';
  }

  @override
  String get myDevices => '我的設備';

  @override
  String get scanQrToAddDevice => '掃描二維碼添加設備';

  @override
  String get infiniteScroll => '無限滾動';

  @override
  String get noMoreItems => '沒有更多內容';

  @override
  String get loginSuccess => '登入成功';

  @override
  String loginFailed(Object error) {
    return '登入失敗：$error';
  }

  @override
  String logoutFailed(Object error) {
    return '登出失敗：$error';
  }

  @override
  String get googleLoginSuccess => 'Google登入成功';

  @override
  String googleLoginFailed(Object error) {
    return 'Google登入失敗：$error';
  }

  @override
  String get facebookLoginSuccess => 'Facebook登入成功';

  @override
  String facebookLoginFailed(Object error) {
    return 'Facebook登入失敗：$error';
  }

  @override
  String get pleaseAgreeToTerms => '請閱讀並同意用戶協議和隱私保護協議';

  @override
  String get totpVerifyTitle => '二次驗證';

  @override
  String get enterTotpCode => '請輸入驗證器應用中的 6 位動態碼';

  @override
  String get enterBackupCode => '請輸入一個 8 位備用恢復碼';

  @override
  String get useBackupCode => '改用備用恢復碼';

  @override
  String get useTotpCode => '改用驗證器動態碼';

  @override
  String get invalidBackupCode => '請輸入 8 位備用恢復碼';

  @override
  String get totpExpired => '驗證碼已過期或工作階段已被鎖定，請重新登入。';

  @override
  String get totpVerify => '驗證';

  @override
  String get consentTitle => '閱讀並同意';

  @override
  String get consentAccept => '同意並繼續';

  @override
  String get consentReject => '拒絕';

  @override
  String get consentRequired => '請閱讀並同意以下協議以繼續。';

  @override
  String get emailOtpNotRegistered => '此電子郵件尚未註冊。';

  @override
  String get emailOtpNotRegisteredHint => '是否前往註冊新帳號？';

  @override
  String get rateLimited => '請求過於頻繁，請稍後再試。';

  @override
  String get turnstileFailed => '人機驗證失敗，請重試。';

  @override
  String get accountNotActivated => '您的帳號尚未啟用。';

  @override
  String get resendActivation => '重新發送啟用郵件';

  @override
  String get sessionExpired => '工作階段已過期，請重新登入。';

  @override
  String get register => '註冊';

  @override
  String get registerTitle => '建立帳號';

  @override
  String get registrationDisabledTitle => '註冊已關閉';

  @override
  String get registrationDisabledDescription => '目前領域暫不接受新帳號註冊。';

  @override
  String get enterConfirmPassword => '請確認密碼';

  @override
  String get passwordMismatch => '兩次輸入的密碼不一致';

  @override
  String get passwordPolicyHint => '密碼長度需在 8~24 位之間，且需同時包含大小寫字母和數字。';

  @override
  String get registerSuccess => '註冊成功，您現在可以登入了。';

  @override
  String get registerSuccessLoginHint => '點擊下方連結返回登入。';

  @override
  String get emailAlreadyRegistered => '此電子郵件已被註冊。';

  @override
  String get verificationCodeInvalid => '驗證碼無效或已過期。';

  @override
  String get emailAlreadyRegisteredHint => '請嘗試登入或找回密碼。';

  @override
  String get verifyEmailPendingTitle => '驗證您的電子郵件';

  @override
  String get verifyEmailPendingNotice => '驗證郵件已發送，請開啟郵件以啟用您的帳號。';

  @override
  String get resendVerificationEmail => '重新發送驗證郵件';

  @override
  String get verificationEmailSent => '驗證郵件已發送。';

  @override
  String get emailVerificationSuccess => '電子郵件驗證成功。';

  @override
  String get resetPasswordConfirmTitle => '設定新密碼';

  @override
  String get enterResetCode => '請輸入重置碼';

  @override
  String get enterNewPassword => '請輸入新密碼';

  @override
  String get enterConfirmNewPassword => '請確認新密碼';

  @override
  String get passwordResetSuccess => '密碼已重置，請重新登入。';

  @override
  String get resetCodeInvalid => '重置碼無效或已過期。';

  @override
  String get backToLogin => '返回登入';

  @override
  String get pointsBalance => '積分餘額';

  @override
  String get accountOverviewFailed => '無法載入帳號資訊。';

  @override
  String get purchasePoints => '購買積分';

  @override
  String get stripeCreemCheckout => '透過 Stripe 或 Creem 安全結帳';

  @override
  String get billingNotConfigured =>
      '購買功能尚未設定，請為目前建置設定 HERALD_CLIENT_APP_UUID。';

  @override
  String get purchaseOptionsFailed => '無法載入購買選項。';

  @override
  String get retry => '重試';

  @override
  String get noPurchaseOptions => '暫無可購買的選項。';

  @override
  String pointsAmount(Object points) {
    return '$points 積分';
  }

  @override
  String get priceUnavailable => '價格暫不可用';

  @override
  String get alreadyOwned => '已擁有';

  @override
  String get openingCheckout => '正在開啟結帳頁面……';

  @override
  String get buyNow => '立即購買';

  @override
  String get waitingForPayment => '等待付款確認';

  @override
  String get paymentWebhookHint => '僅在伺服器確認支付平台 Webhook 後才會發放積分。';

  @override
  String get checkPayment => '檢查狀態';

  @override
  String get paymentSucceeded => '付款已確認，積分已更新。';

  @override
  String get paymentFailed => '付款未完成。';

  @override
  String get paymentStatusFailed => '暫時無法查詢付款狀態，請重試。';

  @override
  String get purchaseFailed => '無法開啟結帳頁面，請重試。';

  @override
  String get iapCheckoutSubtitle => '透過 App Store / Google Play 購買';

  @override
  String get restorePurchase => '恢復購買';

  @override
  String get iapVerificationFailed => '購買驗證失敗，請嘗試恢復。';

  @override
  String get iapOwnershipMismatch => '購買歸屬校驗未通過，請重新購買。';

  @override
  String get iapAlreadyConsumed => '該購買已被使用。';

  @override
  String get iapProductUnavailable => '該商品暫不可購買。';

  @override
  String get iapRestoreNothing => '未發現可恢復的購買。';

  @override
  String get iapPurchaseCancelHint => '購買已取消，您可以稍後恢復。';

  @override
  String get membershipLabel => '會員';

  @override
  String get membershipActive => '已開通';

  @override
  String get membershipNone => '暫無會員';
}
