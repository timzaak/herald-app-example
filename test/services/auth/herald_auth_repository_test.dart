// Unit tests for HeraldAuthRepository (design §6.1, FL-D02).
//
// Exercises the lenient multi-branch parse and the AuthError classification
// table by scripting raw Herald response bodies through a real AuthApi mounted
// on a Dio with a hand-rolled HttpClientAdapter. Per the §6.1 decoupling note,
// responses are constructed as Map literals — the repository reads raw bodies
// and never trusts the generated declared return type.
//
// No new deps (Rule 2). Mirrors the approach in
// test/api/dio_auth_interceptor_test.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/auth/auth_error.dart';
import 'package:app/services/auth/auth_result.dart';
import 'package:app/services/auth/herald_auth_repository.dart';
import 'package:app/services/auth/token_store.dart';

/// In-memory TokenStore replacement (same shape as the one in
/// dio_auth_interceptor_test). Avoids shared_preferences in unit tests.
class _FakeTokenStore implements TokenStore {
  String? accessToken;
  String? refreshToken;

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }
}

/// Hand-rolled Dio adapter that returns scripted [ResponseBody]s in sequence,
/// recording each requested path so tests can assert routing. No new test
/// dependency (Rule 2 — http_mock_adapter not added).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(List<ResponseBody> Function() responses)
    : _responses = responses();

  final List<ResponseBody> _responses;
  final List<String> requestedPaths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    if (_responses.isEmpty) {
      throw StateError('_ScriptedAdapter: no scripted response left');
    }
    return _responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: const {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Builds a [HeraldAuthRepositoryImpl] backed by a real [AuthApi] whose Dio is
/// served by [adapter]. Realm/client/baseUrl default to non-empty values so
/// the config-missing preflight passes; the preflight test passes blanks.
(HeraldAuthRepository, _FakeTokenStore) _buildRepo(
  _ScriptedAdapter adapter, {
  String realmId = 'realm-1',
  String clientId = 'client-1',
  String baseUrl = 'https://herald.test',
}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = adapter;
  final authApi = AuthApi(dio, standardSerializers);
  final tokenStore = _FakeTokenStore();
  final repo = HeraldAuthRepositoryImpl(
    authApi,
    tokenStore,
    realmId: realmId,
    clientId: clientId,
    baseUrl: baseUrl,
  );
  return (repo, tokenStore);
}

void main() {
  group('HeraldAuthRepository.loginWithPassword', () {
    test(
      'direct-success (BrowserTokenResponse) → AuthSuccess + persists',
      () async {
        // The generated login() is typed Response<LoginResponse>; a
        // BrowserTokenResponse body fails to deserialize, surfacing as a 200
        // DioException whose response.data is the raw body. The repository
        // recovers it and lenient-parses the accessToken branch.
        final adapter = _ScriptedAdapter(
          () => [
            _jsonBody(200, {
              'accessToken': 'a1',
              'refreshToken': 'r1',
              'expiresIn': 3600,
              'refreshExpiresIn': 86400,
              'tokenType': 'Bearer',
            }),
          ],
        );
        final (repo, tokenStore) = _buildRepo(adapter);

        final result = await repo.loginWithPassword(
          email: 'u@e.com',
          password: 'pw',
        );

        expect(result, isA<AuthSuccess>());
        final s = (result as AuthSuccess).session;
        expect(s.accessToken, 'a1');
        expect(s.refreshToken, 'r1');
        expect(s.expiresIn, 3600);
        expect(s.refreshExpiresIn, 86400);
        // Session was persisted before returning so it survives navigation.
        expect(tokenStore.accessToken, 'a1');
        expect(tokenStore.refreshToken, 'r1');
      },
    );

    test(
      'requiresTotp branch → AuthRequiresTotp(tempToken, secondFactors)',
      () async {
        final adapter = _ScriptedAdapter(
          () => [
            _jsonBody(200, {
              'requiresTotp': true,
              'tempToken': 'tt',
              'secondFactors': ['totp'],
              'message': 'm',
              'expiresInSeconds': 300,
              'realmId': 'r',
              'userId': 'u',
            }),
          ],
        );
        final (repo, _) = _buildRepo(adapter);

        final result = await repo.loginWithPassword(
          email: 'u@e.com',
          password: 'pw',
        );

        expect(result, isA<AuthRequiresTotp>());
        final r = result as AuthRequiresTotp;
        expect(r.tempToken, 'tt');
        expect(r.secondFactors, ['totp']);
      },
    );

    test('consentRequired branch → AuthConsentRequired(agreements)', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'consentRequired': true,
            'agreements': [
              {
                'versionId': 'v1',
                'title': 'Terms',
                'summary': 's',
                'external_url': 'https://e',
                'agreement_type': 'terms',
                'effective_at': '2026-01-01T00:00:00Z',
                'mode': 'full_text',
                'version_no': 1,
              },
            ],
            'message': 'm',
            'expiresInSeconds': 300,
            'realmId': 'r',
            'userId': 'u',
          }),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.loginWithPassword(
        email: 'u@e.com',
        password: 'pw',
      );

      expect(result, isA<AuthConsentRequired>());
      final c = result as AuthConsentRequired;
      expect(c.agreements.length, 1);
      expect(c.agreements.single.id, 'v1');
      expect(c.agreements.single.title, 'Terms');
      expect(c.agreements.single.externalUrl, 'https://e');
    });

    test('401 → invalidCredentials', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(401, {'code': 'invalid_credentials'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.loginWithPassword(
        email: 'u@e.com',
        password: 'wrong',
      );

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).error.kind,
        AuthErrorKind.invalidCredentials,
      );
    });

    test('403 → accountNotActivated', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(403, {'code': 'email_not_verified'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.loginWithPassword(
        email: 'u@e.com',
        password: 'pw',
      );

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).error.kind,
        AuthErrorKind.accountNotActivated,
      );
    });

    test(
      'config missing (blank realm) → configMissing, no network call',
      () async {
        final adapter = _ScriptedAdapter(() => [_jsonBody(200, {})]); // unused
        final (repo, _) = _buildRepo(adapter, realmId: '', clientId: 'c');

        final result = await repo.loginWithPassword(
          email: 'u@e.com',
          password: 'pw',
        );

        expect(result, isA<AuthFailure>());
        expect((result as AuthFailure).error.kind, AuthErrorKind.configMissing);
        expect(
          adapter.requestedPaths,
          isEmpty,
          reason: 'config-missing preflight must skip the network entirely',
        );
      },
    );
  });

  group('HeraldAuthRepository.sendEmailOtp', () {
    test('200 → SendEmailOtpResult.sent', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {'message': 'sent', 'expiresInSeconds': 300}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.sendEmailOtp(email: 'u@e.com');

      expect(result.sent, isTrue);
      expect(result.agreements, isNull);
      expect(result.error, isNull);
    });

    test('409 email_not_registered → emailNotRegistered', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(409, {'code': 'email_not_registered', 'message': 'nope'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.sendEmailOtp(email: 'u@e.com');

      expect(result.sent, isFalse);
      expect(result.error!.kind, AuthErrorKind.emailNotRegistered);
    });

    test(
      '409 consent_required → SendEmailOtpResult.consent with agreements',
      () async {
        final adapter = _ScriptedAdapter(
          () => [
            _jsonBody(409, {
              'code': 'consent_required',
              'consentRequired': true,
              'message': 'consent',
              'agreements': [
                {
                  'version_id': 'v2',
                  'title': 'Privacy',
                  'agreement_type': 'privacy',
                  'effective_at': '2026-01-01T00:00:00Z',
                  'mode': 'full_text',
                  'version_no': 2,
                },
              ],
            }),
          ],
        );
        final (repo, _) = _buildRepo(adapter);

        final result = await repo.sendEmailOtp(email: 'u@e.com');

        expect(result.sent, isFalse);
        expect(
          result.error,
          isNull,
          reason: 'consent branch is not an error; it routes to /consent',
        );
        expect(result.agreements, isNotNull);
        expect(result.agreements!.single.id, 'v2');
        expect(result.agreements!.single.title, 'Privacy');
      },
    );

    test('429 → rateLimited', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(429, {'code': 'too_many_requests'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.sendEmailOtp(email: 'u@e.com');

      expect(result.error!.kind, AuthErrorKind.rateLimited);
    });
  });

  group('HeraldAuthRepository.loginWithEmailOtp', () {
    test('200 direct-success → AuthSuccess', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'accessToken': 'a2',
            'refreshToken': 'r2',
            'expiresIn': 3600,
            'refreshExpiresIn': 86400,
            'tokenType': 'Bearer',
          }),
        ],
      );
      final (repo, tokenStore) = _buildRepo(adapter);

      final result = await repo.loginWithEmailOtp(
        email: 'u@e.com',
        code: '123456',
      );

      expect(result, isA<AuthSuccess>());
      expect((result as AuthSuccess).session.accessToken, 'a2');
      expect(tokenStore.accessToken, 'a2');
    });

    test('200 inline consent JSON {message, consentRequired, agreements} → '
        'AuthConsentRequired', () async {
      // verify() is typed Response<BrowserTokenResponse>; the inline consent
      // JSON has no accessToken and would fail to deserialize. The repository
      // recovers the raw 200 body and lenient-parses the consentRequired
      // branch.
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'message': 'consent needed',
            'consentRequired': true,
            'agreements': [
              {
                'version_id': 'v3',
                'title': 'EULA',
                'agreement_type': 'eula',
                'effective_at': '2026-01-01T00:00:00Z',
                'mode': 'link',
                'version_no': 1,
                'external_url': 'https://eula',
              },
            ],
          }),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.loginWithEmailOtp(
        email: 'u@e.com',
        code: '123456',
      );

      expect(result, isA<AuthConsentRequired>());
      final c = result as AuthConsentRequired;
      expect(c.agreements.single.id, 'v3');
      expect(c.agreements.single.externalUrl, 'https://eula');
    });

    test('401 verify_turnstile_for_client_app → turnstileFailed', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(401, {'code': 'verify_turnstile_for_client_app'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.loginWithEmailOtp(
        email: 'u@e.com',
        code: '123456',
      );

      expect(result, isA<AuthFailure>());
      expect((result as AuthFailure).error.kind, AuthErrorKind.turnstileFailed);
    });
  });

  group('HeraldAuthRepository.register', () {
    test('verificationRequired:true → RegisterResult(true)', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {'message': 'pending', 'verificationRequired': true}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.register(email: 'u@e.com', password: 'pw');

      expect(result.verificationRequired, isTrue);
    });

    test('verificationRequired:false → RegisterResult(false)', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {'message': 'ok', 'verificationRequired': false}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.register(email: 'u@e.com', password: 'pw');

      expect(result.verificationRequired, isFalse);
    });
  });

  group('HeraldAuthRepository.reset password flow', () {
    test(
      'request then confirm happy path completes without throwing',
      () async {
        // request: 200 ResetPasswordRequestResponse (message only)
        // confirm: 200 void
        final adapter = _ScriptedAdapter(
          () => [
            _jsonBody(200, {'message': 'sent'}),
            _jsonBody(200, {}),
          ],
        );
        final (repo, _) = _buildRepo(adapter);

        await repo.requestResetPassword(email: 'u@e.com');
        await repo.confirmResetPassword(code: 'CODE', newPass: 'newpass');

        expect(adapter.requestedPaths, [
          '/api/auth/realm-1/reset_password/request',
          startsWith('/api/auth/realm-1/reset_password/confirm/'),
        ]);
      },
    );
  });

  group('HeraldAuthRepository.checkStatus', () {
    test('200 authenticated:true → true', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'authenticated': true,
            'credentialClass': 'first_party',
            'scopes': [],
            'realmId': 'r',
            'userId': 'u',
          }),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      expect(await repo.checkStatus(), isTrue);
    });

    test('401 → false (no throw)', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(401, {'code': 'unauthorized'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      expect(await repo.checkStatus(), isFalse);
    });
  });

  group('HeraldAuthRepository.verifyTotp', () {
    test('direct-success → AuthSuccess', () async {
      // handleVerifyTotp is typed Response<VerifyTotpResponse>; a direct
      // BrowserTokenResponse body fails to deserialize and is recovered.
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'accessToken': 'a3',
            'refreshToken': 'r3',
            'expiresIn': 3600,
            'refreshExpiresIn': 86400,
            'tokenType': 'Bearer',
          }),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.verifyTotp(tempToken: 'tt', code: '123456');

      expect(result, isA<AuthSuccess>());
      expect((result as AuthSuccess).session.accessToken, 'a3');
    });

    test('401 → sessionExpired', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(401, {'code': 'temp_token_expired'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.verifyTotp(tempToken: 'tt', code: '123456');

      expect(result, isA<AuthFailure>());
      expect((result as AuthFailure).error.kind, AuthErrorKind.sessionExpired);
    });
  });

  group('HeraldAuthRepository.logout', () {
    test('best-effort logout always clears TokenStore', () async {
      // Even a failing logout (500) must clear the local store.
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(500, {'code': 'internal'}),
        ],
      );
      final (repo, tokenStore) = _buildRepo(adapter);
      tokenStore.accessToken = 'stale';

      await repo.logout();

      expect(tokenStore.accessToken, isNull);
    });
  });
}
