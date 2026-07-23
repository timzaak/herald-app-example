String? validateEmail(String? text) {
  if (text == null ||
      !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(text)) {
    return '邮箱地址格式不正确';
  }
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return '请输入密码';
  }
  if (value.length < 8 || value.length > 24) {
    return '密码长度需在8~24位之间';
  }
  if (!RegExp(r'(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(value)) {
    return '密码需同时包含大小写字母和数字';
  }
  return null;
}

String? validateVerificationCode(String? value) {
  if (value == null || value.isEmpty) {
    return '请输入验证码';
  }
  if (value.length != 6 || !RegExp(r'^\d{6}$').hasMatch(value)) {
    return '验证码必须为6位纯数字';
  }
  return null;
}
