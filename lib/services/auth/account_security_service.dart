import 'package:dio/dio.dart';

enum AccountSecurityErrorKind {
  wrongPassword,
  reauthExpired,
  passwordRejected,
  network,
}

class AccountSecurityException implements Exception {
  const AccountSecurityException(this.kind);

  final AccountSecurityErrorKind kind;
}

abstract class AccountSecurityService {
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

class HeraldAccountSecurityService implements AccountSecurityService {
  HeraldAccountSecurityService(this._dio);

  final Dio _dio;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final begin = await _dio.post<Map<String, dynamic>>(
        '/api/user/reauth',
        data: const {'targetOperation': 'change_password'},
      );
      final factors = begin.data?['availableFactors'];
      if (factors is! List || !factors.contains('password')) {
        throw const AccountSecurityException(AccountSecurityErrorKind.network);
      }

      final verify = await _dio.post<Map<String, dynamic>>(
        '/api/user/reauth/verify',
        data: {
          'targetOperation': 'change_password',
          'factor': 'password',
          'password': currentPassword,
        },
      );
      final reauthToken = verify.data?['reauthToken'];
      if (reauthToken is! String || reauthToken.isEmpty) {
        throw const AccountSecurityException(AccountSecurityErrorKind.network);
      }

      await _dio.post<void>(
        '/api/user/change-password',
        data: {'newPass': newPassword, 'reauthToken': reauthToken},
      );
    } on AccountSecurityException {
      rethrow;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      final path = error.requestOptions.path;
      if (path.endsWith('/reauth/verify') && statusCode == 401) {
        throw const AccountSecurityException(
          AccountSecurityErrorKind.wrongPassword,
        );
      }
      if (statusCode == 409) {
        throw const AccountSecurityException(
          AccountSecurityErrorKind.reauthExpired,
        );
      }
      if (path.endsWith('/change-password') && statusCode == 400) {
        throw const AccountSecurityException(
          AccountSecurityErrorKind.passwordRejected,
        );
      }
      throw const AccountSecurityException(AccountSecurityErrorKind.network);
    }
  }
}
