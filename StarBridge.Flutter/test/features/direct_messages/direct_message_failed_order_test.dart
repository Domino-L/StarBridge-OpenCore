import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_message_history_list.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_message_send_queue.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_contract.dart';

// 2026-11-19 (F acceptance after B7): a failed bubble dropped below a later
// message that did go out. Failed messages now stay at the time they were
// written; messages still sending stay at the bottom.

final _row = Conversation(
  'ref-a',
  'Pilot',
  '',
  DateTime.utc(2026, 11, 19),
  0,
  'friend',
  conversationKey: 'key-a',
);

DirectMessage _history(
  int sequence,
  String id,
  DateTime time, {
  bool incoming = false,
}) => DirectMessage(sequence, id, incoming, 'text $id', time, null);

final class _PendingSender implements DirectMessageSender {
  final _never = Completer<DirectSendResult>();
  @override
  bool get supportsSending => true;
  @override
  Future<DirectSendResult> send(
    String ref,
    String text,
    String clientMessageId,
  ) => _never.future;
}

DirectMessageSendQueue _queue(
  DateTime Function() now, {
  DirectMessageSender? sender,
}) => DirectMessageSendQueue(
  sender: () => sender,
  changed: () {},
  onResult: (_, _) {},
  now: now,
);

void main() {
  test(
    'a failed message stays at its own time when a later message goes out',
    () async {
      var clock = DateTime.utc(2026, 11, 19, 10);
      final queue = _queue(() => clock);
      final failed = queue.enqueue(_row, 'first try');
      await Future<void>.delayed(Duration.zero);
      expect(failed.state, DirectOutgoingState.failed);

      final history = [
        _history(1, 'old', DateTime.utc(2026, 11, 19, 9), incoming: true),
        _history(2, 'later-own', DateTime.utc(2026, 11, 19, 10, 5)),
      ];
      final (:timeline, :pinned) = directMessageTimeline(
        history,
        queue.forConversation(_row),
      );
      expect(pinned, isEmpty);
      expect(
        timeline,
        [history[0], failed, history[1]],
        reason: 'the failed bubble sits between the older message and the later delivered one',
      );
      queue.dispose();
    },
  );

  test('a failed message with nothing after it is the newest item', () async {
    final queue = _queue(() => DateTime.utc(2026, 11, 19, 10));
    final failed = queue.enqueue(_row, 'only try');
    await Future<void>.delayed(Duration.zero);
    final history = [
      _history(1, 'old', DateTime.utc(2026, 11, 19, 9), incoming: true),
    ];
    final (:timeline, :pinned) = directMessageTimeline(
      history,
      queue.forConversation(_row),
    );
    expect(pinned, isEmpty);
    expect(timeline, [history[0], failed]);
    queue.dispose();
  });

  test('a message still sending stays at the bottom, below history and failed ones', () async {
    var clock = DateTime.utc(2026, 11, 19, 10);
    final failingQueue = _queue(() => clock);
    final failed = failingQueue.enqueue(_row, 'failed');
    await Future<void>.delayed(Duration.zero);

    clock = DateTime.utc(
      2026,
      11,
      19,
      9,
    ); // even an earlier local clock keeps sending at the bottom
    final sendingQueue = _queue(() => clock, sender: _PendingSender());
    final sending = sendingQueue.enqueue(_row, 'sending');
    await Future<void>.delayed(Duration.zero);
    expect(sending.state, DirectOutgoingState.sending);

    final history = [_history(1, 'later', DateTime.utc(2026, 11, 19, 11))];
    final (:timeline, :pinned) = directMessageTimeline(history, [
      ...failingQueue.forConversation(_row),
      ...sendingQueue.forConversation(_row),
    ]);
    expect(pinned, [sending]);
    expect(timeline, [failed, history[0]]);
    failingQueue.dispose();
    sendingQueue.dispose();
  });

  test('several failed messages keep their order and equal times keep history first', () async {
    final at = DateTime.utc(2026, 11, 19, 10);
    final queue = _queue(() => at);
    final a = queue.enqueue(_row, 'a');
    final b = queue.enqueue(_row, 'b');
    await Future<void>.delayed(Duration.zero);
    final history = [_history(1, 'same-time', at)];
    final (:timeline, :pinned) = directMessageTimeline(
      history,
      queue.forConversation(_row),
    );
    expect(pinned, isEmpty);
    expect(timeline, [history[0], a, b]);
    queue.dispose();
  });
}
