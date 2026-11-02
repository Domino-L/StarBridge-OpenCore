import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:starbridge_flutter/features/common/organization_ship_image_features.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'official_fleet_shared_ships_test.dart' as catalog;

// Synthetic Bridge responses exercise the real Flutter parser/adapter. These
// fixtures are not the separately required actual C Host/HTTP wire evidence.
String ref(int n) => n.toRadixString(16).padLeft(32, '0');
String hash(int n) => n.toRadixString(16).padLeft(64, '0');
const source = 'officialFleet:7';
const imageNames = OrganizationShipImageFeatures.callableNames;
const imageFeatures = <String, Object?>{
  'protocolVersion': 1,
  'read': true,
  'upload': true,
  'report': true,
  'reduce': true,
};
final pngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

Map<String, Object?> imagePage(
  Map<String, Object?> request, {
  Map<String, Object?>? features = imageFeatures,
  bool hasImage = true,
}) => {
  ...catalog.projection(request),
  'imageFeatures': ?features,
  'ships': [
    {
      ...catalog.ship(),
      'hasCustomImage': hasImage,
      if (hasImage) 'imageVersion': hash(10),
    },
  ],
};
Map<String, Object?> imageChunk(Map<String, Object?> request) => {
  'schemaVersion': 1,
  'targetRef': request['targetRef'],
  'shipRef': request['shipRef'],
  'version': hash(10),
  'contentHash': sha256.convert(pngBytes).toString(),
  'mimeType': 'image/png',
  'totalBytes': pngBytes.length,
  'offset': 0,
  'next': null,
  'data': base64Encode(pngBytes),
  'cropFocusX': .3,
  'cropFocusY': .7,
  'cropZoom': 1.4,
};

class ImageWire {
  ImageWire({
    required Iterable<String> capabilities,
    this.account = const BridgeAccountContext(
      environment: 'synthetic',
      authority: 'scm',
      subject: 'image-fixture-only',
    ),
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    client = pair.client;
    wire = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities(capabilities.toList());
    lifetime = session.events.listen((_) {}, onDone: () => terminal = true);
    subscription = wire.incoming.listen((request) async {
      requests.add(request);
      final value = request.name == 'account.getCurrent'
          ? <String, Object?>{'schemaVersion': 1, 'state': 'signedIn'}
          : await respond(request);
      await wire.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: account,
          status: 'ok',
          payload: value,
        ),
      );
    });
  }
  late final BridgeConnection wire;
  late final BridgeConnection client;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late final StreamSubscription<BridgeEnvelope> lifetime;
  bool terminal = false;
  final sourceChanges = ValueNotifier<String?>(source);
  final requests = <BridgeEnvelope>[];
  FutureOr<Map<String, Object?>> Function(BridgeEnvelope) respond = (_) =>
      throw StateError('Missing synthetic response');
  final BridgeAccountContext account;
  Future<void> close() async {
    // A transport-done test has already closed the session streams. Do not
    // enter a second active-shutdown path inside WidgetTest FakeAsync cleanup.
    if (!terminal) await session.close();
    await lifetime.cancel();
    await subscription.cancel();
    await wire.close();
    sourceChanges.dispose();
  }
}
