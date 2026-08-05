import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Abstraction over the platform native sign-in plugins (Apple Sign-In on iOS,
/// Google Sign-In on Android) so the Notifier stays testable and platform-agnostic
/// (design §4.4.1 / §5.2). Returns the one-time handshake credential
/// (`identityToken` / `idToken`) or null when the user cancels, the platform is
/// unsupported, or no account is signed in. The returned credential is never
/// persisted — it is consumed once by [HeraldAuthRepository] (DEC-native-login-004).
abstract class NativeSignInService {
  /// iOS: obtains the Apple `identityToken` via `ASAuthorizationAppleIDProvider`.
  /// Non-iOS: returns null (the button is hidden, so this is defensive).
  Future<String?> requestAppleIdentityToken();

  /// Android: obtains the Google `idToken` via `google_sign_in`.
  /// Non-Android: returns null (the button is hidden, so this is defensive).
  Future<String?> requestGoogleIdToken();
}

/// Concrete [NativeSignInService]. The iOS / Android branches are guarded by
/// `Platform.isIOS` / `Platform.isAndroid`; on other platforms (Web/Desktop)
/// both methods return null so the login page shows no native buttons.
class PlatformNativeSignInService implements NativeSignInService {
  const PlatformNativeSignInService();

  @override
  Future<String?> requestAppleIdentityToken() async {
    if (kIsWeb || !Platform.isIOS) return null;
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      return credential.identityToken;
    } on SignInWithAppleAuthorizationException catch (e) {
      // User cancel / no account — surface as null (→ AuthFailure(cancelled)).
      if (e.code == AuthorizationErrorCode.canceled ||
          e.code == AuthorizationErrorCode.unknown) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<String?> requestGoogleIdToken() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final googleSignIn = GoogleSignIn(
        scopes: const ['openid', 'email', 'profile'],
      );
      final account = await googleSignIn.signIn();
      if (account == null) return null; // user cancelled
      final auth = await account.authentication;
      return auth.idToken;
    } on Object {
      // Any platform/plugin failure — treat like a cancel so the user can retry.
      return null;
    }
  }
}
