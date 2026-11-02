import '../../features/account/account_models.dart';
import '../../features/onboarding/connection_mode_port.dart';

/// The Host returns no entitlements in these states whatever the account owns.
/// A signed-out or local profile really has none, so it stays out of this list.
bool overlayAppearanceQualificationUnknown(
  AccountSessionState session,
  ConnectionModeSnapshot? mode,
) =>
    (mode?.isOffline ?? false) ||
    (mode?.needsOnlineRecovery ?? false) ||
    session == AccountSessionState.credentialTemporarilyUnavailable ||
    session == AccountSessionState.legacyUnavailable;
