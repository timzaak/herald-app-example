import 'package:dio/dio.dart';

/// Stable, UI-facing classification of an auth failure (design §5.1, §4.2.2).
///
/// The UI maps each kind to a localized string. The same HTTP status can map
/// to different kinds depending on the operation (401 is `invalidCredentials`
/// on `login` but `sessionExpired` on `refresh` / `totp`), so classification is
/// always performed through [AuthError.fromDioException] with an `operation`
/// string — see the operation vocabulary on that method.
enum AuthErrorKind {
  invalidCredentials,
  accountNotActivated,
  emailNotRegistered,
  emailAlreadyRegistered,
  verificationCodeInvalid,
  resetCodeInvalid,
  consentRequired,
  rateLimited,
  turnstileFailed,
  configMissing,
  sessionExpired,
  network,
}

/// A classified auth error. [rawMessage] is for logs only — never render it.
class AuthError {
  final AuthErrorKind kind;
  final String? rawMessage;
  const AuthError(this.kind, [this.rawMessage]);

  /// Local-preflight config-missing case (realmId / clientId / baseUrl blank).
  /// Used by [HeraldAuthRepository] before any network call is attempted.
  static const AuthError configMissing = AuthError(AuthErrorKind.configMissing);

  /// Classifies a [DioException] into an [AuthError] using the frozen
  /// `operation` vocabulary below. 401 means different things per operation,
  /// so the [operation] argument is load-bearing — callers must pass exactly
  /// one of the documented strings.
  ///
  /// Operation vocabulary (frozen — repository tests and UI l10n pin these):
  /// - `"login"`: password login. 401 → `invalidCredentials`; 403 →
  ///   `accountNotActivated`.
  /// - `"emailOtpSend"`: 409 + `email_not_registered` → `emailNotRegistered`;
  ///   409 + `consent_required` → `consentRequired`.
  /// - `"emailOtpVerify"`: `invalid_code` → `verificationCodeInvalid`;
  ///   other 401 → `invalidCredentials`. The 200 inline
  ///   `{consentRequired: true, agreements}` branch is handled in the
  ///   repository's lenient parse, NOT here.
  /// - `"totp"`: 401 → `sessionExpired` (tempToken expired / locked; default).
  /// - `"refresh"`: 401 → `sessionExpired`.
  /// - `"turnstileStatus"`: must NOT be passed — [TurnstileService] handles its
  ///   401 internally (caches disabled) and never calls this helper.
  /// - `"register"`: `email_already_exists` → `emailAlreadyRegistered`.
  /// - `"resetPasswordConfirm"`: 400/404 → `resetCodeInvalid`.
  /// - `"verifyEmailConfirm"`: 400/404 → `verificationCodeInvalid`.
  ///
  /// Common across all operations: 429 / known rate-limit code →
  /// `rateLimited`; `verify_turnstile_for_client_app` → `turnstileFailed`;
  /// 400 with Client-App-disabled / realm-capability body code →
  /// `configMissing`; network exception / 5xx / unrecognized → `network`.
  static AuthError fromDioException(
    DioException e, {
    required String operation,
  }) {
    final response = e.response;
    final statusCode = response?.statusCode;
    final bodyCode = _bodyCode(response?.data);

    // 429 / explicit too_many_requests always wins.
    if (statusCode == 429 ||
        bodyCode == 'too_many_requests' ||
        bodyCode == 'rate_limit_exceeded') {
      return AuthError(AuthErrorKind.rateLimited, e.toString());
    }

    if (bodyCode == 'verify_turnstile_for_client_app') {
      return AuthError(AuthErrorKind.turnstileFailed, e.toString());
    }

    // Client-App-disabled / realm-capability-unenabled → configMissing, any op.
    if (statusCode == 400 && _isConfigMissingBodyCode(bodyCode)) {
      return AuthError(AuthErrorKind.configMissing, e.toString());
    }

    switch (operation) {
      case 'login':
        if (statusCode == 401) {
          return AuthError(AuthErrorKind.invalidCredentials, e.toString());
        }
        if (statusCode == 403) {
          return AuthError(AuthErrorKind.accountNotActivated, e.toString());
        }
        if (statusCode == 400) {
          return AuthError(AuthErrorKind.configMissing, e.toString());
        }
        return AuthError(AuthErrorKind.network, e.toString());

      case 'emailOtpSend':
        if (statusCode == 409) {
          if (bodyCode == 'email_not_registered') {
            return AuthError(AuthErrorKind.emailNotRegistered, e.toString());
          }
          if (bodyCode == 'consent_required') {
            return AuthError(AuthErrorKind.consentRequired, e.toString());
          }
        }
        if (statusCode == 401) {
          // 401 from send is Turnstile siteverify failure (verify_turnstile_for_client_app).
          return AuthError(AuthErrorKind.turnstileFailed, e.toString());
        }
        if (statusCode == 400) {
          return AuthError(AuthErrorKind.configMissing, e.toString());
        }
        return AuthError(AuthErrorKind.network, e.toString());

      case 'emailOtpVerify':
        if (statusCode == 401) {
          if (bodyCode == 'invalid_code') {
            return AuthError(
              AuthErrorKind.verificationCodeInvalid,
              e.toString(),
            );
          }
          // Code invalid / account disabled.
          return AuthError(AuthErrorKind.invalidCredentials, e.toString());
        }
        if (statusCode == 400) {
          return AuthError(AuthErrorKind.configMissing, e.toString());
        }
        return AuthError(AuthErrorKind.network, e.toString());

      case 'totp':
        if (statusCode == 401) {
          // tempToken expired / locked / wrong code — default to sessionExpired
          // (UI distinguishes "expired" from "wrong code" only when a body code
          // is present, which Herald does not currently send).
          return AuthError(AuthErrorKind.sessionExpired, e.toString());
        }
        if (statusCode == 400) {
          return AuthError(AuthErrorKind.network, e.toString());
        }
        return AuthError(AuthErrorKind.network, e.toString());

      case 'refresh':
        if (statusCode == 401) {
          return AuthError(AuthErrorKind.sessionExpired, e.toString());
        }
        return AuthError(AuthErrorKind.network, e.toString());

      case 'register':
        if ((statusCode == 400 || statusCode == 409) &&
            bodyCode == 'email_already_exists') {
          return AuthError(AuthErrorKind.emailAlreadyRegistered, e.toString());
        }
        return AuthError(AuthErrorKind.network, e.toString());

      case 'resetPasswordConfirm':
        if (statusCode == 400 || statusCode == 404) {
          return AuthError(AuthErrorKind.resetCodeInvalid, e.toString());
        }
        return AuthError(AuthErrorKind.network, e.toString());

      case 'verifyEmailConfirm':
        if (statusCode == 400 || statusCode == 404) {
          return AuthError(AuthErrorKind.verificationCodeInvalid, e.toString());
        }
        return AuthError(AuthErrorKind.network, e.toString());

      case 'resetPasswordRequest':
      case 'resendVerification':
        return AuthError(AuthErrorKind.network, e.toString());

      default:
        return AuthError(AuthErrorKind.network, e.toString());
    }
  }

  /// Extracts the Herald `code` field from a response body, tolerating both
  /// Map-shaped and already-deserialized bodies.
  static String? _bodyCode(Object? data) {
    if (data is Map) {
      final code = data['code'];
      if (code is String && code.isNotEmpty) return code;
    }
    return null;
  }

  /// Body codes Herald emits when the Client App is disabled or a realm
  /// capability is not enabled (`require_enabled_client`,
  /// realm-capability-unenabled variants). Used for the cross-operation 400 →
  /// configMissing mapping.
  static bool _isConfigMissingBodyCode(String? code) {
    switch (code) {
      case 'require_enabled_client':
      case 'client_app_disabled':
      case 'realm_capability_unenabled':
      case 'realm_capability_not_enabled':
        return true;
      default:
        return false;
    }
  }
}
