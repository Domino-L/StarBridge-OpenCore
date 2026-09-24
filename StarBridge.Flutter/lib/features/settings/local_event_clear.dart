import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';

abstract interface class LocalEventClearPort {
  Future<String> clear();
  void cancel();
}

final class BridgeLocalEventClear implements LocalEventClearPort {
  BridgeLocalEventClear(this.session);
  final BridgeClientSession session;
  BridgeRequestOperation? _operation;
  @override
  Future<String> clear() async {
    if (_operation != null) return 'busy';
    try {
      final operation = session.beginRequest(
        'diagnostics.clearLocalEvents',
        payload: {'schemaVersion': 1, 'confirmed': true},
      );
      _operation = operation;
      final p = (await operation.future).payload;
      return p.length == 2 &&
              p['schemaVersion'] == 1 &&
              p['outcome'] == 'cleared'
          ? 'cleared'
          : 'unknown';
    } on BridgeClientException catch (error) {
      return switch (error.code) {
        'localEventsClear.unavailable' ||
        'host.capability_missing' => 'unavailable',
        'localEventsClear.failed' => 'failed',
        'localEventsClear.busy' => 'busy',
        _ => 'unknown',
      };
    } on Object {
      return 'unknown';
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
