class Settings {
  // Inject with:
  // --dart-define=HERALD_BASE_URL=https://...
  // --dart-define=HERALD_REALM_ID=...
  // --dart-define=HERALD_CLIENT_ID=...
  static const String heraldBaseUrl = String.fromEnvironment(
    'HERALD_BASE_URL',
    defaultValue: 'https://auth.fornetcode.com',
  );
  static const String heraldRealmId = String.fromEnvironment(
    'HERALD_REALM_ID',
    defaultValue: 'admin',
  );
  static const String heraldClientId = String.fromEnvironment(
    'HERALD_CLIENT_ID',
    defaultValue: 'fornetcode-app',
  );
  static const String heraldClientAppUuid = String.fromEnvironment(
    'HERALD_CLIENT_APP_UUID',
  );

  // Token persistence keys (shared_preferences). Consumed by TokenStore and
  // the startup bootstrap.
  static const String accessTokenKey = 'herald.accessToken';
  static const String refreshTokenKey = 'herald.refreshToken';
}
