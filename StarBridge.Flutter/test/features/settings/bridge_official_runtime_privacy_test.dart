import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/bridge_local_privacy.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test('actual Bridge consumes exact opaque scope and renews common lease before Apply', () async {
    final h = OfficialPrivacyBridgeHarness();
    addTearDown(h.close);
    await h.adapter.read();
    final scope = await h.adapter.readOfficialRuntimePrivacy();
    final receipt = await h.adapter.saveOfficialRuntimePrivacy(
      scope: scope,
      expectedRevision: 1,
      fields: 1,
      cancelSavedScope: false,
    );
    expect(receipt.revision, 2);
    final save = h.requests.singleWhere(
      (r) => r.name == 'privacy.officialFleetSave',
    );
    expect(save.payload.keys.toSet(), {
      'schemaVersion',
      'contextRef',
      'expectedRevision',
      'operationId',
      'fields',
    });
    expect(save.payload['contextRef'], 'a' * 32);
    await expectLater(
      h.adapter.publication('apply', revision: 2),
      throwsA(isA<BridgeClientException>()),
    );
    expect(
      h.requests.where((r) => r.name == 'privacy.applyPublication'),
      isEmpty,
    );
    await h.adapter.read();
    await h.adapter.publication('apply', revision: 2);
    expect(
      h.requests.where((r) => r.name == 'privacy.applyPublication'),
      hasLength(1),
    );
  });
  test('missing capability sends no scope request and malformed identity-bearing scope is rejected', () async {
    final h = OfficialPrivacyBridgeHarness();
    addTearDown(h.close);
    h.session.acceptHostCapabilities(['privacy.local', 'privacy.publication']);
    await h.adapter.read();
    await expectLater(
      h.adapter.readOfficialRuntimePrivacy(),
      throwsA(isA<BridgeClientException>()),
    );
    expect(
      h.requests.where((r) => r.name == 'privacy.officialFleetRead'),
      isEmpty,
    );
    h.session.acceptHostCapabilities([
      'privacy.local',
      'privacy.publication',
      'privacy.officialFleetScopes',
    ]);
    await Future<void>.delayed(Duration.zero);
    h.addRawAuthority = true;
    await expectLater(
      h.adapter.readOfficialRuntimePrivacy(),
      throwsFormatException,
    );
  });
  test(
    'generation retirement rejects an old editor without sending a save',
    () async {
      final h = OfficialPrivacyBridgeHarness();
      addTearDown(h.close);
      await h.adapter.read();
      final scope = await h.adapter.readOfficialRuntimePrivacy();
      h.session.advanceGeneration(2);
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        h.adapter.saveOfficialRuntimePrivacy(
          scope: scope,
          expectedRevision: 1,
          fields: 15,
          cancelSavedScope: false,
        ),
        throwsA(isA<BridgeClientException>()),
      );
      expect(
        h.requests.where((r) => r.name == 'privacy.officialFleetSave'),
        isEmpty,
      );
    },
  );
  test(
    'lost save receipt cannot reuse ref, Apply old lease or replay on refresh',
    () async {
      final h = OfficialPrivacyBridgeHarness(
        timeout: const Duration(milliseconds: 20),
      );
      addTearDown(h.close);
      await h.adapter.read();
      final scope = await h.adapter.readOfficialRuntimePrivacy();
      h.dropSaveReply = true;
      await expectLater(
        h.adapter.saveOfficialRuntimePrivacy(
          scope: scope,
          expectedRevision: 1,
          fields: 1,
          cancelSavedScope: false,
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        h.adapter.publication('apply', revision: 1),
        throwsA(isA<BridgeClientException>()),
      );
      expect((await h.adapter.read()).revision, 2);
      expect((await h.adapter.readOfficialRuntimePrivacy()).fields, 1);
      expect(
        h.requests.where((r) => r.name == 'privacy.officialFleetSave'),
        hasLength(1),
      );
      expect(
        h.requests.where((r) => r.name == 'privacy.applyPublication'),
        isEmpty,
      );
    },
  );
}

/// Synthetic transport facts only; the production Bridge adapter is exercised.
final class OfficialPrivacyBridgeHarness {
  OfficialPrivacyBridgeHarness({
    Duration timeout = const Duration(seconds: 15),
  }) {
    session =
        BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
          requestTimeout: timeout,
        )..acceptHostCapabilities([
          'privacy.local',
          'privacy.publication',
          'privacy.officialFleetScopes',
        ]);
    adapter = BridgeLocalPrivacy(session);
    host = pair.host.incoming.listen((r) async {
      if (r.messageType != 'request') return;
      requests.add(r);
      if (r.name == 'bridge.cancel') return;
      Map<String, Object?> body;
      if (r.name == 'account.getCurrent') {
        body = {'schemaVersion': 1, 'state': 'signedIn'};
      } else if (r.name == 'privacy.localRead') {
        body = {
          'schemaVersion': 1,
          'revision': revision,
          'savedAt': '2026-10-17T00:00:00Z',
          'operationId': operation,
          'settings': LocalPrivacySettings.editorDefaults
              .copyWith(communities: [])
              .toJson(),
          'publicationAvailable': false,
        };
      } else if (r.name == 'privacy.officialFleetRead') {
        body = {
          'schemaVersion': 1,
          'state': 'available',
          'sourceRef': 'officialFleet:7',
          'scopeRef': 'c' * 32,
          'contextRef': 'a' * 32,
          'cancelContextRef': 'b' * 32,
          'revision': revision,
          'fields': fields,
          'savedFields': fields,
          'savedForCurrentSource': fields != 0,
          'canSave': true,
          'canCancel': fields != 0,
          'publicationApplied': false,
          if (addRawAuthority) 'authorityNamespace': 'must-not-reach-ui',
        };
      } else if (r.name == 'privacy.officialFleetSave') {
        expect(r.payload['expectedRevision'], revision);
        fields = r.payload['fields'] as int;
        operation = r.payload['operationId'] as String;
        revision++;
        if (dropSaveReply) return;
        body = {
          'schemaVersion': 1,
          'revision': revision,
          'operationId': operation,
          'fields': fields,
          'state': 'saved',
          'publicationApplied': false,
        };
      } else if (r.name == 'privacy.applyPublication') {
        expect(r.payload['expectedRevision'], revision);
        body = {
          'schemaVersion': 1,
          'supportedFields': 15,
          'state': 'applied',
          'appliedRevision': revision,
          'firstUseRequired': false,
        };
      } else {
        throw StateError('Unexpected ${r.name}');
      }
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: r.name,
          correlationId: r.correlationId,
          sessionGeneration: r.sessionGeneration,
          accountContext: owner,
          payload: body,
          status: 'ok',
        ),
      );
    });
  }
  static const owner = BridgeAccountContext(
    environment: 'fixture',
    authority: 'scm',
    subject: 'synthetic',
  );
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeLocalPrivacy adapter;
  late final StreamSubscription<BridgeEnvelope> host;
  final requests = <BridgeEnvelope>[];
  int revision = 1, fields = 0;
  String operation = '1' * 32;
  bool dropSaveReply = false, addRawAuthority = false;
  Future<void> close() async {
    await adapter.close();
    await host.cancel();
    await session.close();
    await pair.host.close();
  }
}
