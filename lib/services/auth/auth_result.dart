import 'auth_error.dart';

/// Normalized result of an auth flow (design §5.1).
///
/// The repository collapses Herald's multi-branch 200 responses and all error
/// responses into this sum type so the UI never sees a raw DTO or
/// [DioException]. Each subtype carries exactly the fields the UI needs to
/// route to the next page.
sealed class AuthResult {
  const AuthResult();
}

/// Direct session establishment (login / email-otp verify / verify_totp direct
/// branch, refresh).
class AuthSuccess extends AuthResult {
  final AuthSession session;
  const AuthSuccess(this.session);
}

/// Password login returned `requiresTotp: true`; the UI must collect a TOTP /
/// backup code and call [HeraldAuthRepository.verifyTotp] with [tempToken].
class AuthRequiresTotp extends AuthResult {
  final String tempToken;
  final List<String> secondFactors;
  const AuthRequiresTotp(this.tempToken, this.secondFactors);
}

/// A consent gate is required before a session can be established. [agreements]
/// is the list the UI renders on `/consent`.
class AuthConsentRequired extends AuthResult {
  final List<AgreementView> agreements;
  const AuthConsentRequired(this.agreements);
}

/// A network / server / client-side failure. The UI maps [AuthError.kind] to a
/// localized message and stays on the current page (except where the kind
/// implies a navigation, e.g. `sessionExpired` → `/login`).
class AuthFailure extends AuthResult {
  final AuthError error;
  const AuthFailure(this.error);
}

/// Token family issued by Herald on direct-success branches (the
/// `BrowserTokenResponse` shape). Persisted into [TokenStore] inside the
/// repository so the session is durable before the UI navigates.
class AuthSession {
  final String accessToken;
  final String refreshToken;
  final int? expiresIn;
  final int? refreshExpiresIn;
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    this.expiresIn,
    this.refreshExpiresIn,
  });
}

/// UI-facing projection of a legal agreement. Mapped from the generated
/// `LegalAgreementSummary` (Herald's 200 `consentRequired` branch on login /
/// verify_totp) and from the inline `agreements` array on email-otp verify's
/// hand-written consent JSON. Only fields the consent page needs are kept.
class AgreementView {
  final String id;
  final String title;
  final String? summary;
  final String? externalUrl;
  const AgreementView({
    required this.id,
    required this.title,
    this.summary,
    this.externalUrl,
  });
}

/// Result of `sendEmailOtp`. Either the code was sent (success) or Herald
/// returned 409 `consent_required` (auto-register requires prior consent), in
/// which case the UI routes to `/consent` with [agreements]. 409
/// `email_not_registered` / rate limiting / network errors surface as
/// [AuthFailure] via [error].
class SendEmailOtpResult {
  final bool sent;
  final List<AgreementView>? agreements;
  final AuthError? error;

  const SendEmailOtpResult._({this.sent = false, this.agreements, this.error});

  /// Code was sent successfully.
  const SendEmailOtpResult.sent() : this._(sent: true);

  /// Auto-register requires consent; [agreements] is non-null.
  const SendEmailOtpResult.consent(List<AgreementView> agreements)
    : this._(agreements: agreements);

  /// Send failed; [error] is non-null.
  const SendEmailOtpResult.failure(AuthError error) : this._(error: error);
}

/// Result of `register`. Herald's `verificationRequired` flag decides whether
/// the UI routes to `/verify-email-pending` (true) or surfaces a "you can now
/// log in" affordance (false).
class RegisterResult {
  final bool verificationRequired;
  const RegisterResult(this.verificationRequired);
}
