// Hand-rolled fake of [HeraldAuthRepository] for widget tests (FL-T01).
//
// Why a hand-rolled fake (not mockito): guides/flutter/testing.md prefers
// fakes over call-count-based mocking for stable, intent-revealing tests, and
// the FL-T01 item pins this ("fake 优先"). This fake records every call's args
// into exposed `*Calls` lists and returns queued `*Result` values set by the
// test. It is the ONLY fake point at the widget layer — dio is never mocked
// here (dio is covered at the unit layer in FL-D01).
//
// Repository contract honored (FL-D02 binding):
// - `loginWithPassword` / `loginWithEmailOtp` / `verifyTotp` / `sendEmailOtp`
//   return their result type (never throw).
// - `register` / `resendVerification` / `requestResetPassword` /
//   `confirmResetPassword` THROW [AuthErrorException] on failure (they do not
//   return an AuthFailure). To script a failure for these, set the
//   corresponding `*Error` field instead of a `*Result`.
// - `checkStatus` never throws; returns the seeded bool.
// - `logout` always succeeds and records the call.
//
// Pending responses: each method's result field may be a `Future` controlled
// by a test-held `Completer`, so tests can assert the loading / disabled-button
// state while a call is in flight. See `loginWithPasswordPending`.
import 'package:api_client/api_client.dart';
import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/auth_result.dart';
import 'package:app/services/auth/herald_auth_repository.dart';

/// Single recorded call to `loginWithPassword`.
class LoginCall {
  final String email;
  final String password;
  final String? turnstileToken;
  final List<AuthConsentAgreement>? agreements;
  const LoginCall({
    required this.email,
    required this.password,
    this.turnstileToken,
    this.agreements,
  });
}

/// Single recorded call to `loginWithEmailOtp`.
class LoginWithEmailOtpCall {
  final String email;
  final String code;
  final String? turnstileToken;
  final List<AuthConsentAgreement>? agreements;
  const LoginWithEmailOtpCall({
    required this.email,
    required this.code,
    this.turnstileToken,
    this.agreements,
  });
}

/// Single recorded call to `sendEmailOtp`.
class SendEmailOtpCall {
  final String email;
  final String? turnstileToken;
  final List<AuthConsentAgreement>? agreements;
  const SendEmailOtpCall({
    required this.email,
    this.turnstileToken,
    this.agreements,
  });
}

/// Single recorded call to `verifyTotp`.
class VerifyTotpCall {
  final String tempToken;
  final String? code;
  final String? backupCode;
  final List<AuthConsentAgreement>? agreements;
  const VerifyTotpCall({
    required this.tempToken,
    this.code,
    this.backupCode,
    this.agreements,
  });
}

/// Single recorded call to `register`.
class RegisterCall {
  final String email;
  final String password;
  final String? turnstileToken;
  const RegisterCall({
    required this.email,
    required this.password,
    this.turnstileToken,
  });
}

class FakeHeraldAuthRepository implements HeraldAuthRepository {
  // ---- Argument-recording lists (test assertions read these). ----
  final List<LoginCall> loginCalls = [];
  final List<LoginWithEmailOtpCall> loginWithEmailOtpCalls = [];
  final List<SendEmailOtpCall> sendEmailOtpCalls = [];
  final List<VerifyTotpCall> verifyTotpCalls = [];
  final List<RegisterCall> registerCalls = [];
  final List<ResendVerificationCall> resendVerificationCalls = [];
  final List<String> confirmEmailVerificationCalls = [];
  final List<ResetPasswordRequestCall> requestResetPasswordCalls = [];
  final List<ConfirmResetPasswordCall> confirmResetPasswordCalls = [];
  final List<void> logoutCalls = [];

  // ---- Queued return values (test sets these before pumping/tapping). ----
  //
  // For the Future-returning methods, the field may hold either a plain value
  // (returned immediately) or a `Future` the test controls via a Completer
  // (for loading-state assertions). The small `_asFuture` helper normalizes.

  /// Result returned by `loginWithPassword`. Defaults to a generic network
  /// failure so a test that forgets to seed a value fails loudly instead of
  /// accidentally navigating.
  FutureOrResult<AuthResult> loginWithPasswordResult = FutureOrResult.value(
    const AuthFailure(AuthError(AuthErrorKind.network)),
  );

  FutureOrResult<AuthResult> loginWithEmailOtpResult = FutureOrResult.value(
    const AuthFailure(AuthError(AuthErrorKind.network)),
  );

  FutureOrResult<SendEmailOtpResult> sendEmailOtpResult = FutureOrResult.value(
    const SendEmailOtpResult.failure(AuthError(AuthErrorKind.network)),
  );

  FutureOrResult<AuthResult> verifyTotpResult = FutureOrResult.value(
    const AuthFailure(AuthError(AuthErrorKind.network)),
  );

  /// Thrown by `register` when non-null. When null, [registerResult] is
  /// returned. Kept separate from the result because `register` throws on
  /// failure (FL-D02 binding).
  AuthErrorException? registerError;
  RegisterResult registerResult = const RegisterResult(false);

  /// When non-null, `register` awaits this future before returning
  /// [registerResult] (or throwing [registerError]). Tests use this with a
  /// test-held `Completer` to assert the loading / disabled-button state
  /// while the call is in flight.
  Future<RegisterResult>? registerPending;

  /// Thrown by `resendVerification` when non-null; otherwise the call returns
  /// normally.
  AuthErrorException? resendVerificationError;
  AuthErrorException? confirmEmailVerificationError;

  AuthErrorException? requestResetPasswordError;
  AuthErrorException? confirmResetPasswordError;

  /// `checkStatus` never throws; returns this bool.
  bool checkStatusResult = false;

  // ---- HeraldAuthRepository implementation ----

  @override
  Future<AuthResult> loginWithPassword({
    required String email,
    required String password,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  }) async {
    loginCalls.add(
      LoginCall(
        email: email,
        password: password,
        turnstileToken: turnstileToken,
        agreements: agreements,
      ),
    );
    return _asFuture(loginWithPasswordResult);
  }

  @override
  Future<SendEmailOtpResult> sendEmailOtp({
    required String email,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  }) async {
    sendEmailOtpCalls.add(
      SendEmailOtpCall(
        email: email,
        turnstileToken: turnstileToken,
        agreements: agreements,
      ),
    );
    return _asFuture(sendEmailOtpResult);
  }

  @override
  Future<AuthResult> loginWithEmailOtp({
    required String email,
    required String code,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  }) async {
    loginWithEmailOtpCalls.add(
      LoginWithEmailOtpCall(
        email: email,
        code: code,
        turnstileToken: turnstileToken,
        agreements: agreements,
      ),
    );
    return _asFuture(loginWithEmailOtpResult);
  }

  @override
  Future<RegisterResult> register({
    required String email,
    required String password,
    String? turnstileToken,
  }) async {
    registerCalls.add(
      RegisterCall(
        email: email,
        password: password,
        turnstileToken: turnstileToken,
      ),
    );
    final pending = registerPending;
    if (pending != null) await pending;
    final error = registerError;
    if (error != null) throw error;
    return registerResult;
  }

  @override
  Future<void> resendVerification({
    required String email,
    String? turnstileToken,
  }) async {
    resendVerificationCalls.add(
      ResendVerificationCall(email: email, turnstileToken: turnstileToken),
    );
    final error = resendVerificationError;
    if (error != null) throw error;
  }

  @override
  Future<void> confirmEmailVerification({required String code}) async {
    confirmEmailVerificationCalls.add(code);
    final error = confirmEmailVerificationError;
    if (error != null) throw error;
  }

  @override
  Future<void> requestResetPassword({
    required String email,
    String? turnstileToken,
  }) async {
    requestResetPasswordCalls.add(
      ResetPasswordRequestCall(email: email, turnstileToken: turnstileToken),
    );
    final error = requestResetPasswordError;
    if (error != null) throw error;
  }

  @override
  Future<void> confirmResetPassword({
    required String code,
    required String newPass,
    String? turnstileToken,
  }) async {
    confirmResetPasswordCalls.add(
      ConfirmResetPasswordCall(
        code: code,
        newPass: newPass,
        turnstileToken: turnstileToken,
      ),
    );
    final error = confirmResetPasswordError;
    if (error != null) throw error;
  }

  @override
  Future<AuthResult> verifyTotp({
    required String tempToken,
    String? code,
    String? backupCode,
    List<AuthConsentAgreement>? agreements,
  }) async {
    verifyTotpCalls.add(
      VerifyTotpCall(
        tempToken: tempToken,
        code: code,
        backupCode: backupCode,
        agreements: agreements,
      ),
    );
    return _asFuture(verifyTotpResult);
  }

  @override
  Future<bool> checkStatus() async => checkStatusResult;

  @override
  Future<void> logout() async {
    logoutCalls.add(null);
  }

  Future<T> _asFuture<T>(FutureOrResult<T> value) {
    final v = value.value;
    final f = value.future;
    if (f != null) return f;
    return Future<T>.value(v as T);
  }
}

class ResetPasswordRequestCall {
  final String email;
  final String? turnstileToken;
  const ResetPasswordRequestCall({required this.email, this.turnstileToken});
}

class ResendVerificationCall {
  final String email;
  final String? turnstileToken;
  const ResendVerificationCall({required this.email, this.turnstileToken});
}

class ConfirmResetPasswordCall {
  final String code;
  final String newPass;
  final String? turnstileToken;
  const ConfirmResetPasswordCall({
    required this.code,
    required this.newPass,
    this.turnstileToken,
  });
}

/// Holds either an immediate value or a test-controlled Future for a queued
/// result. Exactly one of [value] / [future] is non-null.
class FutureOrResult<T> {
  final T? value;
  final Future<T>? future;
  const FutureOrResult.value(T v) : value = v, future = null;
  const FutureOrResult.pending(this.future) : value = null;
}

/// Builds an [AuthSuccess] with a minimal valid session (the page only checks
/// navigation, not the session contents).
AuthSuccess authSuccess() => AuthSuccess(
  const AuthSession(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    expiresIn: 3600,
    refreshExpiresIn: 86400,
  ),
);
