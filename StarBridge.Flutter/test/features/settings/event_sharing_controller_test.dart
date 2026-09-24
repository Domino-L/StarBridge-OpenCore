import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/event_sharing_controller.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'single CAS save keeps other scopes and exact membership timestamp',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.ready();
      expect(h.controller.choice(null).enabled, isFalse);
      await h.controller.change(
        'A',
        const EventSharingChoice(enabled: true, selectedTypes: 32),
      );
      expect(h.writes.length, 1);
      final write = h.writes.single.payload;
      expect(write['expectedRevision'], 0);
      final settings = write['settings'] as Map;
      expect(settings['room'], {'enabled': false, 'selectedTypes': 47});
      final rows = settings['communities'] as List;
      expect(rows[0]['joinedAt'], Harness.joined);
      expect(rows[1]['choice'], {'enabled': false, 'selectedTypes': 47});
      expect(h.controller.choice('A').selectedTypes, 32);
      expect(h.controller.snapshot!['revision'], 1);
    },
  );
  test(
    'changed account without event cannot write previous account settings',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.ready();
      h.subject = 'other-synthetic-owner';
      await h.controller.change(
        null,
        const EventSharingChoice(enabled: true, selectedTypes: 1),
      );
      expect(h.writes, isEmpty);
      expect(h.controller.snapshot, isNull);
      expect(h.controller.error, 'events.account_changed');
      await h.controller.refresh();
      expect(h.controller.canEdit, isTrue);
    },
  );
  test(
    'uncertain write keeps displayed settings and never replays on read',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.ready();
      h.failSave = true;
      await h.controller.change(
        null,
        const EventSharingChoice(enabled: true, selectedTypes: 1),
      );
      expect(h.controller.snapshot!['revision'], 0);
      expect(h.controller.canEdit, isFalse);
      await h.controller.refresh();
      expect(h.writes.length, 1);
      expect(h.controller.canEdit, isTrue);
    },
  );
  test('rejoining does not reuse an old membership grant', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.ready();
    await h.controller.change(
      'A',
      const EventSharingChoice(enabled: true, selectedTypes: 32),
    );
    h.joinedAt = '2026-09-14T00:00:00.0000001+00:00';
    await h.controller.refresh();
    expect(h.controller.choice('A').enabled, isFalse);
  });
}

final class Harness {
  Harness() {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities(const ['eventSharing.settings']);
    subscription = connection.incoming.listen((request) {
      unawaited(reply(request));
    });
    controller = EventSharingController(session);
  }
  static const joined = '2026-09-01T00:00:00.1234567+00:00';
  String joinedAt = joined;
  String subject = 'synthetic-owner';
  bool failSave = false;
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late final EventSharingController controller;
  final writes = <BridgeEnvelope>[];
  Map<String, Object?> snapshot = {
    'schemaVersion': 1,
    'revision': 0,
    'operationId': null,
    'appliedAt': null,
    'publicationEnabled': false,
    'settings': null,
  };
  Future<void> reply(BridgeEnvelope request) async {
    if (request.name == 'eventSharing.save') {
      writes.add(request);
      if (!failSave) {
        snapshot = {
          'schemaVersion': 1,
          'revision': (request.payload['expectedRevision'] as int) + 1,
          'operationId': request.payload['operationId'],
          'appliedAt': DateTime.now().toUtc().toIso8601String(),
          'publicationEnabled': request.payload['publicationEnabled'],
          'settings': request.payload['settings'],
        };
      }
    }
    final failed = request.name == 'eventSharing.save' && failSave;
    await connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: BridgeAccountContext(
          environment: 'test',
          authority: 'scm',
          subject: subject,
        ),
        status: failed ? 'error' : 'ok',
        error: failed
            ? const BridgeErrorBody(
                code: 'events.write_unconfirmed',
                message: 'fixture',
                retryable: false,
              )
            : null,
        payload: request.name == 'account.getCurrent'
            ? {'schemaVersion': 1, 'state': 'signedIn'}
            : request.name == 'privacy.communityTargets'
            ? {
                'schemaVersion': 2,
                'primaryFleetCode': null,
                'communities': [
                  for (final code in ['A', 'B'])
                    {'code': code, 'name': code, 'joinedAt': joinedAt},
                ],
              }
            : {'snapshot': snapshot, 'state': 'inactive'},
      ),
    );
  }

  Future<void> ready() async {
    for (var i = 0; i < 100 && !controller.canEdit; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.canEdit, isTrue, reason: controller.error);
  }

  Future<void> close() async {
    controller.dispose();
    await subscription.cancel();
    await session.close();
    await connection.close();
  }
}
