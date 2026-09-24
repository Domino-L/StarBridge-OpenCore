import 'dart:async';

import 'bridge_connection.dart';
import 'bridge_envelope.dart';

final class InMemoryBridgePair {
  const InMemoryBridgePair({required this.client, required this.host});
  final BridgeConnection client;
  final BridgeConnection host;
}

final class InMemoryBridgeConnection implements BridgeConnection {
  InMemoryBridgeConnection._(this._incoming);

  final StreamController<BridgeEnvelope> _incoming;
  InMemoryBridgeConnection? _peer;
  bool _closed = false;

  static InMemoryBridgePair createPair() {
    final client = InMemoryBridgeConnection._(
      StreamController<BridgeEnvelope>(),
    );
    final host = InMemoryBridgeConnection._(StreamController<BridgeEnvelope>());
    client._peer = host;
    host._peer = client;
    return InMemoryBridgePair(client: client, host: host);
  }

  @override
  Stream<BridgeEnvelope> get incoming => _incoming.stream;

  @override
  Future<void> send(BridgeEnvelope envelope) async {
    if (_closed) {
      throw StateError('Bridge connection is closed.');
    }
    final peer = _peer;
    if (peer == null || peer._closed) {
      throw StateError('Bridge peer is disconnected.');
    }
    final wireCopy = BridgeFrameCodec.decode(BridgeFrameCodec.encode(envelope));
    peer._incoming.add(wireCopy);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    // A single-subscription controller's close future waits for a listener to
    // consume done. A test peer may legitimately never have an incoming
    // listener, so connection shutdown must not wait forever on that detail.
    unawaited(_incoming.close());
  }
}
