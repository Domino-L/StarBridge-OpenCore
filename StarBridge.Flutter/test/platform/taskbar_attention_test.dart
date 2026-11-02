import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/taskbar_attention_binding.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';

import '../features/party_rooms/party_rooms_test.dart'
    show TestRoomsPort, ready, wire, room;

void main() {
  test('independent application bindings do not silence each other', () async {
    final firstChanges = ValueNotifier(false);
    final secondChanges = ValueNotifier(false);
    final firstEvents = <Map<String, Object?>>[];
    final secondEvents = <Map<String, Object?>>[];
    final first = TaskbarAttentionBinding(
      scope: TaskbarAttentionScope(),
      changes: [firstChanges],
      pending: () => firstChanges.value,
      reduceMotion: () => false,
      publish: (value) async => firstEvents.add(value),
    );
    final second = TaskbarAttentionBinding(
      scope: TaskbarAttentionScope(),
      changes: [secondChanges],
      pending: () => secondChanges.value,
      reduceMotion: () => false,
      publish: (value) async => secondEvents.add(value),
    );
    firstChanges.value = true;
    secondChanges.value = true;
    await Future<void>.delayed(Duration.zero);
    expect(firstEvents.last['pending'], true);
    expect(secondEvents.last['pending'], true);
    first.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(firstEvents.last['pending'], false);
    expect(secondEvents.last['pending'], true);
    second.dispose();
    firstChanges.dispose();
    secondChanges.dispose();
  });
  test('room pending attention survives read failure until confirmed completion or denial', () async {
    final mine = room('a')
      ..['viewerIsHost'] = true
      ..['pendingApplications'] = [
        {
          'applicationId': 'synthetic',
          'callsign': 'Applicant',
          'gameId': 'Example',
          'createdAt': '2026-09-06T11:00:00Z',
        },
      ];
    final port = TestRoomsPort()
      ..result = ready(wire(current: 'a', rooms: [mine]));
    final module = PartyRoomsModule(port);
    await module.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(module.activityCount.value, 1);
    module.select('a');
    await Future<void>.delayed(Duration.zero);
    expect(module.applicationCount, 1);
    expect(module.activityCount.value, 1);
    port.result = const RoomReadResult(RoomReadState.unavailable);
    await module.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(module.activityCount.value, 1);
    port.result = const RoomReadResult(
      RoomReadState.unavailable,
      failure: 'forbidden',
    );
    await module.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(module.activityCount.value, 0);
    module.dispose();
  });
  test(
    'all sources retain attention until every unread/task is cleared',
    () async {
      final sources = List.generate(7, (_) => ValueNotifier(0));
      final reduce = ValueNotifier(false);
      final emitted = <Map<String, Object?>>[];
      final binding = TaskbarAttentionBinding(
        scope: TaskbarAttentionScope(),
        changes: [...sources, reduce],
        pending: () => sources.any((v) => v.value > 0),
        reduceMotion: () => reduce.value,
        publish: (v) async => emitted.add(v),
      );
      await Future<void>.delayed(Duration.zero);
      for (final source in sources) {
        source.value = 1;
        await Future<void>.delayed(Duration.zero);
        expect(emitted.last['pending'], true);
      }
      expect(
        emitted.length,
        2,
      ); // No restart on bursts or different positive count.
      for (final source in sources.take(6)) {
        source.value = 0;
      }
      await Future<void>.delayed(Duration.zero);
      expect(emitted.last['pending'], true);
      reduce.value = true;
      await Future<void>.delayed(Duration.zero);
      expect(emitted.last, {'pending': true, 'reduceMotion': true});
      sources.last.value = 0;
      await Future<void>.delayed(Duration.zero);
      expect(emitted.last['pending'], false);
      binding.dispose();
      for (final source in sources) {
        source.dispose();
      }
      reduce.dispose();
    },
  );
  test('old in-flight binding cannot clear its replacement', () async {
    final scope = TaskbarAttentionScope();
    final gate = Completer<void>();
    final change = ValueNotifier(0);
    final old = <Map<String, Object?>>[], next = <Map<String, Object?>>[];
    final first = TaskbarAttentionBinding(
      scope: scope,
      changes: [change],
      pending: () => true,
      reduceMotion: () => false,
      publish: (v) async {
        old.add(v);
        await gate.future;
      },
    );
    first.dispose();
    final second = TaskbarAttentionBinding(
      scope: scope,
      changes: [change],
      pending: () => true,
      reduceMotion: () => false,
      publish: (v) async => next.add(v),
    );
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(old, [
      {'pending': true, 'reduceMotion': false},
    ]);
    expect(next.last['pending'], true);
    second.dispose();
    change.dispose();
  });
  test(
    'pending management is fenced and independent from inbox read receipts',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      final inbox = NotificationInboxController(session);
      var sequence = 0;
      Future<void> emit(
        String name,
        Map<String, Object?> payload, {
        int generation = 1,
      }) async {
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: name,
            sessionGeneration: generation,
            sequence: ++sequence,
            payload: payload,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      await emit('notificationSettings.pendingManagement', {
        'schemaVersion': 1,
        'count': 2,
      });
      expect(inbox.pendingManagement.value, 2);
      inbox.unread.value = 0; // Reading the inbox isn't approving applicants.
      expect(inbox.pendingManagement.value, 2);
      await emit('notificationSettings.pendingManagement', {
        'schemaVersion': 1,
        'count': -1,
      });
      expect(inbox.pendingManagement.value, 2);
      await emit('notificationSettings.pendingManagement', {
        'schemaVersion': 1,
        'count': 0,
      }, generation: 0);
      expect(inbox.pendingManagement.value, 2);
      await emit('notificationSettings.pendingManagement', {
        'schemaVersion': 1,
        'count': 0,
      });
      expect(inbox.pendingManagement.value, 0);
      await emit('notificationSettings.pendingManagement', {
        'schemaVersion': 1,
        'count': 3,
      });
      await emit('account.changed', {'schemaVersion': 1}, generation: 2);
      expect(inbox.pendingManagement.value, 0);
      await emit('notificationSettings.pendingManagement', {
        'schemaVersion': 1,
        'count': 10,
      });
      expect(inbox.pendingManagement.value, 0);
      inbox.dispose();
      await session.close();
      await pair.host.close();
    },
  );
}
