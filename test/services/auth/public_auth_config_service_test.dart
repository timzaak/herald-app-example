import 'dart:convert';
import 'dart:typed_data';

import 'package:app/services/auth/public_auth_config_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _PublicConfigAdapter implements HttpClientAdapter {
  _PublicConfigAdapter(this.body);

  final Map<String, dynamic> body;
  String? requestedPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPath = options.path;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: const {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'reads the public registration capability for the configured realm',
    () async {
      final adapter = _PublicConfigAdapter({
        'registration': {'enabled': true, 'requireEmailVerification': true},
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
        ..httpClientAdapter = adapter;
      final service = HeraldPublicAuthConfigService(dio, 'realm-1');

      final config = await service.getConfig();

      expect(adapter.requestedPath, '/api/public-config/realm-1');
      expect(config.registrationEnabled, isTrue);
      expect(config.requireEmailVerification, isTrue);
    },
  );

  test(
    'malformed public config fails instead of enabling registration',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
        ..httpClientAdapter = _PublicConfigAdapter({'realmName': 'Realm'});
      final service = HeraldPublicAuthConfigService(dio, 'realm-1');

      await expectLater(service.getConfig(), throwsFormatException);
    },
  );

  test(
    'parses enabled oauthProviders with clientId into enabledNativeProviderNames',
    () async {
      // WHY: native-login button visibility depends on public-config reporting
      // the provider enabled with a non-empty clientId (DEC-006/007). A provider
      // missing clientId or disabled must not light up a dead login button.
      final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
        ..httpClientAdapter = _PublicConfigAdapter({
          'registration': {'enabled': true, 'requireEmailVerification': false},
          'oauthProviders': [
            {
              'name': 'apple',
              'displayName': 'Apple',
              'enabled': true,
              'clientId': 'apple-svc-id',
            },
            {'name': 'google', 'displayName': 'Google', 'enabled': true},
            {
              'name': 'github',
              'displayName': 'GitHub',
              'enabled': false,
              'clientId': 'gh-id',
            },
          ],
        });
      final service = HeraldPublicAuthConfigService(dio, 'realm-1');

      final config = await service.getConfig();

      expect(config.enabledNativeProviderNames, {'apple'});
      expect(config.oauthProviders, hasLength(3));
    },
  );

  test('missing oauthProviders array → empty list (buttons hidden)', () async {
    // WHY: older backends may omit oauthProviders; the login page must hide
    // native buttons rather than throw (fail closed, DEC-006).
    final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
      ..httpClientAdapter = _PublicConfigAdapter({
        'registration': {'enabled': true, 'requireEmailVerification': false},
      });
    final service = HeraldPublicAuthConfigService(dio, 'realm-1');

    final config = await service.getConfig();

    expect(config.oauthProviders, isEmpty);
    expect(config.enabledNativeProviderNames, isEmpty);
  });
}
