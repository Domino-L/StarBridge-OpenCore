import 'dart:async';

import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

Map<String, Object?> onlineWire({
  String state = 'signInRequired',
  String mode = 'signInRequired',
  int revision = 3,
  String? local,
  String? remote,
  String? display,
  String? key,
}) => {
  'schemaVersion': 1,
  'revision': revision,
  'modeState': mode,
  'identity': <String, Object?>{
    'state': state,
    'localHandle': local,
    'authoritativeHandle': remote,
    'accountDisplayName': display,
    'confirmationKey': key,
  },
};
Map<String, Object?> reviewWire({bool confirmed = false}) => onlineWire(
  state: confirmed ? 'confirmedForHandoff' : 'reviewRequired',
  local: 'Pilot-Example',
  remote: 'PILOT-EXAMPLE',
  display: 'Synthetic Pilot',
  key: confirmed ? null : '11111111111111111111111111111111',
);

final class FakeOnlinePort implements OnlineReviewPort {
  OnlineReviewSnapshot snapshot = OnlineReviewWire.parse(onlineWire());
  final events = StreamController<void>.broadcast(sync: true);
  final actions = <OnlineReviewAction>[];
  int reads = 0;
  Future<OnlineReviewSnapshot> Function()? onRead;
  Future<OnlineReviewSnapshot> Function(OnlineReviewAction)? onAction;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<OnlineReviewSnapshot> read() async {
    reads++;
    return onRead?.call() ?? snapshot;
  }

  @override
  Future<OnlineReviewSnapshot> execute(
    OnlineReviewAction action,
    int revision, {
    String? confirmationKey,
  }) async {
    actions.add(action);
    if (onAction != null) return onAction!(action);
    snapshot = OnlineReviewWire.parse(switch (action) {
      OnlineReviewAction.begin => onlineWire(),
      OnlineReviewAction.login => onlineWire(state: 'needsLocalIdentity'),
      OnlineReviewAction.resume => onlineWire(state: 'needsLocalIdentity'),
      OnlineReviewAction.reauthorize => onlineWire(state: 'needsLocalIdentity'),
      OnlineReviewAction.review => reviewWire(),
      OnlineReviewAction.confirm => reviewWire(confirmed: true),
      OnlineReviewAction.cancel => onlineWire(
        mode: 'local',
        state: 'notStarted',
        revision: revision + 1,
      ),
    });
    return snapshot;
  }

  Future<void> close() => events.close();
}

final class OnlineBridgeFixture {
  OnlineBridgeFixture({bool capability = true, bool retainedProtocol = false}) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    if (capability) {
      session.acceptHostCapabilities([
        retainedProtocol
            ? BridgeOnlineReviewAdapter.retainedCapability
            : BridgeOnlineReviewAdapter.capability,
      ]);
    }
    adapter = BridgeOnlineReviewAdapter(session);
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
  late final BridgeOnlineReviewAdapter adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  Map<String, Object?> payload = onlineWire();
  Future<void> Function(BridgeEnvelope)? onRequest;
  Future<void> respond(
    BridgeEnvelope request, {
    Map<String, Object?>? value,
    BridgeAccountContext? context,
  }) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      status: 'ok',
      accountContext: context,
      payload: value ?? payload,
    ),
  );
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}
