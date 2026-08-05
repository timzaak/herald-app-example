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

  Future<void> resendVerification({
    required String email,
    String? turnstileToken,
  });

  Future<void> confirmEmailVerification({required String code});

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
    String? code,
    String? backupCode,
    List<AuthConsentAgreement>? agreements,
  });

  /// Apple Sign-In native login (iOS). Submits the Apple `identityToken` to
  /// Herald's direct-session `POST /api/oauth/{realmId}/apple/native-login`
  /// and reuses the same parse/persist path as password login — no OAuth
  /// redirect branch (DEC-native-login-005).
  Future<AuthResult> loginWithApple({required String identityToken});

  /// Google One-Tap native login (Android). Submits the Google `credential`
  /// (`idToken`) to Herald's direct-session
  /// `POST /api/oauth/{realmId}/google/one-tap` and reuses the same
  /// parse/persist path as password login — no OAuth redirect branch
  /// (DEC-native-login-005).
  Future<AuthResult> loginWithGoogleOneTap({required String credential});

  /// Startup login-state probe. True on 200 with `authenticated == true`;
  /// false on 401 (after the interceptor's single refresh attempt has
  /// failed). Never throws.
  Future<bool> checkStatus();

  /// Current Herald `user_id`. Read from `GET /api/auth/status` `userId`
  /// field. Returns null on missing config, unauthenticated, or any failure —
  /// never throws (the caller blocks the purchase when null).
  ///
  /// The impl reuses the startup [checkStatus] `/api/auth/status` snapshot
  /// when available, so opening the purchase page does not trigger a second
  /// status round-trip. The snapshot is cleared on login/logout, so the cached
  /// id always belongs to the currently-authenticated user; it is never
  /// persisted in [TokenStore] / [AuthSession].
  Future<String?> currentUserId();

  /// Best-effort logout; always clears the local [TokenStore].
  Future<void> logout();
}

class HeraldAuthRepositoryImpl implements HeraldAuthRepository {
  HeraldAuthRepositoryImpl(
    this._authApi,
    this._tokenStore, {
    OauthApi? oauthApi,
    String? realmId,
    String? clientId,
    String? baseUrl,
  }) : _oauthApi = oauthApi, // ignore: prefer_initializing_formals
       _realmId = realmId ?? Settings.heraldRealmId,
       _clientId = clientId ?? Settings.heraldClientId,
       _baseUrl = baseUrl ?? Settings.heraldBaseUrl;

  final AuthApi _authApi;
  final OauthApi? _oauthApi;
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
      return await _parseBranch(response.data, operation: 'login');
    } on Object catch (e) {
      // The direct-success branch returns BrowserTokenResponse, which the
      // generator cannot deserialize into LoginResponse — surfacing as a
      // DioException wrapping a 200 response. Recover the raw body here.
      final recovered = _recover200(e);
      if (recovered != null) {
        return _parseRecovered(recovered, operation: 'login');
      }
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
      final response = await _authApi.send(
        realmId: _realmId,
        emailOtpSendRequest: EmailOtpSendRequest((b) {
          b
            ..clientId = _clientId
            ..email = email
            ..turnstileToken = turnstileToken;
          if (agreements != null) b.agreements.replace(agreements);
        }),
      );
      return SendEmailOtpResult.sent(
        expiresInSeconds: response.data?.expiresInSeconds,
      );
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
      return await _parseBranch(response.data, operation: 'emailOtpVerify');
    } on Object catch (e) {
      // verify() is typed as Response<BrowserTokenResponse>; the inline
      // consent-gate JSON {message, consentRequired, agreements} would
      // fail deserialization — recover the raw 200 body here.
      final recovered = _recover200(e);
      if (recovered != null) {
        return _parseRecovered(recovered, operation: 'emailOtpVerify');
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
  Future<void> resendVerification({
    required String email,
    String? turnstileToken,
  }) async {
    if (_isConfigMissing()) {
      throw const AuthErrorException(AuthError.configMissing);
    }
    try {
      await _authApi.verifyEmailTrigger(
        realmId: _realmId,
        verifyEmailTriggerRequest: VerifyEmailTriggerRequest(
          (b) => b
            ..clientId = _clientId
            ..email = email
            ..turnstileToken = turnstileToken,
        ),
      );
    } on Object catch (e) {
      throw AuthErrorException(_asAuthError(e, 'resendVerification'));
    }
  }

  @override
  Future<void> confirmEmailVerification({required String code}) async {
    if (_isConfigMissing()) {
      throw const AuthErrorException(AuthError.configMissing);
    }
    try {
      await _authApi.verifyEmailConfirm(
        realmId: _realmId,
        emailVerificationCode: code,
      );
    } on Object catch (e) {
      throw AuthErrorException(_asAuthError(e, 'verifyEmailConfirm'));
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
    String? code,
    String? backupCode,
    List<AuthConsentAgreement>? agreements,
  }) async {
    if (_isConfigMissing()) {
      return const AuthFailure(AuthError.configMissing);
    }
    try {
      final response = await _authApi.handleVerifyTotp(
        realmId: _realmId,
        verifyTotpRequest: VerifyTotpRequest((b) {
          b.tempToken = tempToken;
          if (code != null) b.code = code;
          if (backupCode != null) b.backupCode = backupCode;
          if (agreements != null) b.agreements.replace(agreements);
        }),
      );
      return await _parseBranch(response.data, operation: 'totp');
    } on Object catch (e) {
      // handleVerifyTotp is typed as Response<VerifyTotpResponse>; the
      // direct-success BrowserTokenResponse branch would fail deserialization
      // — recover the raw 200 body here.
      final recovered = _recover200(e);
      if (recovered != null) {
        return _parseRecovered(recovered, operation: 'totp');
      }
      return AuthFailure(_asAuthError(e, 'totp'));
    }
  }

  @override
  Future<AuthResult> loginWithApple({required String identityToken}) async {
    if (_isConfigMissing() || _oauthApi == null) {
      return const AuthFailure(AuthError.configMissing);
    }
    try {
      final response = await _oauthApi.appleNativeLogin(
        realmId: _realmId,
        appleNativeRequest: AppleNativeRequest(
          (b) => b
            ..identityToken = identityToken
            ..clientId = _clientId,
        ),
      );
      return await _parseBranch(response.data, operation: 'appleNative');
    } on Object catch (e) {
      // Direct-session returns a flattened BrowserTokenSet body that the
      // generator cannot deserialize into AppleNativeCodeResponse — recover
      // the raw 200 body and lenient-parse it (same pattern as login/totp).
      final recovered = _recover200(e);
      if (recovered != null) {
        return _parseRecovered(recovered, operation: 'appleNative');
      }
      return AuthFailure(_asAuthError(e, 'appleNative'));
    }
  }

  @override
  Future<AuthResult> loginWithGoogleOneTap({required String credential}) async {
    if (_isConfigMissing() || _oauthApi == null) {
      return const AuthFailure(AuthError.configMissing);
    }
    try {
      final response = await _oauthApi.googleOneTap(
        realmId: _realmId,
        oneTapRequest: OneTapRequest(
          (b) => b
            ..credential = credential
            ..clientId = _clientId,
        ),
      );
      return await _parseBranch(response.data, operation: 'googleOneTap');
    } on Object catch (e) {
      final recovered = _recover200(e);
      if (recovered != null) {
        return _parseRecovered(recovered, operation: 'googleOneTap');
      }
      return AuthFailure(_asAuthError(e, 'googleOneTap'));
    }
  }

  /// Cached `GET /api/auth/status` snapshot — lets the startup [checkStatus]
  /// probe and [currentUserId] share one network call per auth session.
  /// Populated on a successful parse; cleared by [_persist] (login) and
  /// [logout] so an account switch never serves a stale `userId` to the
  /// purchase ownership binding. null = not yet fetched, last fetch failed,
  /// or cleared.
  ({bool authenticated, String? userId})? _statusSnapshot;

  /// Fetches `/api/auth/status`, parses both `authenticated` and `userId`, and
  /// caches the snapshot on success. Config-missing and any failure (401 after
  /// the interceptor's single refresh, network, …) return the
  /// unauthenticated/empty snapshot WITHOUT caching, so a later caller retries.
  Future<({bool authenticated, String? userId})> _fetchStatus() async {
    if (_isConfigMissing()) return const (authenticated: false, userId: null);
    try {
      final response = await _authApi.status();
      final data = response.data;
      final authenticated =
          data?.authenticated == true || _bodyAuthenticated(data);
      // userId: typed getter first, then the lenient raw-map fallback (mirrors
      // _bodyAuthenticated — covers DTO-shape drift / recovered raw Maps).
      final typedUserId = data?.userId;
      String? userId;
      if (typedUserId != null && typedUserId.isNotEmpty) {
        userId = typedUserId;
      } else {
        final raw = _readString(_asMap(data), 'userId');
        userId = (raw != null && raw.isNotEmpty) ? raw : null;
      }
      final status = (authenticated: authenticated, userId: userId);
      _statusSnapshot = status;
      return status;
    } on Object {
      // 401 (after refresh failure) or any other failure ⇒ fail closed: the
      // caller blocks the purchase instead of injecting an empty/invalid
      // ownership binding. Do NOT cache; do NOT throw.
      return const (authenticated: false, userId: null);
    }
  }

  @override
  Future<bool> checkStatus() async => (await _fetchStatus()).authenticated;

  @override
  Future<String?> currentUserId() async {
    // Reuse the startup checkStatus() snapshot when present so opening the
    // purchase page does NOT trigger a second `/api/auth/status` round-trip.
    // The snapshot is cleared on login/logout, so a returning user's cached id
    // is the correct ownership binding.
    final cached = _statusSnapshot;
    if (cached != null) return cached.userId;
    return (await _fetchStatus()).userId;
  }

  @override
  Future<void> logout() async {
    _statusSnapshot = null;
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

  Future<AuthResult> _parseRecovered(
    Map<String, dynamic> data, {
    required String operation,
  }) async {
    try {
      return await _parseBranch(data, operation: operation);
    } on Object catch (error) {
      return AuthFailure(_asAuthError(error, operation));
    }
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
            agreementType: s.agreementType,
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
    // A (possibly different) user just authenticated — drop the cached status
    // so the next currentUserId()/checkStatus() re-reads the live session.
    _statusSnapshot = null;
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
    final agreementType = raw['agreementType'] ?? raw['agreement_type'];
    if (agreementType is! String || agreementType.isEmpty) return null;
    final title = raw['title'];
    return AgreementView(
      agreementType: agreementType,
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
