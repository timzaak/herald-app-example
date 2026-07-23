import '../../config/settings.dart';
import '../../util/local_storage.dart';

/// Persists the Herald Bearer session (design §5.3 backing store).
///
/// Backed by [LocalStorage] (shared_preferences wrapper) and the [Settings]
/// token keys. This store performs no TTL math — refresh timing is decided by
/// [DioAuthInterceptor]. [expiresAt] is stored as an ISO-8601 string.
///
/// API surface is frozen for FL-D02 (HeraldAuthRepository + startup bootstrap).
class TokenStore {
  Future<String?> getAccessToken() async {
    final value = await LocalStorage.get(Settings.accessTokenKey);
    return value is String ? value : null;
  }

  Future<String?> getRefreshToken() async {
    final value = await LocalStorage.get(Settings.refreshTokenKey);
    return value is String ? value : null;
  }

  Future<DateTime?> getAccessExpiresAt() async {
    final value = await LocalStorage.get(Settings.accessExpiresAtKey);
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    DateTime? expiresAt,
  }) async {
    await LocalStorage.save(Settings.accessTokenKey, accessToken);
    await LocalStorage.save(Settings.refreshTokenKey, refreshToken);
    await LocalStorage.save(
      Settings.accessExpiresAtKey,
      expiresAt?.toUtc().toIso8601String() ?? '',
    );
  }

  Future<void> clear() async {
    await LocalStorage.remove(Settings.accessTokenKey);
    await LocalStorage.remove(Settings.refreshTokenKey);
    await LocalStorage.remove(Settings.accessExpiresAtKey);
  }
}
