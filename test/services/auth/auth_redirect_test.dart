import 'package:app/services/auth/auth_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts internal destinations with query parameters', () {
    expect(safeAuthDestination('/device?tab=active'), '/device?tab=active');
  });

  test('rejects external and protocol-relative destinations', () {
    expect(safeAuthDestination('https://example.com'), '/index');
    expect(safeAuthDestination('//example.com'), '/index');
  });
}
