final class PasswordRecoveryResult {
  const PasswordRecoveryResult(this.outcome, {this.retryAfterSeconds = 0});
  final String outcome;
  final int retryAfterSeconds;
}

abstract interface class PasswordRecoveryPort {
  bool get supportsPasswordRecovery;
  Future<PasswordRecoveryResult> sendPasswordResetCode(String email);
  Future<PasswordRecoveryResult> confirmPasswordReset(
    String email,
    String code,
    String password,
  );
  Future<void> cancelPasswordRecovery();
}
