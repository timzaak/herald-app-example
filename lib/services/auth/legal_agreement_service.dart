import 'dart:convert';

import 'package:dio/dio.dart';

class LegalAgreement {
  const LegalAgreement({required this.content, this.externalUrl});

  final String content;
  final String? externalUrl;
}

abstract class LegalAgreementService {
  Future<LegalAgreement> getAgreement({
    required String agreementType,
    required String locale,
  });
}

class HeraldLegalAgreementService implements LegalAgreementService {
  HeraldLegalAgreementService(this._dio, this._realmId);

  final Dio _dio;
  final String _realmId;

  @override
  Future<LegalAgreement> getAgreement({
    required String agreementType,
    required String locale,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/legal/$_realmId/agreements/$agreementType',
      queryParameters: {'locale': locale},
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('legal agreement response is empty');
    }

    final content = data['content'];
    return LegalAgreement(
      content: switch (content) {
        String value => value,
        null => '',
        _ => const JsonEncoder.withIndent('  ').convert(content),
      },
      externalUrl: data['external_url'] is String
          ? data['external_url'] as String
          : null,
    );
  }
}
