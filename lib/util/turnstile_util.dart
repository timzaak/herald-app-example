import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode

/// Retrieves the Cloudflare Turnstile token using invisible mode.
///
/// Returns the token [String] on success, or `null` if Turnstile is disabled
/// ([siteKey] is null), the challenge fails, or an error occurs.
///
/// [siteKey] is injected by [TurnstileService] per Client App (design §5.4). A
/// null [siteKey] means Turnstile is disabled for this realm+client — return
/// null without launching a challenge. There is no hardcoded fallback site key.
Future<String?> getTurnstileToken({String? siteKey}) async {
  if (siteKey == null || siteKey.isEmpty) {
    return null;
  }

  final turnstile = CloudflareTurnstile.invisible(siteKey: siteKey);

  try {
    final String? token = await turnstile.getToken();
    if (token != null && kDebugMode) {
      debugPrint('Turnstile token: $token');
    }
    return token;
  } on TurnstileException catch (e) {
    if (kDebugMode) {
      debugPrint('Turnstile challenge failed: ${e.message}');
    }
    return null;
  } finally {
    turnstile.dispose();
  }
}
