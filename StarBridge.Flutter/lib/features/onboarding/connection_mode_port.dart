import 'package:flutter/foundation.dart';

enum ConnectionModeState {
  unsupported,
  unavailable,
  online,
  local,
  offline,
  switching,
  signInRequired,
  recoveryRequired,
}

/// Display facts from the mode owner, not account or installation authority.
@immutable
final class ConnectionModeSnapshot {
  const ConnectionModeSnapshot({
    this.scope = 0,
    this.revision,
    this.state = ConnectionModeState.unsupported,
    this.canEnterOffline = false,
    this.offlineAccount,
  });
  final Object scope;
  final int? revision;
  final ConnectionModeState state;
  final bool canEnterOffline;
  final OfflineAccountDisplay? offlineAccount;
  bool get isOffline => state == ConnectionModeState.offline;
  // Compatibility recovery for an interrupted online handoff, not permission
  // to select a new offline mode or dispatch account traffic.
  bool get needsOnlineRecovery =>
      revision != null &&
      (state == ConnectionModeState.signInRequired ||
          state == ConnectionModeState.recoveryRequired);
}

/// A last-confirmed display name, not a session or permission to use remote APIs.
@immutable
final class OfflineAccountDisplay {
  const OfflineAccountDisplay(
    this.displayName,
    this.cachedAtUtc, {
    this.avatarImageData,
    this.avatarCachedAtUtc,
  });
  final String displayName;
  final DateTime cachedAtUtc;
  final String? avatarImageData;
  final DateTime? avatarCachedAtUtc;
}

abstract interface class ConnectionModePort {
  bool get supported;
  Stream<void> get invalidations;
  Future<ConnectionModeSnapshot> read();
  Future<ConnectionModeSnapshot> enterOffline(int revision);
}

/// Both the primary Bridge owner and the tray's borrowed projection use this
/// interface. Neither can turn an offline choice into a remote presence write.
abstract interface class ConnectionModeControl implements Listenable {
  ConnectionModeSnapshot get snapshot;
  bool get busy;
  bool get failed;
  bool get allowsOnlineTraffic;
  bool get canEnterOffline;
  Future<bool> enterOffline();
}

/// Only keeps materialized display during an account-event mode recheck.
/// It grants no traffic permission and cannot be used for an offline write.
@immutable
final class OnlineModeDisplayContinuity {
  const OnlineModeDisplayContinuity({
    required this.sourceGeneration,
    required this.generation,
    required this.revision,
  });
  final int sourceGeneration, generation, revision;
}

abstract interface class ConnectionModeDisplayContinuitySource {
  OnlineModeDisplayContinuity? get displayContinuity;
}
