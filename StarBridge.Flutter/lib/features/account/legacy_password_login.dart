final class LegacyPasswordLoginResult {
  const LegacyPasswordLoginResult(this.outcome, {this.retryAfterSeconds = 0});
  final String outcome;
  final int retryAfterSeconds;
}

abstract interface class LegacyPasswordLoginPort {
  bool get supportsLegacyPasswordLogin;
  Future<LegacyPasswordLoginResult> loginLegacy(String email, String password);
  Future<void> cancelLegacyPasswordLogin();
}
