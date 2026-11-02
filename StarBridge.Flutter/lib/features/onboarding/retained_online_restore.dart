import 'online_installation_port.dart';
import 'online_review_port.dart';

/// The explicit Online click may resume the retained original account without
/// another guide. Native still verifies identity, issues/consumes its handoff
/// key, and installs the original online owner. Never signs into another account.
Future<int?> restoreRetainedOnline({
  required OnlineReviewPort review,
  required OnlineInstallationPort installation,
  required String? originalHandle,
  required bool Function() current,
}) async {
  if (!current() || !installation.supported) return null;
  var snapshot = await review.read();
  // Only this explicit Online click may acknowledge a cold interrupted retained
  // handoff. Native's v2 cancel performs exit/receipt checks and does not touch
  // the unknown credential. A live sealed candidate is operationInProgress;
  // leave that candidate to the existing review UI, never cancel it implicitly.
  if (current() &&
      snapshot.retainsSession &&
      snapshot.canCancel &&
      snapshot.state == OnlineReviewState.recoveryRequired &&
      snapshot.localHandle == null &&
      snapshot.authoritativeHandle == null) {
    final pendingRevision = snapshot.revision!;
    snapshot = await review.execute(OnlineReviewAction.cancel, pendingRevision);
    if (!current() ||
        snapshot.revision == null ||
        snapshot.revision! <= pendingRevision ||
        snapshot.modeState != OnlineReviewModeState.offline) {
      return null;
    }
  }
  if (!current() ||
      !snapshot.retainsSession ||
      !snapshot.canBegin ||
      snapshot.modeState != OnlineReviewModeState.offline) {
    return null;
  }
  snapshot = await review.execute(OnlineReviewAction.begin, snapshot.revision!);
  if (!current() || !snapshot.canResume) return null;
  snapshot = await review.execute(
    OnlineReviewAction.resume,
    snapshot.revision!,
  );
  if (!current() || !snapshot.retainsSession) return null;
  if (snapshot.state == OnlineReviewState.identityCheckRequired ||
      snapshot.state == OnlineReviewState.needsLocalIdentity) {
    if (!snapshot.canReview) return null;
    snapshot = await review.execute(
      OnlineReviewAction.review,
      snapshot.revision!,
    );
  }
  // A cold offline root intentionally has no online account projection. Its
  // absent UI Handle is not a sign-out receipt. Native resume pins the retained
  // subject and verifies it before issuing this one-use identity review key.
  // Account-only restoration uses that pinned subject, not a local game Handle.
  // An identity-bearing review still requires matching Handles; neither UI path
  // can manufacture game identity authority from the account restoration receipt.
  final expected = originalHandle?.trim().toLowerCase();
  final local = snapshot.localHandle?.trim().toLowerCase();
  final authoritative = snapshot.authoritativeHandle?.trim().toLowerCase();
  final accountOnly = snapshot.state == OnlineReviewState.accountReviewRequired;
  if (!current() ||
      !snapshot.retainsSession ||
      !snapshot.canConfirm ||
      (!accountOnly &&
          (local == null ||
              local.isEmpty ||
              local != authoritative ||
              (expected != null &&
                  expected.isNotEmpty &&
                  authoritative != expected)))) {
    return null;
  }
  snapshot = await review.execute(
    OnlineReviewAction.confirm,
    snapshot.revision!,
    confirmationKey: snapshot.confirmationKey,
  );
  if (!current() ||
      !snapshot.retainsSession ||
      !(snapshot.identityConfirmed ||
          snapshot.state == OnlineReviewState.accountConfirmedForHandoff) ||
      !installation.supported) {
    return null;
  }
  // The caller owns observation of this exact revision. An uncertain install
  // must be read, never replayed. Native remains the only admission authority.
  return snapshot.revision;
}
