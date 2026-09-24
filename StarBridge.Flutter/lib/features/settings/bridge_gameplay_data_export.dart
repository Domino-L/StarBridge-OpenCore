import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'gameplay_data_export_port.dart';

/// A short-lived adapter bound to the account that opened the settings detail.
final class BridgeGameplayDataExport implements GameplayDataExportPort {
  BridgeGameplayDataExport(this._session, this._account);
  final BridgeClientSession _session;
  final BridgeAccountContext _account;
  BridgeRequestOperation? _operation;

  @override
  Future<GameplayExportOutcome> export(String locale) async {
    if (_operation != null) return GameplayExportOutcome.busy;
    try {
      final operation = _session.beginRequest(
        'gameplayTime.export',
        accountContext: _account,
        payload: {'schemaVersion': 1, 'locale': locale},
        timeout: const Duration(minutes: 5),
      );
      _operation = operation;
      final response = await operation.future;
      if (response.payload.length != 2 ||
          response.accountContext?.environment != _account.environment ||
          response.accountContext?.authority != _account.authority ||
          response.accountContext?.subject != _account.subject ||
          response.payload['schemaVersion'] != 1) {
        return GameplayExportOutcome.unknown;
      }
      return switch (response.payload['outcome']) {
        'saved' => GameplayExportOutcome.saved,
        'cancelled' => GameplayExportOutcome.cancelled,
        _ => GameplayExportOutcome.unknown,
      };
    } on BridgeStaleGenerationException {
      return GameplayExportOutcome.accountChanged;
    } on BridgeClientException catch (error) {
      return switch (error.code) {
        'gameplayExport.account_changed' =>
          GameplayExportOutcome.accountChanged,
        'gameplayExport.data_unavailable' =>
          GameplayExportOutcome.dataUnavailable,
        'gameplayExport.file_exists' => GameplayExportOutcome.fileExists,
        'gameplayExport.invalid_destination' =>
          GameplayExportOutcome.invalidDestination,
        'gameplayExport.busy' => GameplayExportOutcome.busy,
        'gameplayExport.save_failed' => GameplayExportOutcome.failed,
        'host.capability_missing' => GameplayExportOutcome.unavailable,
        _ => GameplayExportOutcome.unknown,
      };
    } on Object {
      // A lost response may follow a successful disk commit. Do not claim failure or auto-retry.
      return GameplayExportOutcome.unknown;
    } finally {
      _operation = null;
    }
  }

  @override
  void cancel() {
    final operation = _operation;
    if (operation != null) unawaited(operation.cancel());
  }
}
