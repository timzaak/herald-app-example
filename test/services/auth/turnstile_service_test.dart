// Unit tests for HeraldTurnstileService (design §5.4, §6.1, FL-D02).
//
// Covers: enabled-config caching; 401 → disabled-config caching (and the
// underlying getTurnstileStatus call count stays 1 across two getConfig calls
// — cache hit); obtainToken null when disabled; obtainToken delegates to the
// injected getTurnstileToken shim with the configured siteKey when enabled.
//
// No new deps (Rule 2). Same scripted-adapter approach as
// test/api/dio_auth_interceptor_test.dart and herald_auth_repository_test.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/auth/turnstile_service.dart';

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

AuthApi _authApi(_ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
    ..httpClientAdapter = adapter;
  return AuthApi(dio, standardSerializers);
}

void main() {
  group('HeraldTurnstileService.getConfig', () {
    test('200 enabled:true caches and returns enabled', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {'enabled': true, 'siteKey': 'site-abc'}),
        ],
      );
      final service = HeraldTurnstileService(
        _authApi(adapter),
        'realm-1',
        'client-1',
      );

      final first = await service.getConfig();
      final second = await service.getConfig();

      expect(first.enabled, isTrue);
      expect(first.siteKey, 'site-abc');
      expect(
        second.enabled,
        isTrue,
        reason: 'second call must hit the cache (same config)',
      );
      expect(
        adapter.requestedPaths
            .where((p) => p.endsWith('/turnstile/status'))
            .length,
        1,
        reason:
            'underlying getTurnstileStatus must be called exactly once '
            'across two getConfig calls — cache hit on the second',
      );
    });

    test(
      '401 caches disabled and returns enabled:false on subsequent calls',
      () async {
        // Only one scripted response: the 401. A second network call would crash
        // the adapter (no responses left), proving the second getConfig hit the
        // cache rather than re-probing.
        final adapter = _ScriptedAdapter(
          () => [
            _jsonBody(401, {'code': 'unauthorized'}),
          ],
        );
        final service = HeraldTurnstileService(
          _authApi(adapter),
          'realm-1',
          'client-1',
        );

        final first = await service.getConfig();
        final second = await service.getConfig();

        expect(
          first.enabled,
          isFalse,
          reason:
              '401 from Herald (illegal/disabled Client App) degrades to '
              'disabled rather than throwing',
        );
        expect(
          second.enabled,
          isFalse,
          reason:
              'disabled config is cached so we do not re-probe on every '
              'submit',
        );
        expect(
          adapter.requestedPaths
              .where((p) => p.endsWith('/turnstile/status'))
              .length,
          1,
          reason: 'cache hit on second getConfig — only one network probe',
        );
      },
    );
  });

  group('HeraldTurnstileService.obtainToken', () {
    test('returns null when disabled', () async {
      final adapter = _ScriptedAdapter(
        () => [
          _jsonBody(200, {'enabled': false}),
        ],
      );
      final service = HeraldTurnstileService(
        _authApi(adapter),
        'realm-1',
        'client-1',
        // Shim would fail the test if invoked.
        obtainTokenFn: ({String? siteKey}) async {
          fail('obtainToken must not invoke the challenge when disabled');
        },
      );

      expect(await service.obtainToken(), isNull);
    });

    test(
      'delegates to getTurnstileToken(siteKey: config.siteKey) when enabled',
      () async {
        final adapter = _ScriptedAdapter(
          () => [
            _jsonBody(200, {'enabled': true, 'siteKey': 'site-xyz'}),
          ],
        );
        String? capturedSiteKey;
        final service = HeraldTurnstileService(
          _authApi(adapter),
          'realm-1',
          'client-1',
          obtainTokenFn: ({String? siteKey}) async {
            capturedSiteKey = siteKey;
            return 'token-from-cloudflare';
          },
        );

        final token = await service.obtainToken();

        expect(token, 'token-from-cloudflare');
        expect(
          capturedSiteKey,
          'site-xyz',
          reason:
              'obtainToken must forward the configured siteKey to the '
              'challenge helper (single-use token, never cached)',
        );
      },
    );
  });
}
