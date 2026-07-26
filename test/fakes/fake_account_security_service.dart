import 'package:app/services/auth/account_security_service.dart';

class ChangePasswordCall {
  const ChangePasswordCall(this.currentPassword, this.newPassword);

  final String currentPassword;
  final String newPassword;
}

class FakeAccountSecurityService implements AccountSecurityService {
  final List<ChangePasswordCall> calls = [];
  AccountSecurityException? error;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    calls.add(ChangePasswordCall(currentPassword, newPassword));
    final failure = error;
    if (failure != null) throw failure;
  }
}
