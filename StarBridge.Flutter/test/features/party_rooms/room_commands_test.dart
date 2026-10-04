import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';

import 'party_rooms_test.dart' show TestRoomsPort, ready, wire, room;

void main() {
  test(
    'successful room recovery clears the stale accepted-read warning',
    () async {
      final port = CommandPort();
      final module = PartyRoomsModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      final request = module.execute(
        RoomCommand(RoomOperation.create, {'title': 'Fixture room'}),
      );
      port.pendingCommand.complete(
        const RoomCommandResult('joined', error: 'refreshRequired'),
      );
      await request;
      expect(module.commandMessage, 'refreshRequired');
      expect(module.canCommand, isFalse);
      port.result = ready(wire(current: 'a', rooms: [room('a')]));
      await module.refresh();
      expect(module.directory!.currentRoomId, 'a');
      expect(module.commandNeedsRefresh, isFalse);
      expect(
        module.commandMessage,
        isNull,
        reason: 'Confirmed membership must not retain a failed-read warning.',
      );
      expect(port.calls, 1, reason: 'Recovery must not repeat creation.');
    },
  );
  test(
    'invalid or failed recovery cannot clear an unresolved room operation',
    () async {
      final port = CommandPort();
      final module = PartyRoomsModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      final request = module.execute(
        RoomCommand(RoomOperation.create, {'title': 'Fixture room'}),
      );
      port.pendingCommand.complete(
        const RoomCommandResult('joined', error: 'refreshRequired'),
      );
      await request;
      for (final result in const [
        RoomReadResult(RoomReadState.unavailable),
        RoomReadResult(RoomReadState.ready),
      ]) {
        port.result = result;
        await module.refresh();
        expect(module.commandNeedsRefresh, isTrue);
        expect(module.commandMessage, 'refreshRequired');
        expect(module.canCommand, isFalse);
      }
      expect(port.calls, 1);
    },
  );
  test('authoritative pending application removal clears feedback, missing field does not', () async {
    final port = CommandPort();
    final module = PartyRoomsModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    final request = module.execute(
      RoomCommand(RoomOperation.join, {'roomId': 'a', 'password': ''}),
    );
    port.pendingCommand.complete(
      RoomCommandResult(
        'pending',
        directory: ready(wire()..['viewerPendingRoomIds'] = ['a']).directory,
      ),
    );
    await request;
    expect(module.commandMessage, 'pending');
    // Legacy/unknown and transient failures are not evidence of rejection.
    port.result = ready(wire());
    await module.refresh();
    expect(module.commandMessage, 'pending');
    port.result = const RoomReadResult(RoomReadState.unavailable);
    await module.refresh();
    expect(module.commandMessage, 'pending');
    port.result = ready(wire()..['viewerPendingRoomIds'] = <String>[]);
    await module.refresh();
    expect(module.commandMessage, isNull);
  });
  test(
    'pending application stays in discovery and suppresses duplicate clicks',
    () async {
      final port = CommandPort();
      final module = PartyRoomsModule(port);
      await module.refresh();
      final command = RoomCommand(RoomOperation.join, {
        'roomId': 'a',
        'password': '',
      });
      final request = module.execute(command);
      expect(module.busy, isTrue);
      expect((await module.execute(command)).accepted, isFalse);
      expect(port.calls, 1);
      port.pendingCommand.complete(
        RoomCommandResult('pending', directory: ready(wire()).directory),
      );
      await request;
      expect(module.directory!.currentRoomId, isNull);
      expect(module.commandMessage, 'pending');
      module.dispose();
    },
  );
  test(
    'pending feedback clears when a later authoritative read shows membership',
    () async {
      final port = CommandPort();
      final module = PartyRoomsModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      final request = module.execute(
        RoomCommand(RoomOperation.join, {'roomId': 'a', 'password': ''}),
      );
      port.pendingCommand.complete(
        RoomCommandResult('pending', directory: ready(wire()).directory),
      );
      await request;
      expect(module.commandMessage, 'pending');
      port.result = ready(wire(current: 'a', rooms: [room('a')]));
      await module.refresh();
      expect(module.directory!.currentRoomId, 'a');
      expect(module.commandMessage, isNull);
    },
  );
  test('unknown outcome requires refresh before a new command', () async {
    final port = CommandPort();
    final module = PartyRoomsModule(port);
    await module.refresh();
    final request = module.execute(
      RoomCommand(RoomOperation.leave, {'roomId': 'a'}),
    );
    port.pendingCommand.complete(
      const RoomCommandResult('unknown', error: 'outcomeUnknown'),
    );
    await request;
    expect(module.canCommand, isFalse);
    expect(module.directory, isNull);
    await module.refresh();
    expect(module.canCommand, isTrue);
    module.dispose();
  });
  test(
    'account invalidation rejects a late command and an old dialog',
    () async {
      final port = CommandPort();
      final module = PartyRoomsModule(port);
      await module.refresh();
      final revision = module.contextRevision;
      final command = RoomCommand(RoomOperation.join, {
        'roomId': 'a',
        'password': '',
      });
      final request = module.execute(command, expectedRevision: revision);
      port.events.add(null);
      await Future<void>.delayed(Duration.zero);
      port.pendingCommand.complete(
        RoomCommandResult(
          'joined',
          directory: ready(wire(current: 'a', rooms: [room('a')])).directory,
        ),
      );
      expect((await request).status, 'stale');
      expect(module.directory, isNull);
      await module.refresh();
      expect(
        (await module.execute(command, expectedRevision: revision)).status,
        'stale',
      );
      expect(port.calls, 1);
      module.dispose();
    },
  );
  test(
    'accepted write with failed read is not presented as saved membership',
    () async {
      final port = CommandPort();
      final module = PartyRoomsModule(port);
      await module.refresh();
      final request = module.execute(
        RoomCommand(RoomOperation.join, {'roomId': 'a', 'password': ''}),
      );
      port.pendingCommand.complete(
        const RoomCommandResult('joined', error: 'refreshRequired'),
      );
      await request;
      expect(module.commandNeedsRefresh, isTrue);
      expect(module.directory, isNull);
      expect(module.commandMessage, 'refreshRequired');
      module.dispose();
    },
  );
}

class CommandPort extends TestRoomsPort implements RoomCommandsPort {
  int calls = 0;
  final pendingCommand = Completer<RoomCommandResult>();
  @override
  bool get supportsCommands => true;
  @override
  Future<RoomCommandResult> execute(RoomCommand command) {
    calls++;
    return pendingCommand.future;
  }
}
