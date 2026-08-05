import 'package:dio/dio.dart';

/// A single OAuth provider entry from public-config (design §4.2.2).
class OAuthProviderView {
  final String name;
  final String displayName;
  final bool enabled;
  final String? clientId;
  const OAuthProviderView({
    required this.name,
    required this.displayName,
    required this.enabled,
    this.clientId,
  });
}

class PublicAuthConfig {
  const PublicAuthConfig({
    required this.registrationEnabled,
    required this.requireEmailVerification,
    this.oauthProviders = const <OAuthProviderView>[],
  });

  final bool registrationEnabled;
  final bool requireEmailVerification;

  /// Enabled native-login providers from public-config (apple / google). Empty
  /// when the field is absent or unreadable — the login page hides native
  /// buttons in that case (fail closed, DEC-native-login-006).
  final List<OAuthProviderView> oauthProviders;

  /// Convenience: the set of enabled native provider names with a non-empty
  /// `clientId` (apple / google subset). Drives native-button visibility.
  Set<String> get enabledNativeProviderNames => oauthProviders
      .where((p) => p.enabled && p.clientId != null && p.clientId!.isNotEmpty)
      .map((p) => p.name)
      .toSet();
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
      oauthProviders: _parseOAuthProviders(response.data?['oauthProviders']),
    );
  }

  /// Parses the `oauthProviders` array into [OAuthProviderView]s. Tolerates a
  /// missing array (older backends) by returning an empty list — native
  /// buttons are hidden, never exposed on a malformed/unavailable config.
  static List<OAuthProviderView> _parseOAuthProviders(Object? raw) {
    if (raw is! List) return const <OAuthProviderView>[];
    return raw
        .whereType<Map>()
        .map(_toProviderView)
        .whereType<OAuthProviderView>()
        .toList(growable: false);
  }

  static OAuthProviderView? _toProviderView(Map raw) {
    final name = raw['name'];
    final displayName = raw['displayName'];
    final enabled = raw['enabled'];
    if (name is! String || name.isEmpty) return null;
    if (displayName is! String || displayName.isEmpty) return null;
    if (enabled is! bool) return null;
    final clientId = raw['clientId'];
    return OAuthProviderView(
      name: name,
      displayName: displayName,
      enabled: enabled,
      clientId: clientId is String && clientId.isNotEmpty ? clientId : null,
    );
  }
}
