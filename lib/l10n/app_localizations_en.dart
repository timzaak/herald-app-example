// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get login => 'Login';

  @override
  String get passwordLogin => 'Password Login';

  @override
  String get verificationCodeLogin => 'Verification Code Login';

  @override
  String get enterEmail => 'Please enter email';

  @override
  String get enterPassword => 'Please enter password';

  @override
  String get enterVerificationCode => 'Please enter verification code';

  @override
  String get getVerificationCode => 'Get Code';

  @override
  String resendCode(Object seconds) {
    return 'Resend ($seconds)';
  }

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get submit => 'Submit';

  @override
  String get changePassword => 'Change Password';

  @override
  String get currentPassword => 'Current password';

  @override
  String get wrongCurrentPassword => 'The current password is incorrect.';

  @override
  String get reauthExpired => 'Verification expired. Please try again.';

  @override
  String get passwordChangedSuccess => 'Password changed successfully.';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get userAgreement => 'User Agreement';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get iHaveReadAndAgree => 'I have read and agree to';

  @override
  String get and => 'and';

  @override
  String get unregisteredEmailWillCreateAccount =>
      'Unregistered email will automatically create an account';

  @override
  String get myAccount => 'My Account';

  @override
  String get logout => 'Logout';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get deleteAccountConfirm =>
      'Are you sure you want to delete your account? This action cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get deletingAccount => 'Deleting account...';

  @override
  String get accountDeletedSuccess => 'Account deleted successfully.';

  @override
  String get requiresRecentLogin =>
      'This operation is sensitive and requires recent authentication. Please log in again before retrying.';

  @override
  String unexpectedError(Object error) {
    return 'An unexpected error occurred: $error';
  }

  @override
  String get videoError => 'Video Error';

  @override
  String get initializingPlayer => 'Initializing player...';

  @override
  String get noVideosFound => 'No videos found';

  @override
  String get videoList => 'Video List';

  @override
  String time(Object time) {
    return 'Time: $time';
  }

  @override
  String device(Object name) {
    return 'Device: $name';
  }

  @override
  String get myDevices => 'My Devices';

  @override
  String get scanQrToAddDevice => 'Scan QR code to add device';

  @override
  String get infiniteScroll => 'Infinite Scroll';

  @override
  String get noMoreItems => 'No more items';

  @override
  String get loginSuccess => 'Login successful';

  @override
  String loginFailed(Object error) {
    return 'Login failed: $error';
  }

  @override
  String logoutFailed(Object error) {
    return 'Logout failed: $error';
  }

  @override
  String get googleLoginSuccess => 'Google login successful';

  @override
  String googleLoginFailed(Object error) {
    return 'Google login failed: $error';
  }

  @override
  String get facebookLoginSuccess => 'Facebook login successful';

  @override
  String facebookLoginFailed(Object error) {
    return 'Facebook login failed: $error';
  }

  @override
  String get pleaseAgreeToTerms =>
      'Please read and agree to the User Agreement and Privacy Policy';

  @override
  String get totpVerifyTitle => 'Two-Factor Verification';

  @override
  String get enterTotpCode =>
      'Enter the 6-digit code from your authenticator app';

  @override
  String get enterBackupCode =>
      'Enter one of your 8-character backup recovery codes';

  @override
  String get useBackupCode => 'Use a backup code instead';

  @override
  String get useTotpCode => 'Use authenticator code instead';

  @override
  String get invalidBackupCode => 'Enter an 8-character backup code';

  @override
  String get totpExpired =>
      'The verification code has expired or the session was locked. Please log in again.';

  @override
  String get totpVerify => 'Verify';

  @override
  String get consentTitle => 'Review and Consent';

  @override
  String get consentAccept => 'Accept and Continue';

  @override
  String get consentReject => 'Decline';

  @override
  String get consentRequired =>
      'Please review and accept the following agreements to continue.';

  @override
  String get emailOtpNotRegistered => 'This email is not registered.';

  @override
  String get emailOtpNotRegisteredHint =>
      'Would you like to register a new account?';

  @override
  String get rateLimited => 'Too many requests. Please try again later.';

  @override
  String get turnstileFailed => 'Human verification failed. Please try again.';

  @override
  String get accountNotActivated => 'Your account is not activated yet.';

  @override
  String get resendActivation => 'Resend activation email';

  @override
  String get sessionExpired => 'Your session has expired. Please log in again.';

  @override
  String get register => 'Register';

  @override
  String get registerTitle => 'Create Account';

  @override
  String get registrationDisabledTitle => 'Registration is disabled';

  @override
  String get registrationDisabledDescription =>
      'This realm is not accepting new account registrations.';

  @override
  String get enterConfirmPassword => 'Please confirm password';

  @override
  String get passwordMismatch => 'Passwords do not match';

  @override
  String get passwordPolicyHint =>
      'Password must be 8-24 characters and contain uppercase, lowercase, and a digit.';

  @override
  String get registerSuccess => 'Registration successful. You can now log in.';

  @override
  String get registerSuccessLoginHint =>
      'Tap the link below to return to login.';

  @override
  String get emailAlreadyRegistered => 'This email is already registered.';

  @override
  String get verificationCodeInvalid =>
      'The verification code is invalid or expired.';

  @override
  String get emailAlreadyRegisteredHint =>
      'Try logging in or reset your password.';

  @override
  String get verifyEmailPendingTitle => 'Verify Your Email';

  @override
  String get verifyEmailPendingNotice =>
      'A verification email has been sent. Please open it to activate your account.';

  @override
  String get resendVerificationEmail => 'Resend verification email';

  @override
  String get verificationEmailSent => 'Verification email sent.';

  @override
  String get emailVerificationSuccess => 'Email verified successfully.';

  @override
  String get resetPasswordConfirmTitle => 'Set a New Password';

  @override
  String get enterResetCode => 'Please enter reset code';

  @override
  String get enterNewPassword => 'Please enter new password';

  @override
  String get enterConfirmNewPassword => 'Please confirm new password';

  @override
  String get passwordResetSuccess =>
      'Your password has been reset. Please log in.';

  @override
  String get resetCodeInvalid => 'Reset code is invalid or expired.';

  @override
  String get backToLogin => 'Back to Login';

  @override
  String get pointsBalance => 'Points balance';

  @override
  String get accountOverviewFailed => 'Could not load account information.';

  @override
  String get purchasePoints => 'Buy points';

  @override
  String get stripeCreemCheckout => 'Secure checkout with Stripe or Creem';

  @override
  String get billingNotConfigured =>
      'Purchases are not configured. Set HERALD_CLIENT_APP_UUID for this build.';

  @override
  String get purchaseOptionsFailed => 'Could not load purchase options.';

  @override
  String get retry => 'Retry';

  @override
  String get noPurchaseOptions => 'No purchase options are available.';

  @override
  String pointsAmount(Object points) {
    return '$points points';
  }

  @override
  String get priceUnavailable => 'Price unavailable';

  @override
  String get alreadyOwned => 'Already owned';

  @override
  String get openingCheckout => 'Opening checkout...';

  @override
  String get buyNow => 'Buy now';

  @override
  String get waitingForPayment => 'Waiting for payment confirmation';

  @override
  String get paymentWebhookHint =>
      'Points are credited only after the server confirms the provider webhook.';

  @override
  String get checkPayment => 'Check status';

  @override
  String get paymentSucceeded => 'Payment confirmed. Your points were updated.';

  @override
  String get paymentFailed => 'Payment was not completed.';

  @override
  String get paymentStatusFailed =>
      'Could not check payment status. Please try again.';

  @override
  String get purchaseFailed => 'Could not open checkout. Please try again.';

  @override
  String get iapCheckoutSubtitle => 'Buy via App Store / Google Play';

  @override
  String get restorePurchase => 'Restore purchases';

  @override
  String get iapVerificationFailed =>
      'Purchase verification failed. Try restoring.';

  @override
  String get iapOwnershipMismatch =>
      'Purchase ownership check failed. Please repurchase.';

  @override
  String get iapAlreadyConsumed => 'This purchase has already been used.';

  @override
  String get iapProductUnavailable => 'This product is currently unavailable.';

  @override
  String get iapRestoreNothing => 'No restorable purchases found.';

  @override
  String get iapPurchaseCancelHint =>
      'Purchase canceled. You can restore later.';

  @override
  String get membershipLabel => 'Membership';

  @override
  String get membershipActive => 'Active';

  @override
  String get membershipNone => 'No active membership';

  @override
  String get signInWithApple => 'Sign in with Apple';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get orUseEmail => 'or use email';

  @override
  String get loginServiceUnavailable =>
      'Login service is temporarily unavailable. Please try again later.';

  @override
  String get nativeSignInCancelled => 'Sign-in was not completed.';
}
