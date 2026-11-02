import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'manual_presence.dart';
import '../../features/onboarding/connection_mode_port.dart';

/// Composition supplies only confirmed account identity and current connection
/// facts. This contains no credentials and never derives identity from a label.
class PresenceAccountScope {
  const PresenceAccountScope({
    required this.generation,
    required this.account,
    required this.available,
    this.automaticKey = 'presence.unknown',
  });
  final int generation;
  final BridgeAccountContext? account;
  final bool available;
  final String automaticKey;
  Object get identity =>
      (generation, account?.environment, account?.authority, account?.subject);
}

/// One account-scoped Bridge source for both menus, with bounded read recovery,
/// storage, invented online default or separate tray account session.
class BridgeManualPresence extends ValueNotifier<ManualPresenceSnapshot> {
  BridgeManualPresence(this._session, this._account, {this.connectionMode})
    : super(ManualPresenceSnapshot(scope: _account.value.identity)) {
    controller = ManualPresenceController(
      source: this,
      write: _write,
      connectionMode: connectionMode,
    );
    _account.addListener(_accountChanged);
    _accountChanged();
  }
  final BridgeClientSession _session;
  final ValueListenable<PresenceAccountScope> _account;
  final ConnectionModeControl? connectionMode;
  late final ManualPresenceController controller;
  BridgeRequestOperation? _pending;
  String? _revision;
  Object? _observed;
  bool? _available;
  bool _disposed = false;
  int _epoch = 0;
  int _realtimeEpoch = 0;
  bool _refreshQueued = false;
  Timer? _retry;
  int _retryAttempt = 0;

  void _resetRecovery() {
    _retry?.cancel();
    _retry = null;
    _retryAttempt = 0;
  }

  void _accountChanged() {
    final next = _account.value;
    if (_observed == next.identity && _available == next.available) {
      value = ManualPresenceSnapshot(
        scope: next.identity,
        confirmedMode: value.confirmedMode,
        canChange: value.canChange,
        automaticKey: next.automaticKey,
        hasRealtimeAuthority: value.hasRealtimeAuthority,
        realtimeStatus: value.realtimeStatus,
      );
      return;
    }
    final retainedMode = _observed == next.identity
        ? value.confirmedMode
        : null;
    final retainedRealtime =
        _observed == next.identity && value.hasRealtimeAuthority;
    _observed = next.identity;
    _available = next.available;
    _epoch++;
    _resetRecovery();
    unawaited(_pending?.cancel());
    _pending = null;
    _refreshQueued = false;
    _revision = null;
    value = ManualPresenceSnapshot(
      scope: next.identity,
      confirmedMode: retainedMode,
      automaticKey: next.automaticKey,
      hasRealtimeAuthority: retainedRealtime,
    );
    unawaited(refresh());
  }

  bool _current(int epoch, PresenceAccountScope scope) =>
      !_disposed &&
      (connectionMode?.allowsOnlineTraffic ?? true) &&
      epoch == _epoch &&
      scope.identity == _account.value.identity &&
      _account.value.available &&
      scope.generation == _session.activeGeneration;

  /// A failed read gets at most three backoff retries. No write is replayed.
  Future<void> refresh() async {
    if (_disposed || !(connectionMode?.allowsOnlineTraffic ?? true)) return;
    if (_pending != null) return;
    final scope = _account.value;
    final epoch = _epoch;
    final realtimeEpoch = _realtimeEpoch;
    if (!scope.available ||
        scope.account == null ||
        scope.generation != _session.activeGeneration) {
      return;
    }
    _retry?.cancel();
    _retry = null;
    try {
      await _request('presence.read', const {'schemaVersion': 1}, scope);
    } on Object catch (error) {
      if (!_current(epoch, scope) || realtimeEpoch != _realtimeEpoch) return;
      // Losing the local confirmation channel cannot prolong an online badge.
      value = ManualPresenceSnapshot(
        scope: value.scope,
        confirmedMode: value.confirmedMode,
        canChange: value.canChange,
        automaticKey: value.automaticKey,
        hasRealtimeAuthority: value.hasRealtimeAuthority,
      );
      final recoverable =
          error is BridgeTimeoutException ||
          error is BridgeDisconnectedException ||
          error is BridgeRemoteException &&
              const {
                'presence.unavailable',
                'presence.storage_unavailable',
                'bridge.backpressure',
                'bridge.busy',
              }.contains(error.code);
      if (!recoverable || _retryAttempt >= 3) return;
      final delay = Duration(seconds: 1 << _retryAttempt++);
      _retry = Timer(delay, () {
        _retry = null;
        if (_current(epoch, scope)) unawaited(refresh());
      });
    }
  }

  void invalidateRealtime() {
    if (_disposed) return;
    _realtimeEpoch++;
    _resetRecovery();
    _refreshQueued = _pending != null;
    value = ManualPresenceSnapshot(
      scope: value.scope,
      confirmedMode: value.confirmedMode,
      canChange: value.canChange,
      automaticKey: value.automaticKey,
      hasRealtimeAuthority: value.hasRealtimeAuthority,
    );
    unawaited(refresh());
  }

  Future<void> _write(PresenceVisibility mode, Object expectedScope) async {
    final scope = _account.value;
    final revision = _revision;
    if (_disposed ||
        !(connectionMode?.allowsOnlineTraffic ?? true) ||
        _pending != null ||
        expectedScope != scope.identity ||
        !scope.available ||
        scope.account == null ||
        revision == null ||
        scope.generation != _session.activeGeneration) {
      throw StateError('Presence context unavailable.');
    }
    try {
      await _request('presence.set', {
        'schemaVersion': 1,
        'expectedRevision': revision,
        'mode': mode.name,
      }, scope);
    } on Object {
      // Failed/uncertain writes are reconciled with a read, never replayed.
      if (!_disposed && expectedScope == _account.value.identity) {
        await refresh();
      }
      rethrow;
    }
  }

  Future<void> _request(
    String method,
    Map<String, Object?> payload,
    PresenceAccountScope scope,
  ) async {
    final epoch = _epoch;
    final realtimeEpoch = _realtimeEpoch;
    final operation = _session.beginRequest(
      method,
      payload: payload,
      accountContext: scope.account,
      timeout: const Duration(seconds: 30),
    );
    _pending = operation;
    try {
      final response = await operation.future;
      if (!_current(epoch, scope)) return;
      if (realtimeEpoch != _realtimeEpoch) {
        _refreshQueued = true;
        return;
      }
      final body = response.payload;
      final hasRealtime = body.containsKey('realtimeStatus');
      final realtimeStatus = body['realtimeStatus'];
      final revision = body['revision'];
      final state = body['state'];
      final mode = switch (body['mode']) {
        'online' => PresenceVisibility.online,
        'inGame' => PresenceVisibility.inGame,
        'invisible' => PresenceVisibility.invisible,
        _ => null,
      };
      final returned = response.accountContext;
      if (returned?.environment != scope.account?.environment ||
          returned?.authority != scope.account?.authority ||
          returned?.subject != scope.account?.subject ||
          body.length != (hasRealtime ? 5 : 4) ||
          realtimeStatus != null &&
              (realtimeStatus is! int ||
                  realtimeStatus < 0 ||
                  realtimeStatus > 3) ||
          body['schemaVersion'] != 1 ||
          mode == null ||
          state != 'ready' && state != 'unconfirmed' ||
          revision is! String ||
          revision != 'missing' &&
              !RegExp(r'^[A-F0-9]{64}$').hasMatch(revision)) {
        throw const BridgeFormatException('Invalid presence response.');
      }
      _revision = revision;
      _resetRecovery();
      value = ManualPresenceSnapshot(
        scope: scope.identity,
        confirmedMode: state == 'ready' ? mode : null,
        canChange: true,
        automaticKey: _account.value.automaticKey,
        hasRealtimeAuthority: hasRealtime,
        realtimeStatus: realtimeStatus as int?,
      );
    } finally {
      if (identical(_pending, operation)) {
        _pending = null;
        if (_refreshQueued && !_disposed) {
          _refreshQueued = false;
          unawaited(refresh());
        }
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _resetRecovery();
    _account.removeListener(_accountChanged);
    unawaited(_pending?.cancel());
    controller.dispose();
    super.dispose();
  }
}
