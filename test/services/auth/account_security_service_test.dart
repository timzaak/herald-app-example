import 'dart:convert';
import 'dart:typed_data';

import 'package:app/services/auth/account_security_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.responses);

  final List<ResponseBody> responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: const {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  test('change password obtains and consumes a scoped reauth ticket', () async {
    final adapter = _SequenceAdapter([
      _json(200, {
        'availableFactors': ['password'],
      }),
      _json(200, {'reauthToken': 'ticket-1', 'expiresIn': 120}),
      _json(200, {}),
    ]);
    final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
      ..httpClientAdapter = adapter;

    await HeraldAccountSecurityService(dio).changePassword(
      currentPassword: 'OldPassword1',
      newPassword: 'NewPassword1',
    );

    expect(adapter.requests.map((request) => request.path), [
      '/api/user/reauth',
      '/api/user/reauth/verify',
      '/api/user/change-password',
    ]);
    expect(adapter.requests[1].data, {
      'targetOperation': 'change_password',
      'factor': 'password',
      'password': 'OldPassword1',
    });
    expect(adapter.requests[2].data, {
      'newPass': 'NewPassword1',
      'reauthToken': 'ticket-1',
    });
  });

  test(
    'wrong current password is classified without changing password',
    () async {
      final adapter = _SequenceAdapter([
        _json(200, {
          'availableFactors': ['password'],
        }),
        _json(401, {'code': 'invalid_credentials'}),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
        ..httpClientAdapter = adapter;

      await expectLater(
        HeraldAccountSecurityService(
          dio,
        ).changePassword(currentPassword: 'wrong', newPassword: 'NewPassword1'),
        throwsA(
          isA<AccountSecurityException>().having(
            (error) => error.kind,
            'kind',
            AccountSecurityErrorKind.wrongPassword,
          ),
        ),
      );
      expect(adapter.requests, hasLength(2));
    },
  );
}
