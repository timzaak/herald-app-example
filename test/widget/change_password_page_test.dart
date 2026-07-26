import 'package:app/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_herald_app.dart';

void main() {
  testWidgets('authenticated user changes password through reauth service', (
    tester,
  ) async {
    final harness = await pumpHeraldApp(tester);
    harness.container.read(authStateProvider.notifier).seedAuthenticated(true);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('changePasswordTile')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('changePasswordCurrentField')),
      'OldPassword1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('changePasswordNewField')),
      'NewPassword1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('changePasswordConfirmField')),
      'NewPassword1',
    );
    await tester.tap(find.byKey(const ValueKey('changePasswordSubmitButton')));
    await tester.pumpAndSettle();

    expect(harness.security.calls, hasLength(1));
    expect(harness.security.calls.single.currentPassword, 'OldPassword1');
    expect(harness.security.calls.single.newPassword, 'NewPassword1');
    expect(find.byKey(const ValueKey('changePasswordTile')), findsOneWidget);
    await drainSmartDialogToasts(tester);
  });
}
