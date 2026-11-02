// 0.7.2 G9 data layer: live pushes merge at once ("无延迟同步", 2026-10-21).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_chat_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

class _Port implements MarketplaceChatPort {
  final calls = <(String, MarketRow)>[];
  final pushes = StreamController<MarketRow>.broadcast(sync: true);
  var unread = 2;
  var sendStatus = 'sent';
  Completer<MarketRow>? sendGate;
  final messages = <MarketRow>[
    for (var id = 1; id <= 25; id++)
      {'id': id, 'content': 'm$id', 'mine': id.isEven},
  ];
  @override
  bool get chatSupported => true;
  @override
  Stream<MarketRow> get chatPushes => pushes.stream;
  @override
  Future<MarketRow> chat(String operation, [MarketRow input = const {}]) async {
    calls.add((operation, input));
    switch (operation) {
      case 'conversations':
        return {
          'rows': [
            {'ref': 'p1', 'name': 'Trader_Long_Handle_9000', 'unread': unread},
            {'ref': 'p2', 'name': 'Other', 'unread': 0},
          ],
        };
      case 'history':
        final before = input['before'] as int? ?? 1 << 30;
        final page = messages
            .where((m) => (m['id'] as int) < before)
            .toList()
            .reversed
            .take(20)
            .toList();
        return {'rows': page};
      case 'read':
        unread = 0;
        return {'confirmed': true};
      case 'send':
        if (sendGate case final gate?) return gate.future;
        if (sendStatus != 'sent') {
          return {
            'status': sendStatus,
            'reason': sendStatus == 'rejected' ? '对方已将你拉黑' : null,
          };
        }
        final message = {
          'id': messages.length + 1,
          'content': input['content'],
          'mine': true,
        };
        messages.add(message);
        return {'status': 'sent', 'message': message};
      default:
        return {};
    }
  }
}

int _count(_Port port, String operation) =>
    port.calls.where((x) => x.$1 == operation).length;

void main() {
  test(
    'open reads newest, marks read, pages older; sends never repeat',
    () async {
      final port = _Port();
      final c = MarketplaceChatController(port);
      addTearDown(c.dispose);

      await c.loadConversations();
      expect(c.unread, 2);
      await c.open('p1');
      expect(c.thread.first['id'], 6, reason: 'newest 20, oldest first');
      expect(c.thread.last['id'], 25);
      expect(_count(port, 'read'), 1);
      await pumpEventQueue();
      expect(c.unread, 0);
      expect(
        port.calls.any((x) => x.$1 == 'focus' && x.$2['ref'] == 'p1'),
        isTrue,
      );

      await c.loadOlder();
      expect(c.thread.first['id'], 1);
      expect(c.threadEnd, isTrue);

      final histories = _count(port, 'history');
      await c.send('  成交  ', orderId: 88);
      expect(port.calls.where((x) => x.$1 == 'send').single.$2, {
        'ref': 'p1',
        'content': '成交',
        'orderId': 88,
        'clientMessageId': matches(RegExp(r'^[0-9a-f]{32}$')),
      });
      expect(c.outgoing, isEmpty);
      expect(c.thread.last['content'], '成交', reason: 'shown from the reply');
      expect(
        _count(port, 'history'),
        histories,
        reason: 'no round trip to show it',
      );

      port.sendStatus = 'uncertain';
      await c.send('在吗');
      expect(c.outgoing.single.status, 'uncertain');
      expect(_count(port, 'send'), 2, reason: 'never resent');
      port.sendStatus = 'rejected';
      await c.send('再问');
      expect(c.outgoing.last.reason, '对方已将你拉黑');

      // A manual resend is the same message to SCM: same clientMessageId.
      final ids = [
        for (final x in port.calls.where((x) => x.$1 == 'send'))
          x.$2['clientMessageId'],
      ];
      expect(ids.toSet(), hasLength(3), reason: 'each new message, a new id');
      port.sendStatus = 'sent';
      final again = c.outgoing.last;
      await c.resend(again);
      expect(port.calls.last.$2['clientMessageId'], again.clientMessageId);
      expect(port.calls.last.$2['clientMessageId'], ids.last);
      expect(c.outgoing, isNot(contains(again)));
      expect(c.outgoing.single.status, 'uncertain');
    },
  );

  test('pushes show at once, without any read', () async {
    final port = _Port();
    final c = MarketplaceChatController(port);
    addTearDown(c.dispose);
    await c.loadConversations();
    await c.open('p1');
    await pumpEventQueue();
    final before = port.calls.length;

    // Incoming in the open thread: appended, not counted unread.
    port.pushes.add({
      'kind': 'message',
      'ref': 'p1',
      'name': 'Trader_Long_Handle_9000',
      'message': {'id': 40, 'content': '到了', 'mine': false, 'time': 9},
    });
    expect(c.thread.last['content'], '到了');
    expect(c.conversations.first['lastMessage'], '到了');
    expect(c.conversations.first['unread'], 0);

    // Incoming in another conversation: moves it to the top, unread + 1.
    port.pushes.add({
      'kind': 'message',
      'ref': 'p2',
      'message': {'id': 41, 'content': '还有货吗', 'mine': false},
    });
    expect(c.conversations.first['ref'], 'p2');
    expect(c.conversations.first['unread'], 1);
    expect(c.thread.last['id'], 40, reason: 'other thread untouched');

    // Own message from the SCM site: shown in the open thread as mine, once.
    for (var i = 0; i < 2; i++) {
      port.pushes.add({
        'kind': 'message',
        'ref': 'p1',
        'message': {'id': 42, 'content': '网站上发的', 'mine': true},
      });
    }
    expect(c.thread.where((m) => m['id'] == 42), hasLength(1));
    expect(c.thread.last['mine'], isTrue);

    port.pushes.add({'kind': 'unread', 'count': 7});
    expect(c.unread, 7, reason: 'SCM total wins');
    expect(port.calls.length, before, reason: 'nothing above needed a read');

    // A brand-new conversation shows at once (full row reconciles later).
    port.pushes.add({
      'kind': 'message',
      'ref': 'p9',
      'name': 'NewBuyer',
      'message': {'id': 43, 'content': '你好', 'mine': false},
    });
    expect(c.conversations.first['name'], 'NewBuyer');

    // After a reconnect anything may have been missed: read again.
    final reads = _count(port, 'conversations');
    port.pushes.add({'kind': 'resync'});
    await pumpEventQueue();
    expect(_count(port, 'conversations'), reads + 1);
    expect(
      c.thread.any((m) => m['id'] == 40),
      isTrue,
      reason: 'a newest-page read keeps messages pushed after it',
    );

    await c.close();
    expect(port.calls.last.$1, 'focus');
    expect(port.calls.last.$2, isEmpty);
    c.reset();
    expect(c.conversations, isEmpty);
    expect(c.unread, 0);
  });

  test('SCM spec 6.1-6.3: each event once, own echo, resync', () async {
    final port = _Port();
    final c = MarketplaceChatController(port);
    addTearDown(c.dispose);
    await c.loadConversations();
    await c.open('p1');
    await c.loadOlder();
    await pumpEventQueue();
    expect(c.thread.first['id'], 1);

    // The same event twice in a closed conversation counts once.
    for (var i = 0; i < 2; i++) {
      port.pushes.add({
        'kind': 'message',
        'ref': 'p2',
        'message': {'id': 41, 'content': '还有货吗', 'mine': false},
      });
    }
    expect(c.conversations.first['unread'], 1);
    // My own message from another session, or one SCM already marks read,
    // updates the preview only.
    port.pushes.add({
      'kind': 'message',
      'ref': 'p2',
      'message': {'id': 44, 'content': '有', 'mine': true},
    });
    port.pushes.add({
      'kind': 'message',
      'ref': 'p2',
      'message': {'id': 45, 'content': '好', 'mine': false, 'read': true},
    });
    expect(c.conversations.first['lastMessage'], '好');
    expect(c.conversations.first['unread'], 1);

    // Another session sending the same text does not confirm my pending one.
    final gate = port.sendGate = Completer<MarketRow>();
    final sending = c.send('成交');
    port.pushes.add({
      'kind': 'message',
      'ref': 'p1',
      'message': {'id': 50, 'content': '成交', 'mine': true},
    });
    expect(c.outgoing.single.status, 'sending');
    gate.complete({
      'status': 'sent',
      'message': {'id': 51, 'content': '成交', 'mine': true},
    });
    await sending;
    expect(c.outgoing, isEmpty);
    expect(c.thread.where((m) => m['content'] == '成交'), hasLength(2));

    // A reconnect reads the unread total too, and keeps older pages.
    final unreadReads = _count(port, 'unread');
    port.pushes.add({'kind': 'resync'});
    await pumpEventQueue();
    expect(_count(port, 'unread'), unreadReads + 1);
    expect(c.thread.first['id'], 1, reason: 'older pages stay');
    expect(c.thread.map((m) => m['id']).toSet(), hasLength(c.thread.length));

    // 150 UTF-16 code units, as SCM counts: 76 emoji are 152.
    port.sendGate = null;
    await c.send('😀' * 76);
    expect(_count(port, 'send'), 1);
  });
}
