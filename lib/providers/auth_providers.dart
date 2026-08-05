import 'package:api_client/api_client.dart';
import 'package:app/api/dio_auth_interceptor.dart';
import 'package:app/api/dio_util.dart';
import 'package:app/config/settings.dart';
import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/auth_result.dart';
import 'package:app/services/auth/account_security_service.dart';
import 'package:app/services/auth/herald_auth_repository.dart';
import 'package:app/services/auth/legal_agreement_service.dart';
import 'package:app/services/auth/native_sign_in_service.dart';
import 'package:app/services/auth/public_auth_config_service.dart';
import 'package:app/services/auth/token_store.dart';
import 'package:app/services/auth/turnstile_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:io' show Platform;

/// Single source of truth for Herald login state (design §5.5).
///
/// UI watches [authStateProvider]; auth-flow entry points (login / email-otp /
/// TOTP / register / logout) are invoked through [AuthStateNotifier] methods
/// which both return the routing [AuthResult] / [RegisterResult] to the caller
/// AND write single-source state. This contract is documented on each method.
///
/// Implementation note (Riverpod technical line): this uses [NotifierProvider]
/// per the project's locked Riverpod 3.3.2 (which removed `StateNotifier` /
/// `StateNotifierProvider`) and the constitution's "mutable sync business state
/// → NotifierProvider" rule. The item file's `StateNotifierProvider` wording is
/// a spec drift; the public surface (`authStateProvider`, `AuthState`,
/// `AuthStatus`, the notifier's method names and return types) is unchanged
/// from the frozen contract.
enum AuthStatus { unauthenticated, authenticated }

class AuthState {
  final AuthStatus status;
  final AuthSession? session;
  final AuthError? lastError;
  final bool loading;
  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.session,
    this.lastError,
    this.loading = false,
  });

  static const AuthState initial = AuthState();
}

/// Holds [AuthState] and delegates auth flows to [HeraldAuthRepository].
///
/// Contract: every flow method returns its routing result so the UI can
/// navigate, AND writes single-source state as follows:
/// - [AuthSuccess] → `status = authenticated` + `session` set; `lastError`
///   cleared.
/// - [AuthRequiresTotp] / [AuthConsentRequired] → `status` unchanged (still
///   unauthenticated); the UI routes by the returned subtype.
/// - [AuthFailure] → `lastError` set; `status` unchanged (so a transient
///   password error does not log the user out if they were already in — though
///   in practice the failure happens pre-session).
/// - [RegisterResult] → no status change (no session established); the caller
///   routes by `verificationRequired`.
class AuthStateNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => AuthState.initial;

  HeraldAuthRepository get _repository =>
      ref.read(heraldAuthRepositoryProvider);

  /// Password login. Returns the routing [AuthResult]; also flips state to
  /// `authenticated` on direct success.
  Future<AuthResult> loginWithPassword({
    required String email,
    required String password,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  }) async {
    state = state.copyWith(loading: true);
    final result = await _repository.loginWithPassword(
      email: email,
      password: password,
      turnstileToken: turnstileToken,
      agreements: agreements,
    );
    state = _applyResult(result);
    return result;
  }

  /// Email-OTP send. Returns a [SendEmailOtpResult]; does not flip session
  /// state (no session established at the send step).
  Future<SendEmailOtpResult> sendEmailOtp({
    required String email,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  }) {
    return _repository.sendEmailOtp(
      email: email,
      turnstileToken: turnstileToken,
      agreements: agreements,
    );
  }

  /// Email-OTP verify. Returns the routing [AuthResult]; flips state on
  /// direct success.
  Future<AuthResult> loginWithEmailOtp({
    required String email,
    required String code,
    String? turnstileToken,
    List<AuthConsentAgreement>? agreements,
  }) async {
    state = state.copyWith(loading: true);
    final result = await _repository.loginWithEmailOtp(
      email: email,
      code: code,
      turnstileToken: turnstileToken,
      agreements: agreements,
    );
    state = _applyResult(result);
    return result;
  }

  /// TOTP verify. Returns the routing [AuthResult]; flips state on direct
  /// success.
  Future<AuthResult> verifyTotp({
    required String tempToken,
    String? code,
    String? backupCode,
    List<AuthConsentAgreement>? agreements,
  }) async {
    state = state.copyWith(loading: true);
    final result = await _repository.verifyTotp(
      tempToken: tempToken,
      code: code,
      backupCode: backupCode,
      agreements: agreements,
    );
    state = _applyResult(result);
    return result;
  }

  /// Apple Sign-In native login (iOS). Obtains the Apple `identityToken` via
  /// [NativeSignInService], then submits it to [HeraldAuthRepository]. If the
  /// user cancels (Service returns null), returns [AuthFailure] with
  /// `cancelled` and leaves the current session untouched. On success,
  /// flips state to `authenticated` like password login.
  Future<AuthResult> loginWithApple() async {
    state = state.copyWith(loading: true);
    final identityToken = await ref
        .read(nativeSignInServiceProvider)
        .requestAppleIdentityToken();
    if (identityToken == null) {
      state = state.copyWith(loading: false);
      return const AuthFailure(AuthError(AuthErrorKind.cancelled));
    }
    final result = await _repository.loginWithApple(
      identityToken: identityToken,
    );
    state = _applyResult(result);
    return result;
  }

  /// Google One-Tap native login (Android). Obtains the Google `idToken` via
  /// [NativeSignInService], then submits it to [HeraldAuthRepository]. If the
  /// user cancels (Service returns null), returns [AuthFailure] with
  /// `cancelled` and leaves the current session untouched. On success,
  /// flips state to `authenticated` like password login.
  Future<AuthResult> loginWithGoogleOneTap() async {
    state = state.copyWith(loading: true);
    final credential = await ref
        .read(nativeSignInServiceProvider)
        .requestGoogleIdToken();
    if (credential == null) {
      state = state.copyWith(loading: false);
      return const AuthFailure(AuthError(AuthErrorKind.cancelled));
    }
    final result = await _repository.loginWithGoogleOneTap(
      credential: credential,
    );
    state = _applyResult(result);
    return result;
  }

  /// Registration. Returns [RegisterResult]; no session state change. A
  /// failure throws [AuthErrorException] — the caller catches and surfaces the
  /// embedded [AuthError] via l10n (FL-D04 responsibility).
  Future<RegisterResult> register({
    required String email,
    required String password,
    String? turnstileToken,
  }) {
    return _repository.register(
      email: email,
      password: password,
      turnstileToken: turnstileToken,
    );
  }

  /// Logs out best-effort and resets state to `unauthenticated`.
  Future<void> logout() async {
    await _repository.logout();
    state = const AuthState();
  }

  /// Resets state to unauthenticated without a network call. Used as the
  /// interceptor's `onSessionEnd` callback (a refresh failure means the
  /// session is gone server-side). The router redirect (FL-D03) handles the
  /// actual `/login` navigation.
  void markUnauthenticated() {
    state = const AuthState();
  }

  /// Seeds state from a startup [checkStatus] result. Called once from
  /// `main.dart` before `runApp`.
  void seedAuthenticated(bool authenticated) {
    state = AuthState(
      status: authenticated
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated,
    );
  }

  AuthState _applyResult(AuthResult result) {
    switch (result) {
      case AuthSuccess(:final session):
        return AuthState(status: AuthStatus.authenticated, session: session);
      case AuthRequiresTotp():
        // Status unchanged; UI routes by subtype.
        return state.copyWith(loading: false);
      case AuthConsentRequired():
        return state.copyWith(loading: false);
      case AuthFailure(:final error):
        return state.copyWith(loading: false, lastError: error);
    }
  }
}

final authStateProvider = NotifierProvider<AuthStateNotifier, AuthState>(
  AuthStateNotifier.new,
);

/// shared_preferences-backed token persistence (FL-D01).
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Herald [ApiClient] singleton (design §4.1, FL-D01 Handoff). Constructed
/// with the project's shared [DioUtil.dio] (which mounts [DioAuthInterceptor]
/// as the single Authorization source) and an empty interceptors list so the
/// generated client skips its default `BearerAuthInterceptor`.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    dio: DioUtil.dio,
    basePathOverride: Settings.heraldBaseUrl,
    interceptors: const [],
  );
});

/// Single [HeraldAuthRepository] consumed by [AuthStateNotifier] and the
/// startup `checkStatus` in `main.dart`. Injects the generated [OauthApi] for
/// the native-login endpoints (apple native-login / google one-tap).
final heraldAuthRepositoryProvider = Provider<HeraldAuthRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final tokenStore = ref.watch(tokenStoreProvider);
  return HeraldAuthRepositoryImpl(
    apiClient.getAuthApi(),
    tokenStore,
    oauthApi: apiClient.getOauthApi(),
  );
});

/// Native sign-in plugin wrapper (Apple Sign-In / Google Sign-In). Default
/// impl guards by platform; tests override with a fake that returns scripted
/// tokens or null.
final nativeSignInServiceProvider = Provider<NativeSignInService>((ref) {
  return const PlatformNativeSignInService();
});

/// Per-Client-App Turnstile service. Reads `realmId` / `clientId` from
/// [Settings].
final turnstileServiceProvider = Provider<TurnstileService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return HeraldTurnstileService(
    apiClient.getAuthApi(),
    Settings.heraldRealmId,
    Settings.heraldClientId,
  );
});

/// Public email-OTP capability for the configured realm. Fail closed so a
/// disabled, misconfigured, or unreachable endpoint never exposes a dead
/// login option.
final emailOtpEnabledProvider = FutureProvider<bool>((ref) async {
  if (Settings.heraldRealmId.isEmpty) return false;
  try {
    final apiClient = ref.watch(apiClientProvider);
    final response = await apiClient.getAuthApi().status_1(
      realmId: Settings.heraldRealmId,
    );
    return response.data?.enabled == true;
  } on Object {
    return false;
  }
});

final publicAuthConfigServiceProvider = Provider<PublicAuthConfigService>((
  ref,
) {
  return HeraldPublicAuthConfigService(DioUtil.dio, Settings.heraldRealmId);
});

final legalAgreementServiceProvider = Provider<LegalAgreementService>((ref) {
  return HeraldLegalAgreementService(DioUtil.dio, Settings.heraldRealmId);
});

/// Public registration capability for the configured realm. Fail closed:
/// direct navigation to `/register` must not expose a disabled registration
/// form when the public-config endpoint is unavailable or malformed.
final registrationEnabledProvider = FutureProvider<bool>((ref) async {
  if (Settings.heraldRealmId.isEmpty) return false;
  try {
    final config = await ref.watch(publicAuthConfigServiceProvider).getConfig();
    return config.registrationEnabled;
  } on Object {
    return false;
  }
});

final accountSecurityServiceProvider = Provider<AccountSecurityService>((ref) {
  return HeraldAccountSecurityService(DioUtil.dio);
});

/// Native-login button availability per platform (design §4.4.2, DEC-native-login-002/007).
/// A button shows only when: the running platform matches the provider
/// (iOS→Apple, Android→Google) AND public-config reports the provider enabled
/// with a non-empty `clientId`. Any fetch failure / missing field → button
/// hidden (fail closed, never expose a dead login option).
class NativeLoginAvailability {
  final bool apple;
  final bool google;
  const NativeLoginAvailability({this.apple = false, this.google = false});
}

final nativeLoginAvailabilityProvider = FutureProvider<NativeLoginAvailability>(
  (ref) async {
    if (Settings.heraldRealmId.isEmpty) {
      return const NativeLoginAvailability();
    }
    try {
      final config = await ref
          .watch(publicAuthConfigServiceProvider)
          .getConfig();
      final enabled = config.enabledNativeProviderNames;
      return NativeLoginAvailability(
        apple: _isApplePlatform && enabled.contains('apple'),
        google: _isAndroidPlatform && enabled.contains('google'),
      );
    } on Object {
      return const NativeLoginAvailability();
    }
  },
);

bool get _isApplePlatform => !kIsWeb && Platform.isIOS;

bool get _isAndroidPlatform => !kIsWeb && Platform.isAndroid;

/// Exposes the [DioAuthInterceptor] mounted on [DioUtil.dio] (FL-D01). This is
/// the single Bearer-Authorization source. `main.dart` activates it via
/// `DioUtil.bindAuth(...)` with provider-backed `refreshFn` / `onSessionEnd`
/// callbacks — see `buildSessionBindings` for the wiring.
final dioAuthInterceptorProvider = Provider<DioAuthInterceptor>((ref) {
  return DioUtil.authInterceptor;
});

/// Builds the provider-backed callbacks `main.dart` passes to
/// [DioUtil.bindAuth]. Kept here (next to the providers it reads) so the
/// interceptor's `refreshFn` / `onSessionEnd` stay consistent with
/// [apiClientProvider] / [tokenStoreProvider] / [authStateProvider] across
/// refactors.
///
/// `refreshFn`: calls `AuthApi.refresh` with the stored refresh token,
/// persists the new token family into [TokenStore], returns true on success /
/// false on any failure (never throws — the interceptor treats a thrown
/// refreshFn as failure too, but we keep this defensive).
/// `onSessionEnd`: resets [AuthStateNotifier] so the router redirect (FL-D03)
/// sees `unauthenticated` and bounces to `/login`.
({RefreshFn refreshFn, OnSessionEnd onSessionEnd}) buildSessionBindings(
  ProviderContainer container,
) {
  Future<bool> refreshFn() async {
    try {
      final tokenStore = container.read(tokenStoreProvider);
      final refreshToken = await tokenStore.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return false;
      final apiClient = container.read(apiClientProvider);
      final response = await apiClient.getAuthApi().refresh(
        refreshBrowserTokenRequest: RefreshBrowserTokenRequest(
          (b) => b..refreshToken = refreshToken,
        ),
      );
      final data = response.data;
      if (data == null) return false;
      final accessToken = data.accessToken;
      final newRefresh = data.refreshToken;
      if (accessToken.isEmpty || newRefresh.isEmpty) return false;
      await tokenStore.save(accessToken: accessToken, refreshToken: newRefresh);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> onSessionEnd() async {
    container.read(authStateProvider.notifier).markUnauthenticated();
  }

  return (refreshFn: refreshFn, onSessionEnd: onSessionEnd);
}

typedef RefreshFn = Future<bool> Function();
typedef OnSessionEnd = Future<void> Function();

/// CopyWith helper on an immutable state value.
extension on AuthState {
  AuthState copyWith({
    AuthStatus? status,
    AuthSession? session,
    AuthError? lastError,
    bool? loading,
  }) {
    return AuthState(
      status: status ?? this.status,
      session: session ?? this.session,
      lastError: lastError ?? this.lastError,
      loading: loading ?? this.loading,
    );
  }
}
