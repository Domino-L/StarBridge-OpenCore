import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

// DL-06 / DL-138 (2026-10-21, "the messages window stalls on open"): switching
// back to a recently opened conversation cleared its history and draft and
// waited for a full page read. Recent history and drafts are now kept per
// stable conversation key within one account context, display only.

final _a = 'a' * 64, _b = 'b' * 64;

final class _Port implements DirectMessagesPort {
  final events = StreamController<void>.broadcast(sync: true);
  final pending = <String, Completer<DirectPage>>{};
  int generation = 1;
  @override
  Stream<void> get invalidations => events.stream;
  // Host references change on every directory read; the key stays.
  @override
  Future<List<Conversation>> directory() async => [
    for (final (name, key) in [('Alpha', _a), ('Beta', _b)])
      Conversation(
        '$name-$generation',
        name,
        'last $name',
        DateTime.utc(2026, 10, 21),
        0,
        'friend',
        conversationKey: key,
      ),
  ];
  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) =>
      (pending[ref] = Completer<DirectPage>()).future;
  void answer(String ref, String text) => pending
      .remove(ref)!
      .complete(
        DirectPage(
          ref,
          [
            DirectMessage(
              1,
              '$ref-1',
              true,
              text,
              DateTime.utc(2026, 10, 21),
              null,
            ),
          ],
          1,
          1,
          false,
          'friend',
          canSend: true,
        ),
      );
  @override
  void cancel() {}
  @override
  Future<void> close() => events.close();
}

Conversation _row(DirectMessagesModule module, String name) =>
    module.rows.singleWhere((row) => row.name == name);

void main() {
  test('switching back shows the last history and draft at once', () async {
    final port = _Port();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    final openA = module.open(_row(module, 'Alpha'));
    port.answer('Alpha-1', 'hello from alpha');
    await openA;
    module.editDraft('unsent to alpha');
    final openB = module.open(_row(module, 'Beta'));
    expect(module.draft, '', reason: 'a draft belongs to its conversation');
    port.answer('Beta-1', 'hello from beta');
    await openB;
    module.editDraft('unsent to beta');

    final backToA = module.open(_row(module, 'Alpha'));
    // Before the new page arrives: last history and draft, but no send.
    expect(module.messages.map((m) => m.text), ['hello from alpha']);
    expect(module.draft, 'unsent to alpha');
    expect(module.busy, isTrue);
    expect(module.canSend, isFalse);
    port.answer('Alpha-1', 'newest from alpha');
    await backToA;
    expect(module.messages.map((m) => m.text), ['newest from alpha']);
    expect(module.draft, 'unsent to alpha');
    expect(module.canSend, isTrue);

    module.back();
    final backToB = module.open(_row(module, 'Beta'));
    expect(module.draft, 'unsent to beta');
    expect(module.messages.map((m) => m.text), ['hello from beta']);
    port.answer('Beta-1', 'hello from beta');
    await backToB;
  });

  test('an account boundary forgets every conversation', () async {
    final port = _Port();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    final openA = module.open(_row(module, 'Alpha'));
    port.answer('Alpha-1', 'private to the old account');
    await openA;
    module.editDraft('old account draft');
    final openB = module.open(_row(module, 'Beta'));
    port.answer('Beta-1', 'beta');
    await openB;

    port.generation = 2;
    port.events.add(null);
    await pumpEventQueue();
    final reopen = module.open(_row(module, 'Alpha'));
    expect(module.messages, isEmpty);
    expect(module.draft, '');
    port.answer('Alpha-2', 'new account history');
    await reopen;
    expect(module.messages.map((m) => m.text), ['new account history']);
  });
}
