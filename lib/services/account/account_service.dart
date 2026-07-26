import 'package:dio/dio.dart';

class AccountOverview {
  const AccountOverview({
    required this.email,
    required this.points,
    this.nickname,
  });

  final String email;
  final String? nickname;
  final int points;
}

abstract class AccountService {
  Future<AccountOverview> getOverview();
}

class HeraldAccountService implements AccountService {
  HeraldAccountService(this._dio);

  final Dio _dio;

  @override
  Future<AccountOverview> getOverview() async {
    final responses = await Future.wait([
      _dio.get<Map<String, dynamic>>('/api/user/profile'),
      _dio.get<Map<String, dynamic>>('/api/user/wallets'),
    ]);
    final profile = responses[0].data;
    final wallets = responses[1].data;
    if (profile == null || wallets == null) {
      throw const FormatException('Missing account response');
    }
    return AccountOverview(
      email: _string(profile, 'email'),
      nickname: profile['nickname'] as String?,
      points: _integer(wallets, 'crossBucketTotal'),
    );
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) return value;
    throw FormatException('Invalid $key');
  }

  static int _integer(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw FormatException('Invalid $key');
  }
}
