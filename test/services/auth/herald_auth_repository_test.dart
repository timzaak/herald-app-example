// Unit tests for HeraldAuthRepository.
//
// Exercises the lenient multi-branch parse and the AuthError classification
// table by scripting raw Herald response bodies through a real AuthApi mounted
// on a Dio with a hand-rolled HttpClientAdapter. Per the decoupling approach,
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

class _FailingTokenStore extends _FakeTokenStore {
  @override
  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) {
    throw StateError('storage unavailable');
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
  final List<Object?> requestedBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    requestedBodies.add(options.data);
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
/// When [withOauthApi] is true, an [OauthApi] on the same Dio is injected so the
/// native-login endpoints (apple native-login / google one-tap) can be exercised.
(HeraldAuthRepository, _FakeTokenStore) _buildRepo(
  _ScriptedAdapter adapter, {
  String realmId = 'realm-1',
  String clientId = 'client-1',
  String baseUrl = 'https://herald.test',
  bool withOauthApi = false,
}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = adapter;
  final authApi = AuthApi(dio, standardSerializers);
  final tokenStore = _FakeTokenStore();
  final repo = HeraldAuthRepositoryImpl(
    authApi,
    tokenStore,
    oauthApi: withOauthApi ? OauthApi(dio, standardSerializers) : null,
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
      'storage failure becomes AuthFailure instead of hanging the UI',
      () async {
        // WHY: token persistence is part of login completion. If it fails after
        // a 200 response, the repository must return a visible failure rather
        // than leak an async exception and leave the submit button loading.
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
        final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
          ..httpClientAdapter = adapter;
        final repo = HeraldAuthRepositoryImpl(
          AuthApi(dio, standardSerializers),
          _FailingTokenStore(),
          realmId: 'realm-1',
          clientId: 'client-1',
          baseUrl: 'https://herald.test',
        );

        final result = await repo.loginWithPassword(
          email: 'u@e.com',
          password: 'pw',
        );

        expect(result, isA<AuthFailure>());
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
      expect(c.agreements.single.agreementType, 'terms');
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
      expect(result.expiresInSeconds, 300);
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
        expect(result.agreements!.single.agreementType, 'privacy');
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

    test('401 invalid_code → verificationCodeInvalid', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(401, {'code': 'invalid_code'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.loginWithEmailOtp(
        email: 'u@e.com',
        code: '123456',
      );

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).error.kind,
        AuthErrorKind.verificationCodeInvalid,
      );
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

    test('email_already_exists → emailAlreadyRegistered', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(409, {'code': 'email_already_exists'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      await expectLater(
        repo.register(email: 'u@e.com', password: 'pw'),
        throwsA(
          isA<AuthErrorException>().having(
            (e) => e.error.kind,
            'kind',
            AuthErrorKind.emailAlreadyRegistered,
          ),
        ),
      );
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

    test('400 confirm response → resetCodeInvalid', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(400, {'code': 'invalid_code'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      await expectLater(
        repo.confirmResetPassword(code: 'CODE', newPass: 'newpass'),
        throwsA(
          isA<AuthErrorException>().having(
            (e) => e.error.kind,
            'kind',
            AuthErrorKind.resetCodeInvalid,
          ),
        ),
      );
    });
  });

  group('HeraldAuthRepository.email verification', () {
    test('resend then confirm calls both verification endpoints', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {'message': 'sent'}),
          _jsonBody(200, {}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      await repo.resendVerification(
        email: 'u@e.com',
        turnstileToken: 'turnstile-token',
      );
      await repo.confirmEmailVerification(code: '123456');

      expect(adapter.requestedPaths, [
        '/api/auth/realm-1/verify_email/trigger',
        '/api/auth/realm-1/verify_email/confirm/123456',
      ]);
    });

    test('404 confirm response → verificationCodeInvalid', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(404, {'code': 'invalid_code'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      await expectLater(
        repo.confirmEmailVerification(code: '123456'),
        throwsA(
          isA<AuthErrorException>().having(
            (e) => e.error.kind,
            'kind',
            AuthErrorKind.verificationCodeInvalid,
          ),
        ),
      );
    });
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

    test('backup-code verification uses backupCode and omits code', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'accessToken': 'a4',
            'refreshToken': 'r4',
            'tokenType': 'Bearer',
          }),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      final result = await repo.verifyTotp(
        tempToken: 'tt',
        backupCode: 'AB12CD34',
      );

      expect(result, isA<AuthSuccess>());
      final body = adapter.requestedBodies.single as Map<String, dynamic>;
      expect(body['backupCode'], 'AB12CD34');
      expect(body.containsKey('code'), isFalse);
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

  group('HeraldAuthRepository.currentUserId', () {
    // WHY: currentUserId reads /api/auth/status at
    // runtime; it is never persisted and must never throw (the caller blocks
    // the purchase when null). These cases mirror checkStatus's lenient-read
    // approach but assert the userId field instead of authenticated.

    test('200 with userId non-empty → returns it', () async {
      final userId = '11111111-2222-4333-8444-555555555555';
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'authenticated': true,
            'credentialClass': 'first_party',
            'scopes': [],
            'realmId': 'r',
            'userId': userId,
          }),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      expect(await repo.currentUserId(), userId);
    });

    test('200 with userId null/empty → returns null', () async {
      // WHEN the typed StatusResponse.userId is null, currentUserId must fall
      // through to the lenient map read and (finding nothing) return null —
      // never throw.
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'authenticated': true,
            'credentialClass': 'first_party',
            'scopes': [],
            'realmId': 'r',
            'userId': null,
          }),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      expect(await repo.currentUserId(), isNull);
    });

    test('200 with userId only in raw map (DTO shape drift) → lenient read '
        'returns it', () async {
      // Mirrors checkStatus's _bodyAuthenticated lenient fallback: if the
      // generated DTO somehow fails to surface userId, the raw map read must
      // still recover it.
      final userId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'authenticated': true,
            'credentialClass': 'first_party',
            'scopes': [],
            'realmId': 'r',
            'userId': userId,
          }),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      expect(await repo.currentUserId(), userId);
    });

    test('401 → returns null (no throw)', () async {
      // The interceptor's single refresh attempt has failed; currentUserId
      // must fail closed (null) so the caller blocks the purchase instead of
      // injecting an empty ownership binding.
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(401, {'code': 'unauthorized'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter);

      expect(await repo.currentUserId(), isNull);
    });

    test('config missing (blank realm) → null, no network call', () async {
      final adapter = _ScriptedAdapter(() => [_jsonBody(200, {})]); // unused
      final (repo, _) = _buildRepo(adapter, realmId: '', clientId: 'c');

      expect(await repo.currentUserId(), isNull);
      expect(
        adapter.requestedPaths,
        isEmpty,
        reason: 'config-missing preflight must skip the network entirely',
      );
    });

    test(
      'checkStatus seeds the snapshot — currentUserId reuses it (no 2nd call)',
      () async {
        // WHY: the startup checkStatus() probe already fetches
        // /api/auth/status; opening the purchase page must NOT trigger a
        // second round-trip for the userId. The adapter scripts exactly ONE
        // status response — a second fetch would drain the queue and throw.
        final userId = '11111111-2222-4333-8444-555555555555';
        final adapter = _ScriptedAdapter(
          () => [
            _jsonBody(200, {
              'authenticated': true,
              'credentialClass': 'first_party',
              'scopes': [],
              'realmId': 'r',
              'userId': userId,
            }),
          ],
        );
        final (repo, _) = _buildRepo(adapter);

        expect(await repo.checkStatus(), isTrue);
        expect(
          await repo.currentUserId(),
          userId,
          reason: 'currentUserId must reuse the checkStatus snapshot',
        );
        expect(
          adapter.requestedPaths,
          hasLength(1),
          reason: 'checkStatus + currentUserId share a single status call',
        );
      },
    );

    test(
      'logout clears the snapshot — currentUserId re-fetches (no stale id)',
      () async {
        // WHY: an account switch (logout) must never serve the previous user's
        // cached id to the purchase ownership binding. logout() drops the
        // snapshot so the next currentUserId() hits the network again.
        final adapter = _ScriptedAdapter(
          () => [
            _jsonBody(200, {
              'authenticated': true,
              'credentialClass': 'first_party',
              'scopes': [],
              'realmId': 'r',
              'userId': 'user-A',
            }),
            _jsonBody(200, {}), // logout response (best-effort, body unused)
            _jsonBody(200, {
              'authenticated': true,
              'credentialClass': 'first_party',
              'scopes': [],
              'realmId': 'r',
              'userId': 'user-B',
            }),
          ],
        );
        final (repo, _) = _buildRepo(adapter);

        expect(await repo.checkStatus(), isTrue); // call 1 → caches user-A
        await repo.logout(); // call 2 (logout) → clears the snapshot
        expect(
          await repo.currentUserId(),
          'user-B',
          reason: 'logout invalidated the cache — currentUserId re-fetches',
        );
        expect(
          adapter.requestedPaths,
          hasLength(3),
          reason: 'status + logout + status',
        );
      },
    );
  });

  group('HeraldAuthRepository.loginWithApple', () {
    test('direct-success (BrowserTokenSet) → AuthSuccess + persists', () async {
      // WHY: native-login returns a flattened BrowserTokenSet body that the
      // generator cannot deserialize into AppleNativeCodeResponse — the
      // repository must recover the raw 200 body and parse accessToken,
      // exactly like password login's direct-success branch.
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'message': 'ok',
            'userId': 'u1',
            'accessToken': 'a-apple',
            'refreshToken': 'r-apple',
            'expiresIn': 3600,
            'refreshExpiresIn': 86400,
            'tokenType': 'Bearer',
          }),
        ],
      );
      final (repo, tokenStore) = _buildRepo(adapter, withOauthApi: true);

      final result = await repo.loginWithApple(identityToken: 'apple.jwt');

      expect(result, isA<AuthSuccess>());
      final s = (result as AuthSuccess).session;
      expect(s.accessToken, 'a-apple');
      expect(s.refreshToken, 'r-apple');
      expect(tokenStore.accessToken, 'a-apple');
      expect(tokenStore.refreshToken, 'r-apple');
      expect(
        adapter.requestedPaths.last,
        contains('/apple/native-login'),
        reason: 'routed to the apple native-login endpoint',
      );
    });

    test('401 → AuthFailure(invalidCredentials)', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(401, {'code': 'invalid_token', 'message': 'bad'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter, withOauthApi: true);

      final result = await repo.loginWithApple(identityToken: 'apple.jwt');

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).error.kind,
        AuthErrorKind.invalidCredentials,
      );
    });

    test('404 → AuthFailure(providerUnavailable)', () async {
      // WHY: a 404 means the realm has not enabled the apple provider — the UI
      // must surface a distinct kind so the button can be hidden / retried.
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(404, {'code': 'not_found', 'message': 'no provider'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter, withOauthApi: true);

      final result = await repo.loginWithApple(identityToken: 'apple.jwt');

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).error.kind,
        AuthErrorKind.providerUnavailable,
      );
    });

    test('503 → AuthFailure(serviceUnavailable)', () async {
      // WHY: 503 means Apple JWKS is unreachable — a transient upstream failure
      // distinct from invalid credentials or a missing provider.
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(503, {'code': 'upstream', 'message': 'jwks down'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter, withOauthApi: true);

      final result = await repo.loginWithApple(identityToken: 'apple.jwt');

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).error.kind,
        AuthErrorKind.serviceUnavailable,
      );
    });

    test(
      'config missing (blank realm) → AuthFailure(configMissing), no request',
      () async {
        final adapter = _ScriptedAdapter(() => []);
        final (repo, _) = _buildRepo(
          adapter,
          realmId: '',
          clientId: 'client-1',
          withOauthApi: true,
        );

        final result = await repo.loginWithApple(identityToken: 'apple.jwt');

        expect(result, isA<AuthFailure>());
        expect((result as AuthFailure).error.kind, AuthErrorKind.configMissing);
        expect(adapter.requestedPaths, isEmpty);
      },
    );

    test('no OauthApi injected → AuthFailure(configMissing)', () async {
      // WHY: a repo constructed without the OauthApi (legacy callers) must not
      // throw on a native call — it fails closed with configMissing.
      final adapter = _ScriptedAdapter(() => []);
      final (repo, _) = _buildRepo(adapter, withOauthApi: false);

      final result = await repo.loginWithApple(identityToken: 'apple.jwt');

      expect(result, isA<AuthFailure>());
      expect((result as AuthFailure).error.kind, AuthErrorKind.configMissing);
      expect(adapter.requestedPaths, isEmpty);
    });
  });

  group('HeraldAuthRepository.loginWithGoogleOneTap', () {
    test('direct-success (BrowserTokenSet) → AuthSuccess + persists', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {
            'message': 'ok',
            'userId': 'u-g',
            'accessToken': 'a-google',
            'refreshToken': 'r-google',
            'expiresIn': 3600,
            'refreshExpiresIn': 86400,
            'tokenType': 'Bearer',
          }),
        ],
      );
      final (repo, tokenStore) = _buildRepo(adapter, withOauthApi: true);

      final result = await repo.loginWithGoogleOneTap(credential: 'google.jwt');

      expect(result, isA<AuthSuccess>());
      expect((result as AuthSuccess).session.accessToken, 'a-google');
      expect(tokenStore.accessToken, 'a-google');
      expect(
        adapter.requestedPaths.last,
        contains('/google/one-tap'),
        reason: 'routed to the google one-tap endpoint',
      );
    });

    test('401 (unverified email) → AuthFailure(invalidCredentials)', () async {
      // WHY: Herald's google one-tap handler forces email_verified == true;
      // a 401 here covers invalid/expired token OR unverified email — both map
      // to invalidCredentials so the UI shows a single retry message.
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(401, {'code': 'invalid_token', 'message': 'bad'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter, withOauthApi: true);

      final result = await repo.loginWithGoogleOneTap(credential: 'google.jwt');

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).error.kind,
        AuthErrorKind.invalidCredentials,
      );
    });

    test('404 → AuthFailure(providerUnavailable)', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(404, {'code': 'not_found', 'message': 'no provider'}),
        ],
      );
      final (repo, _) = _buildRepo(adapter, withOauthApi: true);

      final result = await repo.loginWithGoogleOneTap(credential: 'google.jwt');

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).error.kind,
        AuthErrorKind.providerUnavailable,
      );
    });

    test('config missing → AuthFailure(configMissing), no request', () async {
      final adapter = _ScriptedAdapter(() => []);
      final (repo, _) = _buildRepo(adapter, clientId: '', withOauthApi: true);

      final result = await repo.loginWithGoogleOneTap(credential: 'google.jwt');

      expect(result, isA<AuthFailure>());
      expect((result as AuthFailure).error.kind, AuthErrorKind.configMissing);
      expect(adapter.requestedPaths, isEmpty);
    });
  });
}
