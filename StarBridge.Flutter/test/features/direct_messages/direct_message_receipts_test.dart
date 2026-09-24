import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';

class Receipts implements DirectMessagesPort, DirectReadReceiptPort {
  final example = ExampleDirectMessages();
  final events = StreamController<void>.broadcast();
  final calls = <int>[];
  Completer<DirectReadReceipt>? pending;
  bool fail = false;
  @override
  bool get supportsReadReceipts => true;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<List<Conversation>> directory() => example.directory();
  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) =>
      example.history(ref, before: before, after: after);
  @override
  Future<DirectReadReceipt> markRead(String ref, int through) {
    calls.add(through);
    if (fail) throw const DirectReadFailure('unavailable');
    return pending?.future ?? example.markRead(ref, through);
  }

  @override
  void cancel() {}
  @override
  Future<void> close() => events.close();
}

void main() {
  test(
    'loading alone does not mark read; visible cursor preserves newer unread',
    () async {
      final port = Receipts();
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      await module.open(module.rows.first);
      expect(port.calls, isEmpty);
      await module.markVisibleRead(999);
      await module.markVisibleRead(
        60,
      ); // Own message cannot mark incoming read.
      expect(port.calls, isEmpty);
      await module.markVisibleRead(57);
      expect(module.rows.first.unread, 1);
      await module.markVisibleRead(57);
      expect(port.calls, [57]);
      await module.markVisibleRead(59);
      expect(module.rows.first.unread, 0);
      expect(module.rows.last.unread, 1);
      await module.refresh();
      expect(module.rows.first.unread, 0);
    },
  );
  test(
    'failed receipt retains unread and retries only after explicit refresh',
    () async {
      final port = Receipts()..fail = true;
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      await module.open(module.rows.first);
      await module.markVisibleRead(59);
      expect(module.rows.first.unread, 2);
      expect(module.readError, 'unavailable');
      await module.markVisibleRead(59);
      expect(port.calls, [59]);
      port.fail = false;
      await module.load();
      await module.markVisibleRead(59);
      expect(module.rows.first.unread, 0);
      expect(module.readError, isNull);
    },
  );
  test('late acknowledgement cannot overwrite a refreshed directory', () async {
    final port = Receipts()..pending = Completer<DirectReadReceipt>();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await module.open(module.rows.first);
    final mark = module.markVisibleRead(59);
    await module.refresh();
    port.pending!.complete(const DirectReadReceipt(59, 0));
    await mark;
    expect(module.rows.first.unread, 2);
    expect(module.selected, isNull);
  });
}
