import 'package:api_client/api_client.dart';
import 'package:app/config/settings.dart';
import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/auth_result.dart';
import 'package:app/services/auth/token_store.dart';
import 'package:dio/dio.dart';

/// Thin orchestration layer over the generated [AuthApi] (design §5.2).
///
/// Responsibilities:
/// - Collapse Herald's multi-branch 200 responses into [AuthResult]
///   (lenient parse by field presence, never trusting the generated return
///   type — the direct-success branch returns a `BrowserTokenResponse` the
///   generator does not surface through `login`'s declared return type, and
///   email-otp verify's consent branch is hand-written inline JSON).
/// - Persist [AuthSuccess] sessions into [TokenStore] so the session is
///   durable before the UI navigates.
/// - Convert every [DioException] into a classified [AuthError] so the UI
///   never sees a raw exception.
abstract class HeraldAuthRepository {
  Future<AuthResult> loginWithPassword({
    required String email,
    required String password,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  });

  Future<SendEmailOtpResult> sendEmailOtp({
    required String email,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  });

  Future<AuthResult> loginWithEmailOtp({
    required String email,
    required String code,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  });

  Future<RegisterResult> register({
    required String email,
    required String password,
    String? turnstileToken,
  });

  Future<void> resendVerification({required String email});

  Future<void> requestResetPassword({
    required String email,
    String? turnstileToken,
  });

  Future<void> confirmResetPassword({
    required String code,
    required String newPass,
    String? turnstileToken,
  });

  Future<AuthResult> verifyTotp({
    required String tempToken,
    required String code,
    List<AuthConsentAgreement>? agreements,
  });

  /// Startup login-state probe. True on 200 with `authenticated == true`;
  /// false on 401 (after the interceptor's single refresh attempt has
  /// failed). Never throws.
  Future<bool> checkStatus();

  /// Best-effort logout; always clears the local [TokenStore].
  Future<void> logout();
}

class HeraldAuthRepositoryImpl implements HeraldAuthRepository {
  HeraldAuthRepositoryImpl(
    this._authApi,
    this._tokenStore, {
    String? realmId,
    String? clientId,
    String? baseUrl,
  }) : _realmId = realmId ?? Settings.heraldRealmId,
       _clientId = clientId ?? Settings.heraldClientId,
       _baseUrl = baseUrl ?? Settings.heraldBaseUrl;

  final AuthApi _authApi;
  final TokenStore _tokenStore;
  final String _realmId;
  final String _clientId;
  final String _baseUrl;

  bool _isConfigMissing() =>
      _realmId.isEmpty || _clientId.isEmpty || _baseUrl.isEmpty;

  @override
  Future<AuthResult> loginWithPassword({
    required String email,
    required String password,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  }) async {
    if (_isConfigMissing()) {
      return const AuthFailure(AuthError.configMissing);
    }
    try {
      final response = await _authApi.login(
        realmId: _realmId,
        loginRequestPayload: LoginRequestPayload((b) {
          b
            ..clientId = _clientId
            ..email = email
            ..password = password
            ..turnstileToken = turnstileToken;
          if (agreements != null) b.agreements.replace(agreements);
        }),
      );
      return _parseBranch(response.data, operation: 'login');
    } on Object catch (e) {
      // The direct-success branch returns BrowserTokenResponse, which the
      // generator cannot deserialize into LoginResponse — surfacing as a
      // DioException wrapping a 200 response. Recover the raw body here.
      final recovered = _recover200(e);
      if (recovered != null) return _parseBranch(recovered, operation: 'login');
      return AuthFailure(_asAuthError(e, 'login'));
    }
  }

  @override
  Future<SendEmailOtpResult> sendEmailOtp({
    required String email,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  }) async {
    if (_isConfigMissing()) {
      return const SendEmailOtpResult.failure(AuthError.configMissing);
    }
    try {
      await _authApi.send(
        realmId: _realmId,
        emailOtpSendRequest: EmailOtpSendRequest((b) {
          b
            ..clientId = _clientId
            ..email = email
            ..turnstileToken = turnstileToken;
          if (agreements != null) b.agreements.replace(agreements);
        }),
      );
      return const SendEmailOtpResult.sent();
    } on Object catch (e) {
      final dioError = e is DioException ? e : null;
      final statusCode = dioError?.response?.statusCode;
      final bodyCode = _bodyCode(dioError?.response?.data);
      // 409 consent_required on send carries agreements — route to /consent.
      if (statusCode == 409 && bodyCode == 'consent_required') {
        final agreements = _extractAgreements(dioError?.response?.data);
        return SendEmailOtpResult.consent(agreements);
      }
      return SendEmailOtpResult.failure(_asAuthError(e, 'emailOtpSend'));
    }
  }

  @override
  Future<AuthResult> loginWithEmailOtp({
    required String email,
    required String code,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  }) async {
    if (_isConfigMissing()) {
      return const AuthFailure(AuthError.configMissing);
    }
    try {
      final response = await _authApi.verify(
        realmId: _realmId,
        emailOtpVerifyRequest: EmailOtpVerifyRequest((b) {
          b
            ..clientId = _clientId
            ..email = email
            ..code = code
            ..turnstileToken = turnstileToken;
          if (agreements != null) b.agreements.replace(agreements);
        }),
      );
      return _parseBranch(response.data, operation: 'emailOtpVerify');
    } on Object catch (e) {
      // verify() is typed as Response<BrowserTokenResponse>; the inline
      // consent-gate JSON {message, consentRequired, agreements} would
      // fail deserialization — recover the raw 200 body here.
      final recovered = _recover200(e);
      if (recovered != null) {
        return _parseBranch(recovered, operation: 'emailOtpVerify');
      }
      return AuthFailure(_asAuthError(e, 'emailOtpVerify'));
    }
  }

  @override
  Future<RegisterResult> register({
    required String email,
    required String password,
    String? turnstileToken,
  }) async {
    if (_isConfigMissing()) {
      throw const AuthErrorException(AuthError.configMissing);
    }
    try {
      final response = await _authApi.register(
        realmId: _realmId,
        registerRequest: RegisterRequest(
          (b) => b
            ..clientId = _clientId
            ..email = email
            ..password = password
            ..turnstileToken = turnstileToken,
        ),
      );
      final data = response.data;
      final verificationRequired =
          data?.verificationRequired == true || _bodyVerificationRequired(data);
      return RegisterResult(verificationRequired);
    } on Object catch (e) {
      throw AuthErrorException(_asAuthError(e, 'register'));
    }
  }

  @override
  Future<void> resendVerification({required String email}) async {
    if (_isConfigMissing()) {
      throw const AuthErrorException(AuthError.configMissing);
    }
    try {
      await _authApi.verifyEmailTrigger(
        realmId: _realmId,
        verifyEmailTriggerRequest: VerifyEmailTriggerRequest(
          (b) => b
            ..clientId = _clientId
            ..email = email,
        ),
      );
    } on Object catch (e) {
      throw AuthErrorException(_asAuthError(e, 'resendVerification'));
    }
  }

  @override
  Future<void> requestResetPassword({
    required String email,
    String? turnstileToken,
  }) async {
    if (_isConfigMissing()) {
      throw const AuthErrorException(AuthError.configMissing);
    }
    try {
      await _authApi.resetPasswordRequest(
        realmId: _realmId,
        resetPasswordRequestRequest: ResetPasswordRequestRequest(
          (b) => b
            ..clientId = _clientId
            ..email = email
            ..turnstileToken = turnstileToken,
        ),
      );
    } on Object catch (e) {
      throw AuthErrorException(_asAuthError(e, 'resetPasswordRequest'));
    }
  }

  @override
  Future<void> confirmResetPassword({
    required String code,
    required String newPass,
    String? turnstileToken,
  }) async {
    if (_isConfigMissing()) {
      throw const AuthErrorException(AuthError.configMissing);
    }
    try {
      await _authApi.resetPasswordConfirm(
        realmId: _realmId,
        resetCode: code,
        resetPasswordConfirmRequest: ResetPasswordConfirmRequest(
          (b) => b
            ..newPass = newPass
            ..turnstileToken = turnstileToken,
        ),
      );
    } on Object catch (e) {
      throw AuthErrorException(_asAuthError(e, 'resetPasswordConfirm'));
    }
  }

  @override
  Future<AuthResult> verifyTotp({
    required String tempToken,
    required String code,
    List<AuthConsentAgreement>? agreements,
  }) async {
    if (_isConfigMissing()) {
      return const AuthFailure(AuthError.configMissing);
    }
    try {
      final response = await _authApi.handleVerifyTotp(
        realmId: _realmId,
        verifyTotpRequest: VerifyTotpRequest((b) {
          b
            ..tempToken = tempToken
            ..code = code;
          if (agreements != null) b.agreements.replace(agreements);
        }),
      );
      return _parseBranch(response.data, operation: 'totp');
    } on Object catch (e) {
      // handleVerifyTotp is typed as Response<VerifyTotpResponse>; the
      // direct-success BrowserTokenResponse branch would fail deserialization
      // — recover the raw 200 body here.
      final recovered = _recover200(e);
      if (recovered != null) return _parseBranch(recovered, operation: 'totp');
      return AuthFailure(_asAuthError(e, 'totp'));
    }
  }

  @override
  Future<bool> checkStatus() async {
    if (_isConfigMissing()) return false;
    try {
      final response = await _authApi.status();
      final authenticated =
          response.data?.authenticated == true ||
          _bodyAuthenticated(response.data);
      return authenticated;
    } on Object {
      // 401 (after the interceptor's single refresh attempt failed) or any
      // other failure ⇒ not authenticated. Do NOT throw.
      return false;
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _authApi.logout();
    } on Object {
      // Best-effort — the local store is cleared regardless below.
    }
    await _tokenStore.clear();
  }

  // ------------------------------------------------------------------
  // Lenient multi-branch parse (design §5.2 algorithm).
  //
  // `data` may be:
  // - a generated DTO the AuthApi successfully deserialized (BrowserTokenResponse
  //   on verify direct-success; LoginResponse on login requiresTotp /
  //   consentRequired; VerifyTotpResponse on totp consentRequired) —
  // - the hand-written inline consent JSON `{message, consentRequired,
  //   agreements}` from email-otp verify (no DTO), or
  // - a raw Map recovered from a failed deserialize (e.g. login direct-success,
  //   where Herald returns BrowserTokenResponse but login() is typed
  //   Response<LoginResponse>).
  //
  // We never trust the static declared type. For DTO objects we read the typed
  // getters directly; for raw Maps we read by field presence.
  // ------------------------------------------------------------------

  Future<AuthResult> _parseBranch(
    Object? data, {
    required String operation,
  }) async {
    // Direct success as a typed BrowserTokenResponse (verify direct-success).
    if (data is BrowserTokenResponse && data.accessToken.isNotEmpty) {
      final session = AuthSession(
        accessToken: data.accessToken,
        refreshToken: data.refreshToken,
        expiresIn: data.expiresIn,
        refreshExpiresIn: data.refreshExpiresIn,
      );
      await _persist(session);
      return AuthSuccess(session);
    }

    // TOTP / consentRequired as a typed VerifyTotpResponse.
    if (data is VerifyTotpResponse) {
      if (data.consentRequired == true) {
        return AuthConsentRequired(_agreementsFromSummaries(data.agreements));
      }
      // VerifyTotpResponse's direct-success field is `token`, but Herald's
      // actual direct-success body is BrowserTokenResponse (accessToken) —
      // which would have failed deserialize and been recovered as a Map below.
      // If we somehow got a typed VerifyTotpResponse without consentRequired,
      // treat as unrecognized.
    }

    // requiresTotp / consentRequired as a typed LoginResponse.
    if (data is LoginResponse) {
      if (data.requiresTotp == true) {
        return AuthRequiresTotp(
          data.tempToken ?? '',
          (data.secondFactors?.toList() ?? <String>[]),
        );
      }
      if (data.consentRequired == true) {
        return AuthConsentRequired(_agreementsFromSummaries(data.agreements));
      }
    }

    // Raw Map path: covers inline consent JSON and recovered raw bodies
    // (login direct-success, email-otp verify both branches, totp
    // direct-success when Herald's BrowserTokenResponse body failed to
    // deserialize into VerifyTotpResponse).
    final map = _asMap(data);
    if (map != null) {
      // Direct success: BrowserTokenResponse shape (accessToken present).
      final accessToken = _readString(map, 'accessToken');
      if (accessToken != null && accessToken.isNotEmpty) {
        final session = AuthSession(
          accessToken: accessToken,
          refreshToken: _readString(map, 'refreshToken') ?? '',
          expiresIn: _readInt(map, 'expiresIn') ?? _readInt(map, 'expires_in'),
          refreshExpiresIn:
              _readInt(map, 'refreshExpiresIn') ??
              _readInt(map, 'refresh_expires_in'),
        );
        await _persist(session);
        return AuthSuccess(session);
      }

      // requiresTotp branch (login only).
      if (_readBool(map, 'requiresTotp')) {
        final tempToken = _readString(map, 'tempToken') ?? '';
        final factors = _readStringList(map, 'secondFactors') ?? <String>[];
        return AuthRequiresTotp(tempToken, factors);
      }

      // consentRequired branch (login / email-otp verify / verify_totp).
      if (_readBool(map, 'consentRequired')) {
        return AuthConsentRequired(_extractAgreements(map));
      }
    }

    // Unrecognized 200 shape — treat as network-classified failure so the UI
    // surfaces a generic error rather than navigating on a broken response.
    return AuthFailure(
      AuthError(AuthErrorKind.network, 'unrecognized 200 body for $operation'),
    );
  }

  /// Maps the generated agreement summaries (Herald's consent branch —
  /// `BuiltList<LegalAgreementSummary>?` on LoginResponse / VerifyTotpResponse;
  /// accepted as `Iterable?` so this file does not import built_collection)
  /// into UI-facing [AgreementView]s.
  List<AgreementView> _agreementsFromSummaries(
    Iterable<LegalAgreementSummary>? summaries,
  ) {
    if (summaries == null) return const <AgreementView>[];
    return summaries
        .map(
          (s) => AgreementView(
            id: s.versionId,
            title: (s.title?.isNotEmpty ?? false) ? s.title! : s.versionId,
            summary: s.summary,
            externalUrl: s.externalUrl,
          ),
        )
        .toList(growable: false);
  }

  /// If [e] is a [DioException] wrapping a 200 response (the generated client
  /// throws when Herald's 200 body doesn't match the declared DTO — e.g.
  /// direct-success `BrowserTokenResponse` on `/login`), return the raw body
  /// Map so [_parseBranch] can lenient-parse it. Otherwise return null.
  Map<String, dynamic>? _recover200(Object e) {
    if (e is! DioException) return null;
    final response = e.response;
    if (response?.statusCode != 200) return null;
    return _asMap(response?.data);
  }

  Future<void> _persist(AuthSession session) async {
    if (session.refreshToken.isEmpty) return;
    await _tokenStore.save(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
  }

  /// Converts a caught object into an [AuthError]. Only [DioException] carries
  /// enough context (status code / body code) for precise classification; an
  /// [AuthErrorException] re-exposes its embedded error; anything else is
  /// `network`.
  AuthError _asAuthError(Object e, String operation) {
    if (e is DioException) {
      return AuthError.fromDioException(e, operation: operation);
    }
    if (e is AuthErrorException) {
      return e.error;
    }
    return AuthError(AuthErrorKind.network, e.toString());
  }

  Map<String, dynamic>? _asMap(Object? data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      // Built_value serializers / inline JSON sometimes hand back MapBase
      // subclasses; coerce to Map<String, dynamic>.
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    // Typed DTOs (BrowserTokenResponse / LoginResponse / VerifyTotpResponse)
    // are handled explicitly in _parseBranch before this helper is reached;
    // any other object type is treated as an unrecognized body (returns null).
    return null;
  }

  static String? _bodyCode(Object? data) {
    if (data is Map) {
      final code = data['code'];
      if (code is String && code.isNotEmpty) return code;
    }
    return null;
  }

  static bool _bodyVerificationRequired(Object? data) {
    if (data is Map) {
      final v = data['verificationRequired'];
      return v is bool ? v : false;
    }
    return false;
  }

  static bool _bodyAuthenticated(Object? data) {
    if (data is Map) {
      final v = data['authenticated'];
      return v is bool ? v : false;
    }
    return false;
  }

  static String? _readString(Map<String, dynamic>? map, String key) {
    if (map == null) return null;
    final v = map[key];
    return v is String ? v : null;
  }

  static int? _readInt(Map<String, dynamic>? map, String key) {
    if (map == null) return null;
    final v = map[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  static bool _readBool(Map<String, dynamic>? map, String key) {
    if (map == null) return false;
    final v = map[key];
    return v is bool ? v : false;
  }

  static List<String>? _readStringList(Map<String, dynamic>? map, String key) {
    if (map == null) return null;
    final v = map[key];
    if (v is! List) return null;
    return v.whereType<String>().toList(growable: false);
  }

  /// Extracts the `agreements` array (list of legal-agreement summaries) from
  /// either a 200 `consentRequired` body or a 409 `consent_required` body.
  List<AgreementView> _extractAgreements(Object? data) {
    final map = _asMap(data);
    if (map == null) return const <AgreementView>[];
    final raw = map['agreements'];
    if (raw is! List) return const <AgreementView>[];
    return raw
        .whereType<Map>()
        .map(_toAgreementView)
        .whereType<AgreementView>()
        .toList(growable: false);
  }

  static AgreementView? _toAgreementView(Map raw) {
    final id = raw['versionId'] ?? raw['version_id'] ?? raw['agreementType'];
    if (id is! String || id.isEmpty) return null;
    final title = raw['title'];
    return AgreementView(
      id: id,
      title: title is String && title.isNotEmpty ? title : id,
      summary: _asString(raw['summary']),
      externalUrl:
          _asString(raw['externalUrl']) ?? _asString(raw['external_url']),
    );
  }

  static String? _asString(Object? v) => v is String && v.isNotEmpty ? v : null;
}

/// Thrown by repository methods that return `void` / [RegisterResult] so the
/// caller (the notifier / UI) can classify the failure uniformly. Repository
/// methods returning [AuthResult] / [SendEmailOtpResult] embed the error
/// instead of throwing.
class AuthErrorException implements Exception {
  final AuthError error;
  const AuthErrorException(this.error);
  @override
  String toString() => 'AuthErrorException(${error.kind})';
}
