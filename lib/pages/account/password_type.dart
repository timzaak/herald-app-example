// ignore_for_file: constant_identifier_names
// 常量名沿用 PascalCase 是有意为之：password_page.dart:26 注释约定本文件
// 保持不动（ChangePasswordType 的契约），改名会牵动多处引用，故豁免该 lint。
enum ChangePasswordType {
  ForgotPassword,
  ResetPassword, // Changed from ChangePassword
}
