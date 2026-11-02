import '../account/game_identity_verification.dart';

enum OnlineReviewModeState {
  unavailable,
  switching,
  online,
  local,
  offline,
  signInRequired,
  recoveryRequired,
}

enum OnlineReviewState {
  unavailable,
  notStarted,
  signInRequired,
  authorizing,
  needsLocalIdentity,
  identityCheckRequired,
  reviewRequired,
  confirmedForHandoff,
  accountReviewRequired,
  accountConfirmedForHandoff,
  installedReviewRequired,
  boundOnlineIdentity,
  reviewExpired,
  contextChanged,
  mismatch,
  verificationRequired,
  verificationPending,
  reverifyRequired,
  revoked,
  operationInProgress,
  sessionExpired,
  reauthorizationRequired,
  recoveryRequired,
}

enum OnlineReviewAction {
  begin,
  login,
  resume,
  reauthorize,
  review,
  confirm,
  cancel,
}

// Observations of the original Host owner, never account authority or a guide
// completion receipt. The staged account is not the installed app account.
final class OnlineReviewSnapshot {
  const OnlineReviewSnapshot({
    this.revision,
    this.modeState = OnlineReviewModeState.unavailable,
    this.state = OnlineReviewState.unavailable,
    this.localHandle,
    this.authoritativeHandle,
    this.accountDisplayName,
    this.confirmationKey,
    this.retainsSession = false,
    this.reauthorizationSupported = false,
  });
  final int? revision;
  final OnlineReviewModeState modeState;
  final OnlineReviewState state;
  final bool retainsSession;
  final bool reauthorizationSupported;
  final String? localHandle,
      authoritativeHandle,
      accountDisplayName,
      confirmationKey;
  bool get canBegin =>
      revision != null &&
      (modeState == OnlineReviewModeState.local ||
          modeState == OnlineReviewModeState.offline && retainsSession);
  bool get pending =>
      revision != null && modeState == OnlineReviewModeState.signInRequired;
  bool get canLogin =>
      pending &&
      !retainsSession &&
      const {
        OnlineReviewState.signInRequired,
        OnlineReviewState.reauthorizationRequired,
        OnlineReviewState.sessionExpired,
        OnlineReviewState.mismatch,
      }.contains(state);
  bool get canResume =>
      pending &&
      retainsSession &&
      const {
        OnlineReviewState.signInRequired,
        OnlineReviewState.unavailable,
      }.contains(state);
  bool get canReauthorize =>
      pending &&
      retainsSession &&
      reauthorizationSupported &&
      (state == OnlineReviewState.reauthorizationRequired ||
          state == OnlineReviewState.sessionExpired);
  bool get canReview =>
      (pending ||
          revision != null && modeState == OnlineReviewModeState.online) &&
      state != OnlineReviewState.authorizing &&
      (state != OnlineReviewState.operationInProgress ||
          modeState == OnlineReviewModeState.online) &&
      state != OnlineReviewState.recoveryRequired;
  bool get canConfirm =>
      (pending &&
              (state == OnlineReviewState.reviewRequired ||
                  retainsSession &&
                      state == OnlineReviewState.accountReviewRequired) ||
          modeState == OnlineReviewModeState.online &&
              state == OnlineReviewState.installedReviewRequired) &&
      confirmationKey != null;
  bool get canCancel =>
      pending ||
      revision != null &&
          modeState == OnlineReviewModeState.recoveryRequired &&
          state == OnlineReviewState.recoveryRequired;
  bool get identityConfirmed =>
      pending && state == OnlineReviewState.confirmedForHandoff ||
      modeState == OnlineReviewModeState.online &&
          state == OnlineReviewState.boundOnlineIdentity;
}

/// A review port that can also verify the game identity of its staged account.
abstract interface class OnlineReviewGameIdentitySource {
  GameIdentityVerificationPort get gameIdentity;
}

abstract interface class OnlineReviewPort {
  Stream<void> get invalidations;
  Future<OnlineReviewSnapshot> read();
  Future<OnlineReviewSnapshot> execute(
    OnlineReviewAction action,
    int revision, {
    String? confirmationKey,
  });
}
