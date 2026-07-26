import 'package:app/config/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults target the production App client', () {
    expect(Settings.heraldBaseUrl, 'https://auth.fornetcode.com');
    expect(Settings.heraldRealmId, 'admin');
    expect(Settings.heraldClientId, 'fornetcode-app');
    expect(Settings.heraldClientAppUuid, isEmpty);
  });
}
