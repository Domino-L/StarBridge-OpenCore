import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'management requires its optional Host capability before dispatch',
    () async {
      final host = Harness(
        capabilities: ['partyRooms.read', 'partyRooms.commands'],
      );
      final result = await host.adapter.execute(
        RoomCommand(RoomOperation.close, {'roomId': 'r1'}),
      );
      expect(result.error, 'hostUnavailable');
      expect(host.requests, isEmpty);
      await host.close();
    },
  );
  test('signed out management never dispatches a room command', () async {
    final host = Harness(signedIn: false, capabilities: managementCapabilities);
    final result = await host.adapter.execute(
      RoomCommand(RoomOperation.close, {'roomId': 'r1'}),
    );
    expect(result.error, 'identityUnavailable');
    expect(host.requests.map((r) => r.name), ['account.getCurrent']);
    await host.close();
  });
  for (final approved in [true, false]) {
    test(
      'management receives authoritative ${approved ? 'approval' : 'decline'} result',
      () async {
        final host = Harness(
          capabilities: managementCapabilities,
          commandPayload: {
            'schemaVersion': 1,
            'status': approved ? 'approved' : 'declined',
            'directory': emptyDirectory,
          },
        );
        final command = RoomCommand(RoomOperation.decide, {
          'roomId': 'r1',
          'applicationId': 'a1',
          'approve': approved,
        });
        final result = await host.adapter.execute(command);
        expect(result.accepted, isTrue);
        expect(result.status, approved ? 'approved' : 'declined');
        expect(result.directory, isNotNull);
        expect(host.requests.map((r) => r.name), [
          'account.getCurrent',
          'partyRooms.execute',
        ]);
        expect(host.requests.last.accountContext?.subject, 'test-subject');
        expect(host.requests.last.payload, {
          'schemaVersion': 1,
          'operation': 'decide',
          'data': command.data,
        });
        await host.close();
      },
    );
  }
  test('management success without refreshed state has unknown outcome and is not retried', () async {
    final host = Harness(
      capabilities: managementCapabilities,
      commandPayload: {'schemaVersion': 1, 'status': 'updated'},
    );
    final result = await host.adapter.execute(
      RoomCommand(RoomOperation.update, {'roomId': 'r1'}),
    );
    expect(result.status, 'unknown');
    expect(result.error, 'outcomeUnknown');
    expect(
      host.requests.where((r) => r.name == 'partyRooms.execute'),
      hasLength(1),
    );
    await host.close();
  });
  test('failed management preflight is a safe rejection', () async {
    final host = Harness(
      capabilities: managementCapabilities,
      error: 'party_rooms.command_unavailable',
    );
    final result = await host.adapter.execute(
      RoomCommand(RoomOperation.close, {'roomId': 'r1'}),
    );
    expect(result.status, 'rejected');
    expect(result.error, 'unavailable');
    await host.close();
  });
  test('an older Host disables only room reads', () async {
    final host = Harness();
    host.session.acceptHostCapabilities([]);
    expect((await host.adapter.read()).failure, 'hostUnavailable');
    expect(host.requests, isEmpty);
    await host.close();
  });
  test(
    'directory read carries account context and only uses read requests',
    () async {
      final host = Harness();
      final result = await host.adapter.read();
      expect(result.state, RoomReadState.ready);
      expect(result.directory!.rooms, isEmpty);
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'partyRooms.getDirectory',
      ]);
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      expect(host.requests.last.payload, {'schemaVersion': 1});
      await host.close();
    },
  );
  test('signed out does not call room service', () async {
    final host = Harness(signedIn: false);
    expect((await host.adapter.read()).state, RoomReadState.signedOut);
    expect(host.requests, hasLength(1));
    await host.close();
  });
  test(
    'identity link failure never logs out or automatically migrates',
    () async {
      final host = Harness(error: 'party_rooms.identity_unavailable');
      expect((await host.adapter.read()).failure, 'identityUnavailable');
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'partyRooms.getDirectory',
      ]);
      await host.close();
    },
  );
  test('account changes invalidate the room projection', () async {
    final host = Harness();
    final event = host.adapter.invalidations.first;
    await host.connection.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 5,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await event.timeout(const Duration(seconds: 1));
    await host.close();
  });
}

const managementCapabilities = [
  'partyRooms.read',
  'partyRooms.commands',
  'partyRooms.manage',
];
const emptyDirectory = <String, Object?>{
  'schemaVersion': 1,
  'rooms': [],
  'currentRoomId': null,
  'serverTime': '2026-09-05T12:00:00Z',
};

class Harness {
  Harness({
    bool signedIn = true,
    String? error,
    List<String> capabilities = const ['partyRooms.read'],
    Map<String, Object?>? commandPayload,
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    adapter = BridgePartyRoomsAdapter(session);
    session.acceptHostCapabilities(capabilities);
    subscription = connection.incoming.listen((request) {
      requests.add(request);
      final account = request.name == 'account.getCurrent';
      final failed = !account && error != null;
      unawaited(
        connection.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: signedIn
                ? const BridgeAccountContext(
                    environment: 'test',
                    authority: 'scm-test',
                    subject: 'test-subject',
                  )
                : null,
            status: failed ? 'error' : 'ok',
            error: failed
                ? BridgeErrorBody(
                    code: error,
                    message: 'private upstream body',
                    retryable: false,
                  )
                : null,
            payload: account
                ? {
                    'schemaVersion': 1,
                    'state': signedIn ? 'signedIn' : 'signedOut',
                  }
                : request.name == 'partyRooms.execute' && commandPayload != null
                ? commandPayload
                : {
                    'schemaVersion': 1,
                    'rooms': [],
                    'currentRoomId': null,
                    'serverTime': '2026-09-05T12:00:00Z',
                  },
          ),
        ),
      );
    });
  }
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final BridgePartyRoomsAdapter adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  Future<void> close() async {
    await adapter.close();
    await subscription.cancel();
    await session.close();
    await connection.close();
  }
}
