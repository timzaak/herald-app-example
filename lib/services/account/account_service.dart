import 'package:dio/dio.dart';

/// Membership display snapshot for the MyPage membership row — the
/// entitlement key + billing type from the most recent fulfillment. This is
/// display state only, NOT authoritative entitlement; see
/// [AccountOverview.membership].
class MembershipStatus {
  const MembershipStatus({
    required this.entitlementKey,
    required this.billingType,
  });

  /// e.g. `'pro_monthly'`.
  final String entitlementKey;

  /// `'recurring'` / `'one_time'` / `'non_renewing'`.
  final String billingType;
}

class AccountOverview {
  const AccountOverview({
    required this.email,
    required this.points,
    this.nickname,
    this.membership,
  });

  final String email;
  final String? nickname;
  final int points;

  /// Membership display snapshot. null = no membership (the MyPage renders
  /// the buy-entry tile only).
  ///
  /// EVIDENCE LIMITATION: this is **display state only** (the most recent
  /// fulfillment), NOT authoritative entitlement — the backend receipt /
  /// entitlement query is authoritative. `getOverview()` currently leaves this
  /// null because neither `/api/user/profile` nor `/api/user/wallets` carries
  /// an entitlement field (verified against the response shapes — do NOT
  /// invent a field).
  final MembershipStatus? membership;
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
