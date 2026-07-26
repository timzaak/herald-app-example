import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @passwordLogin.
  ///
  /// In en, this message translates to:
  /// **'Password Login'**
  String get passwordLogin;

  /// No description provided for @verificationCodeLogin.
  ///
  /// In en, this message translates to:
  /// **'Verification Code Login'**
  String get verificationCodeLogin;

  /// No description provided for @enterEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter email'**
  String get enterEmail;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter password'**
  String get enterPassword;

  /// No description provided for @enterVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter verification code'**
  String get enterVerificationCode;

  /// No description provided for @getVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Get Code'**
  String get getVerificationCode;

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend ({seconds})'**
  String resendCode(Object seconds);

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @wrongCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'The current password is incorrect.'**
  String get wrongCurrentPassword;

  /// No description provided for @reauthExpired.
  ///
  /// In en, this message translates to:
  /// **'Verification expired. Please try again.'**
  String get reauthExpired;

  /// No description provided for @passwordChangedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully.'**
  String get passwordChangedSuccess;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @userAgreement.
  ///
  /// In en, this message translates to:
  /// **'User Agreement'**
  String get userAgreement;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @iHaveReadAndAgree.
  ///
  /// In en, this message translates to:
  /// **'I have read and agree to'**
  String get iHaveReadAndAgree;

  /// No description provided for @and.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get and;

  /// No description provided for @unregisteredEmailWillCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Unregistered email will automatically create an account'**
  String get unregisteredEmailWillCreateAccount;

  /// No description provided for @myAccount.
  ///
  /// In en, this message translates to:
  /// **'My Account'**
  String get myAccount;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete your account? This action cannot be undone.'**
  String get deleteAccountConfirm;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deletingAccount.
  ///
  /// In en, this message translates to:
  /// **'Deleting account...'**
  String get deletingAccount;

  /// No description provided for @accountDeletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Account deleted successfully.'**
  String get accountDeletedSuccess;

  /// No description provided for @requiresRecentLogin.
  ///
  /// In en, this message translates to:
  /// **'This operation is sensitive and requires recent authentication. Please log in again before retrying.'**
  String get requiresRecentLogin;

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred: {error}'**
  String unexpectedError(Object error);

  /// No description provided for @videoError.
  ///
  /// In en, this message translates to:
  /// **'Video Error'**
  String get videoError;

  /// No description provided for @initializingPlayer.
  ///
  /// In en, this message translates to:
  /// **'Initializing player...'**
  String get initializingPlayer;

  /// No description provided for @noVideosFound.
  ///
  /// In en, this message translates to:
  /// **'No videos found'**
  String get noVideosFound;

  /// No description provided for @videoList.
  ///
  /// In en, this message translates to:
  /// **'Video List'**
  String get videoList;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time: {time}'**
  String time(Object time);

  /// No description provided for @device.
  ///
  /// In en, this message translates to:
  /// **'Device: {name}'**
  String device(Object name);

  /// No description provided for @myDevices.
  ///
  /// In en, this message translates to:
  /// **'My Devices'**
  String get myDevices;

  /// No description provided for @scanQrToAddDevice.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code to add device'**
  String get scanQrToAddDevice;

  /// No description provided for @infiniteScroll.
  ///
  /// In en, this message translates to:
  /// **'Infinite Scroll'**
  String get infiniteScroll;

  /// No description provided for @noMoreItems.
  ///
  /// In en, this message translates to:
  /// **'No more items'**
  String get noMoreItems;

  /// No description provided for @loginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Login successful'**
  String get loginSuccess;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed: {error}'**
  String loginFailed(Object error);

  /// No description provided for @logoutFailed.
  ///
  /// In en, this message translates to:
  /// **'Logout failed: {error}'**
  String logoutFailed(Object error);

  /// No description provided for @googleLoginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Google login successful'**
  String get googleLoginSuccess;

  /// No description provided for @googleLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Google login failed: {error}'**
  String googleLoginFailed(Object error);

  /// No description provided for @facebookLoginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Facebook login successful'**
  String get facebookLoginSuccess;

  /// No description provided for @facebookLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Facebook login failed: {error}'**
  String facebookLoginFailed(Object error);

  /// No description provided for @pleaseAgreeToTerms.
  ///
  /// In en, this message translates to:
  /// **'Please read and agree to the User Agreement and Privacy Policy'**
  String get pleaseAgreeToTerms;

  /// No description provided for @totpVerifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Two-Factor Verification'**
  String get totpVerifyTitle;

  /// No description provided for @enterTotpCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code from your authenticator app'**
  String get enterTotpCode;

  /// No description provided for @enterBackupCode.
  ///
  /// In en, this message translates to:
  /// **'Enter one of your 8-character backup recovery codes'**
  String get enterBackupCode;

  /// No description provided for @useBackupCode.
  ///
  /// In en, this message translates to:
  /// **'Use a backup code instead'**
  String get useBackupCode;

  /// No description provided for @useTotpCode.
  ///
  /// In en, this message translates to:
  /// **'Use authenticator code instead'**
  String get useTotpCode;

  /// No description provided for @invalidBackupCode.
  ///
  /// In en, this message translates to:
  /// **'Enter an 8-character backup code'**
  String get invalidBackupCode;

  /// No description provided for @totpExpired.
  ///
  /// In en, this message translates to:
  /// **'The verification code has expired or the session was locked. Please log in again.'**
  String get totpExpired;

  /// No description provided for @totpVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get totpVerify;

  /// No description provided for @consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Review and Consent'**
  String get consentTitle;

  /// No description provided for @consentAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept and Continue'**
  String get consentAccept;

  /// No description provided for @consentReject.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get consentReject;

  /// No description provided for @consentRequired.
  ///
  /// In en, this message translates to:
  /// **'Please review and accept the following agreements to continue.'**
  String get consentRequired;

  /// No description provided for @emailOtpNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'This email is not registered.'**
  String get emailOtpNotRegistered;

  /// No description provided for @emailOtpNotRegisteredHint.
  ///
  /// In en, this message translates to:
  /// **'Would you like to register a new account?'**
  String get emailOtpNotRegisteredHint;

  /// No description provided for @rateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please try again later.'**
  String get rateLimited;

  /// No description provided for @turnstileFailed.
  ///
  /// In en, this message translates to:
  /// **'Human verification failed. Please try again.'**
  String get turnstileFailed;

  /// No description provided for @accountNotActivated.
  ///
  /// In en, this message translates to:
  /// **'Your account is not activated yet.'**
  String get accountNotActivated;

  /// No description provided for @resendActivation.
  ///
  /// In en, this message translates to:
  /// **'Resend activation email'**
  String get resendActivation;

  /// No description provided for @sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please log in again.'**
  String get sessionExpired;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get registerTitle;

  /// No description provided for @registrationDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Registration is disabled'**
  String get registrationDisabledTitle;

  /// No description provided for @registrationDisabledDescription.
  ///
  /// In en, this message translates to:
  /// **'This realm is not accepting new account registrations.'**
  String get registrationDisabledDescription;

  /// No description provided for @enterConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Please confirm password'**
  String get enterConfirmPassword;

  /// No description provided for @passwordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordMismatch;

  /// No description provided for @passwordPolicyHint.
  ///
  /// In en, this message translates to:
  /// **'Password must be 8-24 characters and contain uppercase, lowercase, and a digit.'**
  String get passwordPolicyHint;

  /// No description provided for @registerSuccess.
  ///
  /// In en, this message translates to:
  /// **'Registration successful. You can now log in.'**
  String get registerSuccess;

  /// No description provided for @registerSuccessLoginHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the link below to return to login.'**
  String get registerSuccessLoginHint;

  /// No description provided for @emailAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered.'**
  String get emailAlreadyRegistered;

  /// No description provided for @verificationCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'The verification code is invalid or expired.'**
  String get verificationCodeInvalid;

  /// No description provided for @emailAlreadyRegisteredHint.
  ///
  /// In en, this message translates to:
  /// **'Try logging in or reset your password.'**
  String get emailAlreadyRegisteredHint;

  /// No description provided for @verifyEmailPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify Your Email'**
  String get verifyEmailPendingTitle;

  /// No description provided for @verifyEmailPendingNotice.
  ///
  /// In en, this message translates to:
  /// **'A verification email has been sent. Please open it to activate your account.'**
  String get verifyEmailPendingNotice;

  /// No description provided for @resendVerificationEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend verification email'**
  String get resendVerificationEmail;

  /// No description provided for @verificationEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent.'**
  String get verificationEmailSent;

  /// No description provided for @emailVerificationSuccess.
  ///
  /// In en, this message translates to:
  /// **'Email verified successfully.'**
  String get emailVerificationSuccess;

  /// No description provided for @resetPasswordConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a New Password'**
  String get resetPasswordConfirmTitle;

  /// No description provided for @enterResetCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter reset code'**
  String get enterResetCode;

  /// No description provided for @enterNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter new password'**
  String get enterNewPassword;

  /// No description provided for @enterConfirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Please confirm new password'**
  String get enterConfirmNewPassword;

  /// No description provided for @passwordResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your password has been reset. Please log in.'**
  String get passwordResetSuccess;

  /// No description provided for @resetCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Reset code is invalid or expired.'**
  String get resetCodeInvalid;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to Login'**
  String get backToLogin;

  /// No description provided for @pointsBalance.
  ///
  /// In en, this message translates to:
  /// **'Points balance'**
  String get pointsBalance;

  /// No description provided for @accountOverviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load account information.'**
  String get accountOverviewFailed;

  /// No description provided for @purchasePoints.
  ///
  /// In en, this message translates to:
  /// **'Buy points'**
  String get purchasePoints;

  /// No description provided for @stripeCreemCheckout.
  ///
  /// In en, this message translates to:
  /// **'Secure checkout with Stripe or Creem'**
  String get stripeCreemCheckout;

  /// No description provided for @billingNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Purchases are not configured. Set HERALD_CLIENT_APP_UUID for this build.'**
  String get billingNotConfigured;

  /// No description provided for @purchaseOptionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load purchase options.'**
  String get purchaseOptionsFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noPurchaseOptions.
  ///
  /// In en, this message translates to:
  /// **'No purchase options are available.'**
  String get noPurchaseOptions;

  /// No description provided for @pointsAmount.
  ///
  /// In en, this message translates to:
  /// **'{points} points'**
  String pointsAmount(Object points);

  /// No description provided for @priceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Price unavailable'**
  String get priceUnavailable;

  /// No description provided for @alreadyOwned.
  ///
  /// In en, this message translates to:
  /// **'Already owned'**
  String get alreadyOwned;

  /// No description provided for @openingCheckout.
  ///
  /// In en, this message translates to:
  /// **'Opening checkout...'**
  String get openingCheckout;

  /// No description provided for @buyNow.
  ///
  /// In en, this message translates to:
  /// **'Buy now'**
  String get buyNow;

  /// No description provided for @waitingForPayment.
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment confirmation'**
  String get waitingForPayment;

  /// No description provided for @paymentWebhookHint.
  ///
  /// In en, this message translates to:
  /// **'Points are credited only after the server confirms the provider webhook.'**
  String get paymentWebhookHint;

  /// No description provided for @checkPayment.
  ///
  /// In en, this message translates to:
  /// **'Check status'**
  String get checkPayment;

  /// No description provided for @paymentSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmed. Your points were updated.'**
  String get paymentSucceeded;

  /// No description provided for @paymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment was not completed.'**
  String get paymentFailed;

  /// No description provided for @paymentStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not check payment status. Please try again.'**
  String get paymentStatusFailed;

  /// No description provided for @purchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open checkout. Please try again.'**
  String get purchaseFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
