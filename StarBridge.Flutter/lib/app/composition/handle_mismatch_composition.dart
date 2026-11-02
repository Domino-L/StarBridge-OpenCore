import '../../features/account/account_module.dart';
import '../../features/account/handle_mismatch_port.dart';
import '../../features/game_log/game_log_controller.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'handle_mismatch_module.dart';

/// The handle mismatch check: re-runs on account/bootstrap invalidation and
/// refreshes the account and game log when asked. Inert without a host.
HandleMismatchModule composeHandleMismatch(
  AccountModule account,
  GameLogController? gameLog,
  BridgeClientSession? session,
) => HandleMismatchModule(
  account: account.projection,
  gameLog: gameLog,
  port: session == null ? null : BridgeHandleMismatchPort(session),
  activeGeneration: session == null ? null : () => session.activeGeneration,
  invalidations: session?.events
      .where(
        (event) =>
            event.name == 'account.changed' ||
            event.name == 'bootstrap.invalidated',
      )
      .map((_) {}),
  refresh: () async {
    await account.refresh();
    await gameLog?.run();
  },
);
