import 'dart:convert';
import 'dart:typed_data';

import 'package:app/services/auth/legal_agreement_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _LegalAgreementAdapter implements HttpClientAdapter {
  _LegalAgreementAdapter(this.body);

  final Map<String, dynamic> body;
  String? requestedPath;
  Map<String, dynamic>? requestedQuery;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPath = options.path;
    requestedQuery = options.queryParameters;
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
    'requests the selected public agreement so login links show realm content',
    () async {
      final adapter = _LegalAgreementAdapter({
        'content': '# Terms',
        'external_url': 'https://example.com/terms',
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
        ..httpClientAdapter = adapter;
      final service = HeraldLegalAgreementService(dio, 'realm-1');

      final agreement = await service.getAgreement(
        agreementType: 'terms_of_service',
        locale: 'zh-CN',
      );

      expect(
        adapter.requestedPath,
        '/api/legal/realm-1/agreements/terms_of_service',
      );
      expect(adapter.requestedQuery, {'locale': 'zh-CN'});
      expect(agreement.content, '# Terms');
      expect(agreement.externalUrl, 'https://example.com/terms');
    },
  );

  test(
    'non-string agreement content remains readable instead of crashing',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://herald.test'))
        ..httpClientAdapter = _LegalAgreementAdapter({
          'content': {'section': 'Privacy'},
        });
      final service = HeraldLegalAgreementService(dio, 'realm-1');

      final agreement = await service.getAgreement(
        agreementType: 'privacy_policy',
        locale: 'en',
      );

      expect(agreement.content, contains('"section": "Privacy"'));
    },
  );
}
