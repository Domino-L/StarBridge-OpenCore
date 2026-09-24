import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';

import 'party_rooms_test.dart' show TestRoomsPort, ready, wire;

void main() {
  test('room prefetch is reused on entry and only explicit refresh exposes progress', () async {
    final port = TestRoomsPort();
    final module = PartyRoomsModule(port);
    addTearDown(module.dispose);
    await module.refresh(reuseFresh: true);
    await module.refresh(reuseFresh: true);
    expect(port.reads, 1);
    port.pending = Completer<RoomReadResult>();
    final automatic = module.refresh();
    expect(module.manualRefreshing, false);
    port.pending!.complete(ready(wire()));
    await automatic;
    port.pending = Completer<RoomReadResult>();
    final manual = module.refresh(foreground: true);
    expect(module.manualRefreshing, true);
    port.pending!.complete(ready(wire()));
    await manual;
    expect(module.manualRefreshing, false);
  });
  test(
    'background room read does not block selecting an existing room',
    () async {
      final port = TestRoomsPort();
      final module = PartyRoomsModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      port.pending = Completer<RoomReadResult>();
      final reading = module.refresh();
      module.select('b');
      final selectedDuringRead = module.selectedRoomId;
      port.pending!.complete(ready(wire()));
      await reading;
      expect(selectedDuringRead, 'b');
      expect(module.selectedRoomId, 'b');
    },
  );

  testWidgets('ten warm room revisits reuse the shared session read', (
    tester,
  ) async {
    final port = TestRoomsPort()..result = ready(wire());
    final module = PartyRoomsModule(port)..startSession();
    addTearDown(module.dispose);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      module.enter();
      await tester.pump();
      module.leave();
    }
    expect(port.reads, 1);
    await module.refresh();
    expect(port.reads, 2, reason: 'manual refresh is never cached');
    module.stopSession();
    await tester.pump();
  });

  testWidgets(
    'expiry, invalidation, errors and notification actions read again',
    (tester) async {
      var now = DateTime.utc(2026, 1, 1);
      final port = TestRoomsPort()..result = ready(wire());
      final module = PartyRoomsModule(port, now: () => now)..startSession();
      addTearDown(module.dispose);
      await tester.pump();
      await module.refresh(reuseFresh: true);
      expect(port.reads, 1);
      now = now.add(const Duration(seconds: 8));
      await module.refresh(reuseFresh: true);
      expect(port.reads, 2);
      expect(await module.refreshForNotification(), isTrue);
      expect(port.reads, 3);
      port.events.add(null);
      await tester.pump();
      expect(port.reads, 4);
      port.result = const RoomReadResult(RoomReadState.unavailable);
      await module.refresh();
      await module.refresh(reuseFresh: true);
      expect(port.reads, 6);
      module.stopSession();
      port.result = ready(wire());
      await module.refresh(reuseFresh: true);
      expect(port.reads, 7);
    },
  );
}
