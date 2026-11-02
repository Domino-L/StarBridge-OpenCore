import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import 'native_overlay_observation.dart';

/// Borrowed connection; observation reads never send a runtime/preview command.
/// Owners must dispose this adapter, not the shared Bridge session.
final class BridgeNativeOverlayObservation
    implements NativeOverlayObservationPort {
  BridgeNativeOverlayObservation(this.session) {
    _subscription = session.events
        .where(
          (event) => const {
            'account.changed',
            'bootstrap.invalidated',
            'onboarding.changed',
          }.contains(event.name),
        )
        .listen((_) {
          _epoch++;
          if (!_closed) _invalidations.add(null);
        });
  }
  static const capability = 'onboarding.nativeOverlayObservation.v1';
  static const readRequest = 'onboarding.nativeOverlayObservation.read';
  final BridgeClientSession session;
  final _invalidations = StreamController<void>.broadcast(sync: true);
  late final StreamSubscription<Object?> _subscription;
  int _epoch = 0;
  bool _closed = false;
  @override
  Stream<void> get invalidations => _invalidations.stream;

  @override
  Future<NativeOverlayObservation?> read() async {
    if (_closed) throw StateError('Native observation is closed.');
    final epoch = ++_epoch, generation = session.activeGeneration;
    if (!session.hostCapabilities.contains(capability)) {
      _invalidations.add(null);
      return null;
    }
    try {
      final response = await session.request(
        readRequest,
        payload: const {'schemaVersion': 1},
      );
      if (_closed ||
          epoch != _epoch ||
          generation != session.activeGeneration ||
          response.sessionGeneration != generation ||
          !session.hostCapabilities.contains(capability) ||
          response.status != 'ok' ||
          response.error != null) {
        throw StateError('Native observation is no longer current.');
      }
      return NativeOverlayObservationWire.parse(response.payload, generation);
    } on Object {
      // Do not let a failed latest read leave an old baseline in its consumer.
      // An older request finishing late must not invalidate a newer observation.
      if (!_closed && epoch == _epoch) {
        _epoch++;
        _invalidations.add(null);
      }
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _epoch++;
    await _subscription.cancel();
    await _invalidations.close();
  }
}
