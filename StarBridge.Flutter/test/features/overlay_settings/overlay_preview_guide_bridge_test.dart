import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  for (final recovered in [false, true]) {
    test('guide writes only a local preference patch recovered=$recovered', () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(connection: pair.client, sessionGeneration: 10)
        ..acceptHostCapabilities(['applicationPreferences.read', 'applicationPreferences.write']);
      final requests = <BridgeEnvelope>[];
      var seen = false;
      final subscription = pair.host.incoming.listen((request) {
        requests.add(request);
        if (request.name == 'applicationPreferences.update') {
          expect(request.accountContext, isNull);
          expect(request.payload['expectedRevision'], 17);
          expect(request.payload['patch'], {'appearancePreviewGuideSeen': true});
          seen = true;
        }
        unawaited(pair.host.send(BridgeEnvelope(
          protocolVersion: 1, messageType: 'response', name: request.name,
          correlationId: request.correlationId, sessionGeneration: 10,
          status: 'ok', payload: {
            'schemaVersion': 1, 'revision': 17,
            'storageState': recovered ? 'recoveredDefaults' : 'ready',
            'preferences': {'appearancePreviewGuideSeen': seen},
          },
        )));
      });
      addTearDown(subscription.cancel);
      addTearDown(session.close);
      final adapter = BridgeOverlayWorkspaceAdapter(session);
      if (recovered) {
        await expectLater(adapter.readPreviewGuideSeen(), throwsStateError);
        await expectLater(adapter.markPreviewGuideSeen(), throwsStateError);
        expect(seen, false);
      } else {
        expect(await adapter.readPreviewGuideSeen(), false);
        await adapter.markPreviewGuideSeen();
        expect(await adapter.readPreviewGuideSeen(), true);
      }
      expect(requests.every((r) => r.name.startsWith('applicationPreferences.')), true);
      expect(requests.every((r) => r.accountContext == null), true);
    });
  }
}
