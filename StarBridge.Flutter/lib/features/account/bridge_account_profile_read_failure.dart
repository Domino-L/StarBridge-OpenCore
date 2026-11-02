import '../../platform/bridge/bridge_client_session.dart';
import 'account_models.dart';

final class AccountProfileSnapshotFailure implements Exception {
  const AccountProfileSnapshotFailure(this.snapshot, this.cause);
  final AccountHostSnapshot snapshot;
  final Object cause;
}

final class AccountProfileReadSnapshot {
  AccountProfileReadSnapshot(
    this.route,
    this.generation,
    AccountProfile value,
    this.observedAtUtc,
  ) : profile = AccountProfile(
        displayName: value.displayName,
        avatarUrl: value.avatarUrl,
        avatarImageData: value.avatarImageData,
        maskedAccount: value.maskedAccount,
        locale: value.locale,
        timeZone: value.timeZone,
      );
  final AccountRoute route;
  final int generation;
  final AccountProfile profile;
  final DateTime observedAtUtc;

  static AccountProfileReadSnapshot? capture(
    AccountHostSnapshot snapshot,
    DateTime? observedAtUtc,
  ) {
    final profile = snapshot.profile, route = snapshot.route;
    return snapshot.sessionState != AccountSessionState.signedIn ||
            profile == null ||
            route == null ||
            observedAtUtc == null
        ? null
        : AccountProfileReadSnapshot(
            route,
            snapshot.generation,
            profile,
            observedAtUtc,
          );
  }
}

/// A fresh account read does not make an earlier profile or edit grant fresh.
/// Retention here is one same-owner display snapshot, never an account cache.
AccountHostSnapshot accountProfileReadFailureSnapshot({
  required Object error,
  required int generation,
  required AccountRoute route,
  required AccountProfileReadSnapshot? previous,
}) {
  final lost =
      error is BridgeClientException &&
      const {
        'account.reauthorization_required',
        'bridge.account_context_required',
      }.contains(error.code);
  final transient =
      error is BridgeTimeoutException ||
      error is BridgeDisconnectedException ||
      error is BridgeClientException &&
          error.code == 'profile.read_transient' &&
          error.retryable;
  final at = previous?.observedAtUtc;
  final old = previous?.profile;
  final retain =
      !lost &&
      transient &&
      previous != null &&
      old != null &&
      at != null &&
      previous.generation == generation &&
      previous.route.environment == route.environment &&
      previous.route.authority == route.authority &&
      previous.route.subject == route.subject;
  return AccountHostSnapshot(
    generation: generation,
    sessionState: lost
        ? AccountSessionState.reauthorizationRequired
        : AccountSessionState.signedIn,
    route: lost ? null : route,
    profile: retain
        ? AccountProfile(
            displayName: old.displayName,
            avatarUrl: old.avatarUrl,
            avatarImageData: old.avatarImageData,
            maskedAccount: old.maskedAccount,
            locale: old.locale,
            timeZone: old.timeZone,
          )
        : null,
    profileFreshness: retain
        ? AccountProfileFreshness.cached
        : AccountProfileFreshness.unavailable,
    cachedAt: retain ? at : null,
    identity: const AccountIdentityProjection.unavailable(),
    compatibility: const AccountCompatibilityProjection.unavailable(),
    localeOptions: const [],
    timeZoneOptions: const [],
  );
}
