import 'dart:async';

import '../bridge/bridge_client_session.dart';
import '../bridge/bridge_envelope.dart';
import 'native_host_connector.dart';

/// Revalidates protocol support after the existing account/mode owner changes.
/// It never logs in, reconnects, publishes, or treats capabilities as grants.
final class HostCapabilityRefresh {
  HostCapabilityRefresh(
    this.session,
    this.hostInstanceId,
    this.requiredCapabilities,
  ) {
    _unobserve = session.observeGenerationChanges((_, _) {
      retire();
      unawaited(refresh());
    });
    _events = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        retire();
        unawaited(refresh());
      }
    });
    _unbind = session.registerHostCapabilityRefresh(
      refresh: refresh,
      retire: retire,
    );
  }
  final BridgeClientSession session;
  final String hostInstanceId;
  final List<String> requiredCapabilities;
  late final void Function() _unobserve, _unbind;
  late final StreamSubscription<BridgeEnvelope> _events;
  Future<void>? _pending;
  int _revision = 0, _requested = 0;
  bool _closed = false;
  static const dynamicCapabilities = {
    'privacy.officialFleetScopes',
    'officialFleet.runtimeMembers',
    'officialFleet.runtimeActivity',
    'account.gameIdentity.v1',
  };

  void retire() {
    if (_closed) return;
    ++_revision;
    session.acceptHostCapabilities(
      session.hostCapabilities.where(
        (cap) => !dynamicCapabilities.contains(cap),
      ),
    );
  }

  static Set<String>? validateReady(
    BridgeEnvelope reply,
    String instance,
    Iterable<String> required,
  ) {
    final body = reply.payload;
    if (body['ready'] != true || body['hostInstanceId'] != instance) {
      throw const NativeHostConnectionException('host.ready_invalid');
    }
    if (!body.containsKey('hostCapabilities')) return null;
    final values = body['hostCapabilities'];
    if (values is! List ||
        values.length > 512 ||
        values.any(
          (value) =>
              value is! String ||
              value.isEmpty ||
              value.length > 256 ||
              value.trim() != value ||
              RegExp(r'[\u0000-\u001f\u007f-\u009f]').hasMatch(value),
        )) {
      throw const NativeHostConnectionException('host.ready_invalid');
    }
    final caps = values.cast<String>().toSet();
    if (caps.length != values.length || !required.every(caps.contains)) {
      throw const NativeHostConnectionException('host.capability_missing');
    }
    return Set.unmodifiable(caps);
  }

  Future<void> refresh() {
    if (_closed || session.connectionModeChanging) return Future.value();
    ++_requested;
    return _pending ??= _drain().whenComplete(() => _pending = null);
  }

  Future<void> _drain() async {
    var completed = -1;
    while (!_closed &&
        !session.connectionModeChanging &&
        completed != _requested) {
      final requested = _requested, revision = _revision;
      final generation = session.activeGeneration;
      try {
        final reply = await session.request('host.ready');
        if (_closed ||
            revision != _revision ||
            requested != _requested ||
            session.connectionModeChanging ||
            generation != session.activeGeneration ||
            reply.sessionGeneration != generation) {
          continue;
        }
        final caps = validateReady(reply, hostInstanceId, requiredCapabilities);
        if (caps != null) session.acceptHostCapabilities(caps);
      } on Object {
        // Keep optional protocol support retired on failure. A later explicit
        // lifecycle refresh can recover it; no account operation is replayed.
      }
      completed = requested;
    }
  }

  Future<void> close() async {
    _closed = true;
    ++_revision;
    _unobserve();
    _unbind();
    await _events.cancel();
  }
}
