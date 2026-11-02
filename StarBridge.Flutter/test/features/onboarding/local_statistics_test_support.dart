import 'dart:async';

import 'package:starbridge_flutter/features/onboarding/bridge_local_statistics_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/local_statistics_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

Map<String, Object?> statisticsWire({
  String state = 'choiceRequired',
  String? key = '11111111111111111111111111111111',
  String consent = 'unknown',
  int? seconds = 0,
  bool recording = false,
}) => {
  'schemaVersion': 1,
  'state': state,
  'choiceKey': key,
  'consent': consent,
  'savedSeconds': seconds,
  'recording': recording,
};

final class FakeStatisticsPort implements LocalStatisticsPort {
  final events = StreamController<void>.broadcast(sync: true);
  LocalStatisticsSnapshot snapshot = LocalStatisticsWire.parse(
    statisticsWire(),
  );
  int reads = 0, confirmations = 0;
  bool failRead = false, failConfirm = false;
  Future<LocalStatisticsSnapshot>? pendingRead, pendingConfirm;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<LocalStatisticsSnapshot> read() async {
    reads++;
    if (failRead) throw StateError('Synthetic read failed.');
    return pendingRead ?? snapshot;
  }

  @override
  Future<LocalStatisticsSnapshot> confirm(String key, bool allowed) async {
    confirmations++;
    if (failConfirm) throw StateError('Synthetic confirmation failed.');
    if (pendingConfirm != null) return pendingConfirm!;
    snapshot = LocalStatisticsWire.parse(
      statisticsWire(
        state: 'saved',
        key: '22222222222222222222222222222222',
        consent: allowed ? 'allowed' : 'declined',
      ),
    );
    return snapshot;
  }

  Future<void> close() => events.close();
}

class StatisticsBridgeFixture {
  StatisticsBridgeFixture({bool capabilities = true}) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 3,
    );
    if (capabilities) {
      session.acceptHostCapabilities([BridgeLocalStatisticsAdapter.capability]);
    }
    adapter = BridgeLocalStatisticsAdapter(session);
    subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      if (onRequest != null) {
        await onRequest!(request);
      } else {
        await respond(request);
      }
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeLocalStatisticsAdapter adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  Map<String, Object?>? payload;
  Future<void> Function(BridgeEnvelope)? onRequest;
  Future<void> respond(BridgeEnvelope request) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      status: 'ok',
      payload:
          payload ??
          (request.name.endsWith('confirm')
              ? statisticsWire(
                  state: 'saved',
                  key: '22222222222222222222222222222222',
                  consent: request.payload['allowed'] == true
                      ? 'allowed'
                      : 'declined',
                )
              : statisticsWire()),
    ),
  );
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}
