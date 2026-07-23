// Hand-rolled fake of [TurnstileService] for widget tests (FL-T01).
//
// Default behavior matches the disabled path (`enabled: false`, `obtainToken`
// returns null) so most widget tests skip Turnstile entirely without any
// setup. Tests asserting the fresh-token-on-consent-replay path opt in by
// setting [returnToken] to a canned value; they can then assert
// [obtainTokenCalls] length to verify the consent page took a FRESH token on
// replay (single-use semantics — design §1.4).
import 'package:app/services/auth/turnstile_service.dart';

class FakeTurnstileService implements TurnstileService {
  FakeTurnstileService({this.config = const TurnstileConfig()});

  /// Config returned by [getConfig]. Defaults to disabled.
  TurnstileConfig config;

  /// Token returned by [obtainToken]. When null (default), obtainToken skips
  /// the challenge (matches disabled behavior); tests opt in to the
  /// challenged path by setting this to a non-null canned value.
  String? returnToken;

  /// Number of times [obtainToken] has been called. Tests asserting the
  /// fresh-token-on-consent-replay path assert this == 2 (original submit +
  /// fresh token before consent accept).
  int obtainTokenCalls = 0;

  /// Number of times [getConfig] has been called.
  int getConfigCalls = 0;

  @override
  Future<TurnstileConfig> getConfig() async {
    getConfigCalls++;
    return config;
  }

  @override
  Future<String?> obtainToken() async {
    obtainTokenCalls++;
    return returnToken;
  }
}
