// Unit tests for PlatformNativeSignInService.
//
// WHY these tests exist: the service is the boundary between the Notifier and
// the platform plugins. Its contract is: return the one-time handshake
// credential on success, or null when the user cancels / the platform is
// unsupported / no account is signed in. These tests pin the unsupported-
// platform behavior (the test host is not iOS/Android, so both methods must
// return null) — this is the exact behavior that keeps native buttons inert on
// desktop/web and prevents a plugin crash from breaking the login page.
import 'package:app/services/auth/native_sign_in_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformNativeSignInService on non-iOS/non-Android test host', () {
    test('requestAppleIdentityToken returns null on non-iOS', () async {
      // The unit-test host is a desktop OS (not iOS), so the Apple branch is
      // guarded off — null means the Notifier returns cancelled without
      // touching the platform plugin.
      final service = const PlatformNativeSignInService();
      expect(await service.requestAppleIdentityToken(), isNull);
    });

    test('requestGoogleIdToken returns null on non-Android', () async {
      final service = const PlatformNativeSignInService();
      expect(await service.requestGoogleIdToken(), isNull);
    });
  });
}
