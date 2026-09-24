import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'manual_presence.dart';

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

/// One account-scoped Bridge source for both menus, with no extra polling,
/// storage, invented online default or separate tray account session.
class BridgeManualPresence extends ValueNotifier<ManualPresenceSnapshot> {
  BridgeManualPresence(this._session, this._account)
    : super(ManualPresenceSnapshot(scope: _account.value.identity)) {
    controller = ManualPresenceController(source: this, write: _write);
    _account.addListener(_accountChanged);
    _accountChanged();
  }
  final BridgeClientSession _session;
  final ValueListenable<PresenceAccountScope> _account;
  late final ManualPresenceController controller;
  BridgeRequestOperation? _pending;
  String? _revision;
  Object? _observed;
  bool? _available;
  bool _disposed = false;
  int _epoch = 0;

  void _accountChanged() {
    final next = _account.value;
    if (_observed == next.identity && _available == next.available) {
      value = ManualPresenceSnapshot(
        scope: next.identity,
        confirmedMode: value.confirmedMode,
        canChange: value.canChange,
        automaticKey: next.automaticKey,
      );
      return;
    }
    final retainedMode = _observed == next.identity
        ? value.confirmedMode
        : null;
    _observed = next.identity;
    _available = next.available;
    _epoch++;
    unawaited(_pending?.cancel());
    _pending = null;
    _revision = null;
    value = ManualPresenceSnapshot(
      scope: next.identity,
      confirmedMode: retainedMode,
      automaticKey: next.automaticKey,
    );
    unawaited(refresh());
  }

  bool _current(int epoch, PresenceAccountScope scope) =>
      !_disposed &&
      epoch == _epoch &&
      scope.identity == _account.value.identity &&
      _account.value.available &&
      scope.generation == _session.activeGeneration;

  /// Call again on menu opening after a failed connection. Reads never write.
  Future<void> refresh() async {
    if (_disposed || _pending != null) return;
    final scope = _account.value;
    if (!scope.available ||
        scope.account == null ||
        scope.generation != _session.activeGeneration) {
      return;
    }
    try {
      await _request('presence.read', const {'schemaVersion': 1}, scope);
    } on Object {
      /* Unknown stays unknown; opening/reconnecting can retry. */
    }
  }

  Future<void> _write(PresenceVisibility mode, Object expectedScope) async {
    final scope = _account.value;
    final revision = _revision;
    if (_disposed ||
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
      final body = response.payload;
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
          body.length != 4 ||
          body['schemaVersion'] != 1 ||
          mode == null ||
          state != 'ready' && state != 'unconfirmed' ||
          revision is! String ||
          revision != 'missing' &&
              !RegExp(r'^[A-F0-9]{64}$').hasMatch(revision)) {
        throw const BridgeFormatException('Invalid presence response.');
      }
      _revision = revision;
      value = ManualPresenceSnapshot(
        scope: scope.identity,
        confirmedMode: state == 'ready' ? mode : null,
        canChange: true,
        automaticKey: _account.value.automaticKey,
      );
    } finally {
      if (identical(_pending, operation)) _pending = null;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _account.removeListener(_accountChanged);
    unawaited(_pending?.cancel());
    controller.dispose();
    super.dispose();
  }
}
