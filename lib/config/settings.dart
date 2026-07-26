class Settings {
  // Herald runtime configuration (design §1.4 / §4.1).
  // realmId / clientId / baseUrl are registered and configured ahead of time
  // by ops inside the Herald realm; the App reads them from here. Real values
  // are injected by ops config — replace the placeholders before release.
  // TODO(ops): inject real Herald realm/client/baseUrl via build-time config.
  static const String heraldBaseUrl = 'https://herald.example.com';
  static const String heraldRealmId = '';
  static const String heraldClientId = '';

  // Token persistence keys (shared_preferences). Consumed by TokenStore and
  // the startup bootstrap.
  static const String accessTokenKey = 'herald.accessToken';
  static const String refreshTokenKey = 'herald.refreshToken';
}
