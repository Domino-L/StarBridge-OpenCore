import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';

final class LocalEventExportResult {
  const LocalEventExportResult(
    this.code, {
    this.count = 0,
    this.recovered = false,
  });
  final String code;
  final int count;
  final bool recovered;
}

abstract interface class LocalEventExportPort {
  Future<LocalEventExportResult> export(String locale);
  void cancel();
}

/// Device scope: the Host owns the source, save picker, and destination.
final class BridgeLocalEventExport implements LocalEventExportPort {
  BridgeLocalEventExport(this.session);
  final BridgeClientSession session;
  BridgeRequestOperation? _operation;

  @override
  Future<LocalEventExportResult> export(String locale) async {
    if (_operation != null) return const LocalEventExportResult('busy');
    try {
      final operation = session.beginRequest(
        'diagnostics.exportLocalEvents',
        payload: {'schemaVersion': 1, 'locale': locale},
        timeout: const Duration(minutes: 5),
      );
      _operation = operation;
      final p = (await operation.future).payload;
      if (p.length != 4 ||
          p['schemaVersion'] != 1 ||
          p['count'] is! int ||
          p['recovered'] is! bool) {
        return const LocalEventExportResult('unknown');
      }
      final count = p['count']! as int;
      final recovered = p['recovered']! as bool;
      if (p['outcome'] == 'saved' && count > 0 && count <= 3000) {
        return LocalEventExportResult(
          'saved',
          count: count,
          recovered: recovered,
        );
      }
      if (p['outcome'] == 'cancelled' && count == 0 && !recovered) {
        return const LocalEventExportResult('cancelled');
      }
      return const LocalEventExportResult('unknown');
    } on BridgeClientException catch (error) {
      final code = switch (error.code) {
        'localEventsExport.file_exists' => 'fileExists',
        'localEventsExport.invalid_destination' => 'invalidDestination',
        'localEventsExport.data_unavailable' => 'dataUnavailable',
        'localEventsExport.empty' => 'empty',
        'localEventsExport.busy' => 'busy',
        'localEventsExport.unavailable' ||
        'host.capability_missing' => 'unavailable',
        'localEventsExport.save_failed' => 'failed',
        _ => 'unknown',
      };
      return LocalEventExportResult(code);
    } on Object {
      // A dropped response can follow a committed file; do not auto-retry.
      return const LocalEventExportResult('unknown');
    } finally {
      _operation = null;
    }
  }

  @override
  void cancel() {
    final operation = _operation;
    if (operation != null) {
      unawaited(operation.cancel().catchError((Object _) {}));
    }
  }
}
