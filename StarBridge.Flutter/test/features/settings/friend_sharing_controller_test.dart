import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/friend_sharing_controller.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'background refresh allows save and cannot overwrite its receipt',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.ready();
      h.readGate = Completer<void>();
      final refresh = h.controller.refresh();
      await h.readStarted.future;
      expect(h.controller.canEdit, isTrue);
      await h.controller.change(1, true);
      expect(h.controller.fields, 1);
      h.readGate!.complete();
      await refresh;
      expect(h.controller.fields, 1);
      expect(h.writes, hasLength(1));
    },
  );
  test('new account starts off and each bit saves independently', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.ready();
    expect(h.controller.fields, 0);
    for (final bit in [1, 2, 4, 8, 16, 32]) {
      await h.controller.change(bit, true);
    }
    expect(h.controller.fields, 63);
    expect(h.writes.length, 6);
    await h.controller.change(8, false);
    expect(h.controller.fields, 55);
    expect(
      h.writes.last.payload.keys,
      unorderedEquals([
        'schemaVersion',
        'expectedRevision',
        'operationId',
        'fields',
      ]),
    );
  });
  test('uncertain write automatically reads back without replay', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.ready();
    h.fail = true;
    await h.controller.change(1, true);
    await h.ready();
    expect(h.writes.length, 1);
    expect(h.controller.fields, 0);
  });
  test(
    'silent identity change does not submit previous account choice',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.ready();
      h.subject = 'other';
      await h.controller.change(1, true);
      await h.ready();
      expect(h.writes, isEmpty);
    },
  );
  test('invalid bits and malformed authority are rejected', () {
    for (final fields in [-1, 64, 255]) {
      expect(
        () => FriendSharingController.validate({
          'state': 'inactive',
          'snapshot': {
            'schemaVersion': 1,
            'revision': 1,
            'operationId': '0' * 32,
            'appliedAt': '2026-01-01T00:00:00Z',
            'fields': fields,
          },
        }),
        throwsFormatException,
      );
    }
  });
}

class Harness {
  Harness() {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities(const ['friendSharing.settings']);
    subscription = connection.incoming.listen(
      (request) => unawaited(reply(request)),
    );
    controller = FriendSharingController(session);
  }
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late final FriendSharingController controller;
  final writes = <BridgeEnvelope>[];
  String subject = 'synthetic';
  bool fail = false;
  bool loseWriteReceipt = false;
  Completer<void>? readGate;
  final readStarted = Completer<void>();
  Map<String, Object?> snapshot = {
    'schemaVersion': 1,
    'revision': 0,
    'operationId': null,
    'appliedAt': null,
    'fields': null,
  };
  Future<void> reply(BridgeEnvelope request) async {
    final readSnapshot = Map<String, Object?>.of(snapshot);
    if (request.name == 'friendSharing.read' && readGate != null) {
      if (!readStarted.isCompleted) readStarted.complete();
      await readGate!.future;
    }
    if (request.name == 'friendSharing.save') {
      writes.add(request);
      if (!fail) {
        snapshot = {
          'schemaVersion': 1,
          'revision': (request.payload['expectedRevision'] as int) + 1,
          'operationId': request.payload['operationId'],
          'appliedAt': DateTime.now().toUtc().toIso8601String(),
          'fields': request.payload['fields'],
        };
      }
    }
    final failed = (fail || loseWriteReceipt) && request.name == 'friendSharing.save';
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
                code: 'friendsSharing.write_unconfirmed',
                message: 'fixture',
                retryable: false,
              )
            : null,
        payload: request.name == 'account.getCurrent'
            ? {'schemaVersion': 1, 'state': 'signedIn'}
            : {
                'snapshot': request.name.endsWith('.read')
                    ? readSnapshot
                    : snapshot,
                'state': 'inactive',
              },
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
