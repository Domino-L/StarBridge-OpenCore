import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/account/account_migration_controller.dart';
import '../../features/account/account_migration_result.dart';
import '../../features/account/account_module.dart';
import '../../features/account/bridge_account_migration.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'startup_prompt_queue.dart';

/// Shows the migration result once after the relay migrated a linked account
/// (account plan item 9). It uses the settings card's controller, so both see
/// the same status, its polling and one "showing" guard; the Host keeps the
/// "shown" mark, so the card and this prompt never show the same result twice.
final class MigrationResultFlow {
  MigrationResultFlow({
    required AccountModule account,
    required BridgeClientSession session,
    required this.queue,
    required this.ready,
  }) : _account = account,
       _shared = AccountMigrationController.sharedFor(account.projection),
       _owned = AccountMigrationController.sharedFor(account.projection) == null
           ? AccountMigrationController(
               BridgeAccountMigration(session),
               account.projection,
             )
           : null {
    _migration.addListener(wake);
  }

  final AccountModule _account;
  final AccountMigrationController? _shared, _owned;
  final StartupPromptQueue queue;
  final bool Function() ready;
  AccountMigrationController get _migration => (_shared ?? _owned)!;
  final _key = Object();
  bool _showing = false, _disposed = false;

  void wake() {
    if (_disposed || _showing || !_migration.resultPending) return;
    queue.enqueue(
      _key,
      priority: 120,
      eligible: () =>
          ready() &&
          !_showing &&
          !_migration.presenting &&
          _migration.resultPending,
      show: _show,
    );
  }

  Future<void> _show() async {
    final navigator = queue.navigator;
    if (_disposed || navigator == null) return;
    _showing = true;
    final generation = _account.projection.value.generation;
    try {
      // The result may have been shown from the settings card meanwhile.
      await _migration.load();
      // Re-checked after the read: same session, still pending, and nothing
      // (such as the card's own result dialog) opened over the app meanwhile.
      if (_disposed ||
          !navigator.mounted ||
          !_account.projection.value.isSignedIn ||
          _account.projection.value.generation != generation ||
          !_migration.resultPending ||
          _migration.presenting ||
          queue.hasBlockingRoute) {
        return;
      }
      await _migration.present(
        (view) => showAccountMigrationResult(
          navigator.context,
          view,
          owner: (account: _account.projection, generation: generation),
          source: InteractionSource.programmatic,
        ),
      );
    } finally {
      _showing = false;
      // Skipped behind another dialog: queue again while still pending.
      wake();
    }
  }

  void dispose() {
    _disposed = true;
    queue.cancel(_key);
    if (!_migration.disposed) _migration.removeListener(wake);
    // The shared controller belongs to the settings feature.
    _owned?.dispose();
  }
}
