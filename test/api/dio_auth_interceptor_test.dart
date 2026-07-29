// Unit tests for DioAuthInterceptor.
//
// Covers the five transport-layer scenarios whose failure attribution belongs
// to the transport layer: Authorization injection; 401 refresh+replay; concurrent 401 single
// refresh; refresh-failure clear+onSessionEnd; refresh endpoint 401 no-recursion.
//
// No new deps (Rule 2): the interceptor is exercised through a real Dio with a
// hand-rolled HttpClientAdapter that scripts per-call responses. The test
// TokenStore is an in-memory fake so we do not touch shared_preferences.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/dio_auth_interceptor.dart';
import 'package:app/services/auth/token_store.dart';

/// In-memory TokenStore replacement. Avoids shared_preferences in unit tests
/// and gives synchronous, inspectable token state.
class _FakeTokenStore implements TokenStore {
  String? accessToken;
  String? refreshToken;
  bool cleared = false;

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
    cleared = false;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    cleared = true;
  }
}

/// Hand-rolled Dio adapter that returns scripted [ResponseBody]s in sequence,
/// recording the Authorization header seen on each outgoing request. No new
/// test dependency (Rule 2 — http_mock_adapter not added).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(List<ResponseBody> Function() responses)
    : _responses = responses();

  final List<ResponseBody> _responses;
  final List<String?> authorizationHeaders = [];
  final List<String> requestedPaths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authHeader = options.headers['Authorization'];
    authorizationHeaders.add(authHeader is String ? authHeader : null);
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
    ResponseBody.fromString(jsonEncode(body), status);

/// Builds a Dio with the given scripted [adapter], mounting the interceptor
/// bound to [tokenStore]/[refreshFn]/[onSessionEnd].
Dio _buildDio(
  _FakeTokenStore tokenStore,
  Future<bool> Function() refreshFn,
  Future<void> Function() onSessionEnd,
  _ScriptedAdapter adapter,
) {
  final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
    ..httpClientAdapter = adapter;
  final interceptor = DioAuthInterceptor(tokenStore, refreshFn, onSessionEnd)
    ..attachDio(dio);
  dio.interceptors.add(interceptor);
  return dio;
}

void main() {
  group('DioAuthInterceptor', () {
    test(
      '(a) injects Authorization when token present; omits when null',
      () async {
        final tokenStore = _FakeTokenStore()..accessToken = 'access-abc';
        final adapter = _ScriptedAdapter(
          () => [
            _jsonBody(200, {'ok': true}),
          ],
        );
        final dio = _buildDio(
          tokenStore,
          () async => false,
          () async {},
          adapter,
        );

        await dio.get('/api/auth/status');

        expect(adapter.authorizationHeaders.single, 'Bearer access-abc');

        // Now with no token: no Authorization header must be attached.
        final adapter2 = _ScriptedAdapter(
          () => [
            _jsonBody(200, {'ok': true}),
          ],
        );
        final dio2 = Dio(BaseOptions(baseUrl: 'https://herald.test'))
          ..httpClientAdapter = adapter2;
        final tokenStore2 = _FakeTokenStore(); // accessToken == null
        dio2.interceptors.add(
          DioAuthInterceptor(tokenStore2, () async => false, () async {})
            ..attachDio(dio2),
        );

        await dio2.get('/api/auth/status');

        expect(adapter2.authorizationHeaders.single, isNull);
      },
    );

    test(
      '(b) 401 on a non-refresh request triggers refresh then replays',
      () async {
        final tokenStore = _FakeTokenStore()..accessToken = 'expired-token';
        var refreshCalls = 0;
        Future<bool> refreshFn() async {
          refreshCalls++;
          // Simulate AuthApi.refresh persisting a new token into the store.
          await tokenStore.save(
            accessToken: 'fresh-token',
            refreshToken: 'fresh-refresh',
          );
          return true;
        }

        var sessionEnded = false;
        // First call 401, replay 200.
        final adapter = _ScriptedAdapter(
          () => [
            _jsonBody(401, {'error': 'expired'}),
            _jsonBody(200, {'ok': 1}),
          ],
        );
        final dio = _buildDio(
          tokenStore,
          refreshFn,
          () async => sessionEnded = true,
          adapter,
        );

        final response = await dio.get('/api/auth/status');

        expect(refreshCalls, 1);
        expect(
          sessionEnded,
          isFalse,
          reason: 'successful refresh must not end the session',
        );
        // The original request carried the stale token; the replay carried fresh.
        expect(adapter.authorizationHeaders, [
          'Bearer expired-token',
          'Bearer fresh-token',
        ]);
        expect(adapter.requestedPaths, [
          '/api/auth/status',
          '/api/auth/status',
        ]);
        expect(response.statusCode, 200);
      },
    );

    test('(c) two parallel 401s trigger refresh exactly once', () async {
      final tokenStore = _FakeTokenStore()..accessToken = 'expired-token';
      var refreshCalls = 0;
      final refreshGate = Completer<void>();
      Future<bool> refreshFn() async {
        refreshCalls++;
        // Hold the first (and only) refresh open until both 401s are queued,
        // proving the second caller awaits the same in-flight future.
        await refreshGate.future;
        await tokenStore.save(
          accessToken: 'fresh-token',
          refreshToken: 'fresh-refresh',
        );
        return true;
      }

      // Four scripted responses: two 401s for the parallel requests, then two
      // 200 replays.
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(401, {}),
          _jsonBody(401, {}),
          _jsonBody(200, {'i': 1}),
          _jsonBody(200, {'i': 2}),
        ],
      );
      final dio = _buildDio(tokenStore, refreshFn, () async {}, adapter);

      final futures = [
        dio.get('/api/auth/status'),
        dio.get('/api/auth/logout'),
      ];
      // Let both requests hit 401 and queue on the single refresh future.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      refreshGate.complete();

      final results = await Future.wait(futures);

      expect(
        refreshCalls,
        1,
        reason: 'concurrent 401s must share a single in-flight refresh',
      );
      expect(results.map((r) => r.statusCode), [200, 200]);
      // Both original requests carried the stale token; both replays carried
      // fresh.
      expect(adapter.authorizationHeaders, [
        'Bearer expired-token',
        'Bearer expired-token',
        'Bearer fresh-token',
        'Bearer fresh-token',
      ]);
    });

    test(
      '(d) refresh failure clears TokenStore, calls onSessionEnd, rejects',
      () async {
        final tokenStore = _FakeTokenStore()..accessToken = 'expired-token';
        var refreshCalls = 0;
        Future<bool> refreshFn() async {
          refreshCalls++;
          return false; // refresh failed
        }

        var sessionEnded = 0;
        final adapter = _ScriptedAdapter(() => [_jsonBody(401, {})]);
        final dio = _buildDio(
          tokenStore,
          refreshFn,
          () async => sessionEnded++,
          adapter,
        );

        expect(
          dio.get('/api/auth/status'),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
        // Let the async refresh+clear+onSessionEnd chain settle.
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(refreshCalls, 1);
        expect(
          tokenStore.cleared,
          isTrue,
          reason: 'refresh failure must clear the token store',
        );
        expect(
          sessionEnded,
          1,
          reason: 'refresh failure must invoke onSessionEnd for the waiter',
        );

        // Two parallel waiters share a single refresh; both reject with the
        // original 401; onSessionEnd fires once for the shared refresh (the
        // cleanup is bound to the single-flight, not per-waiter).
        final adapter2 = _ScriptedAdapter(
          () => [_jsonBody(401, {}), _jsonBody(401, {})],
        );
        final tokenStore2 = _FakeTokenStore()..accessToken = 'expired-token';
        var refreshCalls2 = 0;
        var sessionEnded2 = 0;
        // Gate the refresh so both 401s deterministically overlap on the same
        // in-flight future before it completes.
        final refreshGate2 = Completer<void>();
        final dio2 = _buildDio(
          tokenStore2,
          () async {
            refreshCalls2++;
            await refreshGate2.future;
            return false;
          },
          () async => sessionEnded2++,
          adapter2,
        );

        final futures2 = [
          dio2.get('/api/auth/status'),
          dio2.get('/api/auth/logout'),
        ];
        for (final f in futures2) {
          expect(f, throwsA(isA<DioException>()));
        }
        // Let both requests hit 401 and queue on the single refresh future.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        refreshGate2.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(refreshCalls2, 1, reason: 'both waiters share one refresh');
        expect(tokenStore2.cleared, isTrue);
        expect(
          sessionEnded2,
          1,
          reason: 'onSessionEnd runs once for the shared refresh',
        );
      },
    );

    test(
      '(e) 401 on /api/auth/browser-token/refresh does NOT recurse into refresh',
      () async {
        final tokenStore = _FakeTokenStore()
          ..accessToken = 'whatever'
          ..refreshToken = 'dead-refresh';
        var refreshCalls = 0;
        var sessionEnded = 0;
        final adapter = _ScriptedAdapter(() => [_jsonBody(401, {})]);
        final dio = _buildDio(
          tokenStore,
          () async {
            refreshCalls++;
            return true;
          },
          () async => sessionEnded++,
          adapter,
        );

        expect(
          dio.post('/api/auth/browser-token/refresh'),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(
          refreshCalls,
          0,
          reason: 'a 401 from the refresh endpoint must not trigger refresh',
        );
        expect(
          sessionEnded,
          0,
          reason: 'refresh-endpoint 401 must not end the session',
        );
        expect(
          tokenStore.cleared,
          isFalse,
          reason: 'refresh-endpoint 401 must not clear tokens',
        );
        // And no Authorization was injected for the refresh request.
        expect(adapter.authorizationHeaders.single, isNull);
      },
    );

    test('(f) a 401 on the replayed request is not refreshed again', () async {
      final tokenStore = _FakeTokenStore()..accessToken = 'expired-token';
      var refreshCalls = 0;
      Future<bool> refreshFn() async {
        refreshCalls++;
        // Simulate AuthApi.refresh persisting a new token into the store.
        await tokenStore.save(
          accessToken: 'fresh-token',
          refreshToken: 'fresh-refresh',
        );
        return true;
      }

      // First call 401 (triggers refresh + replay); the replay also 401.
      // The replayed 401 must surface directly — no second refresh — so a
      // persistently-401 resource (valid token but no permission, or a new
      // token that is also rejected) cannot loop refresh forever.
      final adapter = _ScriptedAdapter(
        () => [_jsonBody(401, {}), _jsonBody(401, {})],
      );
      final dio = _buildDio(tokenStore, refreshFn, () async {}, adapter);

      await expectLater(
        dio.get('/api/auth/status'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            401,
          ),
        ),
      );

      expect(
        refreshCalls,
        1,
        reason: 'a 401 on the replay must not trigger a second refresh',
      );
    });
  });
}
