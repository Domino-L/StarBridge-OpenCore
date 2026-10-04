import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import 'local_hangar_port.dart';

enum HangarReadStage {
  pageRead,
  bind,
  inventory,
  inventoryProjection,
  legacyRead,
  legacyProjection,
}

/// Temporary SB-HANGAR-DIAG-0704-01 instrumentation. No IO, payloads or identities.
/// Only the explicitly compiled diagnostic build displays this bounded buffer.
abstract final class HangarReadDiagnostics {
  static const enabled = bool.fromEnvironment('SB_HANGAR_DIAGNOSTICS');
  static final _entries = <String>[];
  static List<String> get entries => List.unmodifiable(_entries);
  static void clear() => _entries.clear();

  static const _codes = {
    'hangar.account_changed',
    'hangar.invalid_inventory',
    'hangar.revision_conflict',
    'hangar.inventory_changed',
    'hangar.legacy_unavailable',
    'hangar.unavailable',
    'hangar.busy',
    'hangar.identity_unavailable',
    'bridge.timeout',
    'bridge.disconnected',
    'bridge.account_context_required',
    'account.not_signed_in',
    'account.session_expired',
  };

  static String formatFailure(
    HangarReadStage stage,
    Object error,
    DateTime time,
  ) {
    final raw = switch (error) {
      LocalHangarFailure e => e.code,
      BridgeClientException e => e.code,
      _ => '',
    };
    final code = _codes.contains(raw) ? raw : 'unclassified';
    final kind = switch (error) {
      LocalHangarFailure() => 'localHangar',
      BridgeRemoteException() => 'remoteBridge',
      BridgeClientException() => 'clientBridge',
      TimeoutException() => 'timeout',
      FormatException() => 'format',
      TypeError() => 'type',
      _ => 'other',
    };
    // Never serialize the error, stack, runtimeType, response, path or account.
    return 'SB-HANGAR-DIAG-0704-01 ${time.toUtc().toIso8601String()} '
        '${stage.name} $kind $code';
  }

  static Future<T> capture<T>(
    HangarReadStage stage,
    Future<T> Function() action, {
    bool enabled = HangarReadDiagnostics.enabled,
  }) async {
    if (!enabled) return action();
    try {
      return await action();
    } catch (error) {
      if (_entries.length == 8) _entries.removeAt(0);
      _entries.add(formatFailure(stage, error, DateTime.now()));
      rethrow;
    }
  }
}
