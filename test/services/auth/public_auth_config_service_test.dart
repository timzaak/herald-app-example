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
}
