import 'package:dio/dio.dart';

class PublicAuthConfig {
  const PublicAuthConfig({
    required this.registrationEnabled,
    required this.requireEmailVerification,
  });

  final bool registrationEnabled;
  final bool requireEmailVerification;
}

abstract class PublicAuthConfigService {
  Future<PublicAuthConfig> getConfig();
}

class HeraldPublicAuthConfigService implements PublicAuthConfigService {
  HeraldPublicAuthConfigService(this._dio, this._realmId);

  final Dio _dio;
  final String _realmId;

  @override
  Future<PublicAuthConfig> getConfig() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/public-config/$_realmId',
    );
    final registration = response.data?['registration'];
    if (registration is! Map) {
      throw const FormatException('public config registration is missing');
    }
    return PublicAuthConfig(
      registrationEnabled: registration['enabled'] == true,
      requireEmailVerification:
          registration['requireEmailVerification'] == true,
    );
  }
}
