// ignore_for_file: prefer_initializing_formals
// The HeraldTurnstileService constructor has a default-valued `obtainTokenFn`
// param, which cannot use an initializing formal (`this._obtainTokenFn`).
import 'package:api_client/api_client.dart';
import 'package:app/util/turnstile_util.dart';

/// Per-Client-App Turnstile configuration (design §5.4).
class TurnstileConfig {
  final bool enabled;
  final String? siteKey;
  const TurnstileConfig({this.enabled = false, this.siteKey});
}

/// Resolves Turnstile configuration and obtains single-use challenge tokens.
///
/// Why an abstraction: Herald gates Turnstile per Client App, and a disabled /
/// illegal Client App returns 401 from `/turnstile/status` (inconsistent with
/// the 400 elsewhere — design §3.1). Concrete implementations must never throw
/// on config failure; they degrade to [TurnstileConfig] disabled.
abstract class TurnstileService {
  /// Returns the cached / freshly-fetched config for this realm+client. Cached
  /// for process lifetime (no TTL — design §1.4). A 401 from Herald is treated
  /// as "disabled" and cached, so subsequent calls do not re-probe.
  Future<TurnstileConfig> getConfig();

  /// Returns a single-use Turnstile token, or null when Turnstile is disabled.
  /// The token is never cached (single-use, design §1.4).
  Future<String?> obtainToken();
}

/// Function signature for the invisible-challenge helper injected into
/// [HeraldTurnstileService] (so tests can assert delegation without depending
/// on the real Cloudflare widget).
typedef GetTurnstileTokenFn = Future<String?> Function({String? siteKey});

/// Herald-backed [TurnstileService]. Reads `enabled` + `siteKey` from
/// `AuthApi.getTurnstileStatus` and caches by `realmId+clientId`.
class HeraldTurnstileService implements TurnstileService {
  HeraldTurnstileService(
    this._authApi,
    this._realmId,
    this._clientId, {
    GetTurnstileTokenFn obtainTokenFn = getTurnstileToken,
  }) : _obtainTokenFn = obtainTokenFn;

  final AuthApi _authApi;
  final String _realmId;
  final String _clientId;
  final GetTurnstileTokenFn _obtainTokenFn;

  // Cache for process lifetime (no TTL). Null = not yet fetched.
  TurnstileConfig? _cached;

  @override
  Future<TurnstileConfig> getConfig() async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final response = await _authApi.getTurnstileStatus(
        realmId: _realmId,
        clientId: _clientId,
      );
      final data = response.data;
      final config = TurnstileConfig(
        enabled: data?.enabled ?? false,
        siteKey: data?.siteKey,
      );
      _cached = config;
      return config;
    } on Object {
      // Herald returns 401 for illegal / disabled Client App (design §3.1), and
      // any other network error should also degrade to disabled rather than
      // block the main auth flow. Cache so we don't re-probe on every submit.
      const disabled = TurnstileConfig(enabled: false);
      _cached = disabled;
      return disabled;
    }
  }

  @override
  Future<String?> obtainToken() async {
    final config = await getConfig();
    if (!config.enabled) return null;
    // Delegate to the invisible-challenge helper; single-use token, never
    // cached.
    return _obtainTokenFn(siteKey: config.siteKey);
  }
}
