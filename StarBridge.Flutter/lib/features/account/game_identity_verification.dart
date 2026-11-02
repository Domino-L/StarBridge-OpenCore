/// How one verification step ended. [outcomeUnknown] is neither success nor
/// failure: the write may have reached SCM, so the panel must not imply either.
enum GameIdentityOutcome {
  issued,
  verified,
  rejected,
  alreadyVerified,
  reauthorizationRequired,
  unavailable,
  outcomeUnknown,
}

final class GameIdentityResult {
  const GameIdentityResult(
    this.outcome, {
    this.verificationCode,
    this.expiresInSeconds = 0,
    this.message,
  });
  final GameIdentityOutcome outcome;
  final String? verificationCode;
  final int expiresInSeconds;

  /// SCM's own explanation of a rejection, shown as received.
  final String? message;
}

/// The SCM verification flow behind the shared panel. The Host owns the session;
/// the panel never sees a token. The code is one-time and is meant to be pasted
/// onto a public RSI profile, so a copy left on the clipboard reveals nothing.
abstract interface class GameIdentityVerificationPort {
  bool get supportsGameIdentityVerification;

  /// Support arrives after sign-in, once the Host has confirmed the session.
  Stream<void> get supportChanges;

  /// Binds the next requests to one owner. Requests stop working once that
  /// account or session generation is gone, even if the same account returns.
  void beginFlow();
  Future<GameIdentityResult> requestVerificationCode(String handle);
  Future<GameIdentityResult> submitVerification(String handle, String contact);
  Future<bool> openRsiProfile();
}

/// Same rule as the Host's IdentityBindingPolicy.IsValidGameName, plus SCM's
/// three-character minimum, so a mistyped Handle never reaches SCM.
bool isValidGameIdentityHandle(String value) {
  final handle = value.trim();
  return handle.length >= 3 &&
      handle.length <= 64 &&
      RegExp(r'^[\p{L}\p{N}_.\-]+$', unicode: true).hasMatch(handle);
}

bool isValidGameIdentityContact(String value) {
  final contact = value.trim();
  return contact.length >= 7 && contact.length <= 256;
}
