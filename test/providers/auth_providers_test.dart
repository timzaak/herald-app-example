// Unit tests for the native-login Notifier methods on AuthStateNotifier.
//
// WHY these tests exist: the native-login flow has two stages — obtain a
// one-time credential from the platform (NativeSignInService), then submit it
// to Herald (HeraldAuthRepository). The Notifier must (1) return
// AuthFailure(cancelled) and leave the session untouched when the user cancels
// (Service returns null), and (2) flip state to authenticated on success,
// reusing the same _applyResult path as password login. These tests encode that
// intent by faking both the Service and the Repository.
import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/auth_result.dart';
import 'package:app/services/auth/herald_auth_repository.dart';
import 'package:app/services/auth/native_sign_in_service.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Fake [NativeSignInService] returning scripted tokens / null.
class _FakeNativeSignInService implements NativeSignInService {
  _FakeNativeSignInService({this.appleToken, this.googleToken});
  final String? appleToken;
  final String? googleToken;

  @override
  Future<String?> requestAppleIdentityToken() async => appleToken;

  @override
  Future<String?> requestGoogleIdToken() async => googleToken;
}

/// Fake [HeraldAuthRepository] recording calls and returning scripted results.
class _FakeAuthRepository implements HeraldAuthRepository {
  _FakeAuthRepository({this.appleResult, this.googleResult});

  final AuthResult? appleResult;
  final AuthResult? googleResult;
  String? lastAppleToken;
  String? lastGoogleCredential;

  @override
  Future<AuthResult> loginWithApple({required String identityToken}) async {
    lastAppleToken = identityToken;
    return appleResult ??
        AuthSuccess(const AuthSession(accessToken: 'a', refreshToken: 'r'));
  }

  @override
  Future<AuthResult> loginWithGoogleOneTap({required String credential}) async {
    lastGoogleCredential = credential;
    return googleResult ??
        AuthSuccess(const AuthSession(accessToken: 'a', refreshToken: 'r'));
  }

  // Unused by these tests — throw to catch accidental invocation.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

void main() {
  test(
    'loginWithApple: Service returns null (cancel) → AuthFailure(cancelled), repo not called',
    () async {
      // WHY: a user cancel must not establish a session, clear the current
      // session, or hit the network. The Notifier returns cancelled so the UI
      // can show a friendly toast and leave the user where they are.
      final repo = _FakeAuthRepository();
      final container = ProviderContainer.test(
        overrides: [
          heraldAuthRepositoryProvider.overrideWithValue(repo),
          nativeSignInServiceProvider.overrideWithValue(
            _FakeNativeSignInService(appleToken: null),
          ),
        ],
      );

      final result = await container
          .read(authStateProvider.notifier)
          .loginWithApple();

      expect(result, isA<AuthFailure>());
      expect((result as AuthFailure).error.kind, AuthErrorKind.cancelled);
      expect(repo.lastAppleToken, isNull, reason: 'repo was not called');
      expect(
        container.read(authStateProvider).loading,
        isFalse,
        reason: 'loading cleared after cancel',
      );
      expect(
        container.read(authStateProvider).status.toString(),
        contains('unauthenticated'),
      );
      container.dispose();
    },
  );

  test(
    'loginWithApple: Service returns token → repo called with token, state authenticated',
    () async {
      final repo = _FakeAuthRepository();
      final container = ProviderContainer.test(
        overrides: [
          heraldAuthRepositoryProvider.overrideWithValue(repo),
          nativeSignInServiceProvider.overrideWithValue(
            _FakeNativeSignInService(appleToken: 'apple.jwt'),
          ),
        ],
      );

      final result = await container
          .read(authStateProvider.notifier)
          .loginWithApple();

      expect(repo.lastAppleToken, 'apple.jwt');
      expect(result, isA<AuthSuccess>());
      expect(
        container.read(authStateProvider).status.toString(),
        contains('authenticated'),
      );
      container.dispose();
    },
  );

  test(
    'loginWithApple: repo failure surfaces lastError and keeps unauthenticated',
    () async {
      // WHY: a backend failure (invalid token / service unavailable) must not
      // flip the session state — the user stays on the login page and sees the
      // classified error, mirroring password login's failure handling.
      final repo = _FakeAuthRepository(
        appleResult: const AuthFailure(
          AuthError(AuthErrorKind.serviceUnavailable),
        ),
      );
      final container = ProviderContainer.test(
        overrides: [
          heraldAuthRepositoryProvider.overrideWithValue(repo),
          nativeSignInServiceProvider.overrideWithValue(
            _FakeNativeSignInService(appleToken: 'apple.jwt'),
          ),
        ],
      );

      final result = await container
          .read(authStateProvider.notifier)
          .loginWithApple();

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).error.kind,
        AuthErrorKind.serviceUnavailable,
      );
      final state = container.read(authStateProvider);
      expect(state.lastError?.kind, AuthErrorKind.serviceUnavailable);
      expect(state.status.toString(), contains('unauthenticated'));
      container.dispose();
    },
  );

  test(
    'loginWithGoogleOneTap: Service returns null (cancel) → AuthFailure(cancelled)',
    () async {
      final repo = _FakeAuthRepository();
      final container = ProviderContainer.test(
        overrides: [
          heraldAuthRepositoryProvider.overrideWithValue(repo),
          nativeSignInServiceProvider.overrideWithValue(
            _FakeNativeSignInService(googleToken: null),
          ),
        ],
      );

      final result = await container
          .read(authStateProvider.notifier)
          .loginWithGoogleOneTap();

      expect(result, isA<AuthFailure>());
      expect((result as AuthFailure).error.kind, AuthErrorKind.cancelled);
      expect(repo.lastGoogleCredential, isNull);
      container.dispose();
    },
  );

  test(
    'loginWithGoogleOneTap: repo failure surfaces lastError and keeps unauthenticated',
    () async {
      // WHY: a backend failure (invalid token / provider unavailable) must not
      // flip the session state — the user stays on the login page and sees the
      // classified error. The Notifier must route the repo's AuthFailure
      // through _applyResult exactly like password login.
      final repo = _FakeAuthRepository(
        googleResult: const AuthFailure(
          AuthError(AuthErrorKind.providerUnavailable),
        ),
      );
      final container = ProviderContainer.test(
        overrides: [
          heraldAuthRepositoryProvider.overrideWithValue(repo),
          nativeSignInServiceProvider.overrideWithValue(
            _FakeNativeSignInService(googleToken: 'google.jwt'),
          ),
        ],
      );

      final result = await container
          .read(authStateProvider.notifier)
          .loginWithGoogleOneTap();

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).error.kind,
        AuthErrorKind.providerUnavailable,
      );
      final state = container.read(authStateProvider);
      expect(state.lastError?.kind, AuthErrorKind.providerUnavailable);
      expect(state.status.toString(), contains('unauthenticated'));
      expect(state.loading, isFalse);
      container.dispose();
    },
  );
}
