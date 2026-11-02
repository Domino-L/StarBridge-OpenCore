import '../account/account_models.dart';
import '../onboarding/connection_mode_port.dart';

// A display-cache key, never a Bridge account context or authorization source.
Object achievementReadScope(
  AccountProjection account,
  ConnectionModeControl? mode,
) => (
  achievementReadBaseScope(account, mode),
  account.hasDisplayHandoff ? account.displayHandoff : null,
);

Object achievementReadBaseScope(
  AccountProjection account,
  ConnectionModeControl? mode, {
  Object? modeScope,
}) {
  final snapshot = mode?.snapshot;
  return (
    account.generation,
    account.sessionState,
    account.retainedReadId,
    modeScope ?? snapshot?.scope,
    snapshot?.revision,
    snapshot?.state,
    mode?.failed,
    snapshot?.offlineAccount?.displayName,
    snapshot?.offlineAccount?.cachedAtUtc,
  );
}

Object achievementModeScope(
  ConnectionModeControl? mode, {
  Object? scope,
  ConnectionModeSnapshot? snapshot,
}) => (
  scope ?? snapshot?.scope ?? mode?.snapshot.scope,
  snapshot?.revision ?? mode?.snapshot.revision,
  snapshot?.state ?? mode?.snapshot.state,
  mode?.failed,
  (snapshot ?? mode?.snapshot)?.offlineAccount?.displayName,
  (snapshot ?? mode?.snapshot)?.offlineAccount?.cachedAtUtc,
);
