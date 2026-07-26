import '../../config/settings.dart';
import '../../util/local_storage.dart';

/// Persists the Herald Bearer session (design §5.3 backing store).
///
/// Backed by [LocalStorage] (shared_preferences wrapper) and the [Settings]
/// token keys. Refresh is reactive — the interceptor refreshes on a 401 — so
/// only the access/refresh tokens are persisted; no expiry is stored.
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

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    await LocalStorage.save(Settings.accessTokenKey, accessToken);
    await LocalStorage.save(Settings.refreshTokenKey, refreshToken);
  }

  Future<void> clear() async {
    await LocalStorage.remove(Settings.accessTokenKey);
    await LocalStorage.remove(Settings.refreshTokenKey);
  }
}
