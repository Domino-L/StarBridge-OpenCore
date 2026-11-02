import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

import 'direct_message_receipts_test.dart' show Receipts;

// DL-139 (2026-10-21, user report after the r12b/B02E restarts): the DM window
// showed "read status could not sync" while the conversation had no unread
// message. Every open revalidates the visible cursor with a receipt; one that
// failed during the relay restart kept the warning until a manual refresh.
void main() {
  test('a failed revalidation of a conversation without unread shows no read warning', () async {
    final port = Receipts();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await module.open(module.rows.first);
    await module.markVisibleRead(59);
    expect(module.rows.first.unread, 0);
    module.back();
    await module.open(module.rows.first);
    port.fail = true;
    await module.markVisibleRead(59);
    expect(port.calls, [
      59,
      59,
    ], reason: 'Reopening still revalidates the cursor.');
    expect(
      module.readError,
      isNull,
      reason: 'Nothing is unread, so a failed receipt is not a sync problem for the user.',
    );
  });

  test(
    'a read warning clears once the directory confirms nothing is unread',
    () async {
      final port = Receipts()..fail = true;
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      await module.open(module.rows.first);
      await module.markVisibleRead(59);
      expect(module.readError, 'unavailable');
      expect(module.selected?.unread, 2);
      // The relay applied the read anyway (or another device read it).
      await port.example.markRead(module.selected!.ref, 59);
      await module.receive(directoryOnly: true);
      expect(module.selected?.unread, 0);
      expect(
        module.readError,
        isNull,
        reason: 'The warning stayed after the directory showed no unread.',
      );
    },
  );

  test('a failed receipt with unread messages still warns', () async {
    final port = Receipts()..fail = true;
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await module.open(module.rows.first);
    await module.markVisibleRead(59);
    await module.receive(directoryOnly: true);
    expect(module.selected?.unread, 2);
    expect(module.readError, 'unavailable');
  });
}
