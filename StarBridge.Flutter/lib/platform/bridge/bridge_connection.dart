import 'bridge_envelope.dart';

abstract interface class BridgeConnection {
  Stream<BridgeEnvelope> get incoming;

  Future<void> send(BridgeEnvelope envelope);

  Future<void> close();
}
