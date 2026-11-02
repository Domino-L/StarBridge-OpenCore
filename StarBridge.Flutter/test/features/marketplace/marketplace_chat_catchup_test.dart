import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_chat_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_chat_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_chat_view.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

class CatchUpPort implements MarketplaceChatPort {
  final pushes = StreamController<MarketRow>.broadcast(sync: true);
  final calls = <(String, MarketRow)>[];
  final messages = <MarketRow>[];
  Completer<MarketRow>? historyGate, listGate;
  String? failure;
  @override
  bool get chatSupported => true;
  @override
  Stream<MarketRow> get chatPushes => pushes.stream;

  void addThrough(int last) {
    for (var id = messages.length + 1; id <= last; id++) {
      messages.add({
        'id': id,
        'content': 'm$id',
        'mine': false,
        'time': DateTime.utc(
          2026,
          1,
          1,
        ).add(Duration(seconds: id)).toIso8601String(),
      });
    }
  }

  @override
  Future<MarketRow> chat(String op, [MarketRow input = const {}]) async {
    calls.add((op, input));
    if (failure != null) throw MarketplaceTradeError(failure!);
    if (op == 'conversations') {
      return listGate?.future ??
          Future.value({
            'rows': [
              {'ref': 'p1', 'name': 'Fixture', 'unread': 0},
            ],
          });
    }
    if (op == 'history') {
      if (historyGate != null) return historyGate!.future;
      return page(input['before'] as int?);
    }
    if (op == 'unread') return {'count': 0};
    return {};
  }

  MarketRow page([int? before]) => {
    'rows': messages.reversed
        .where((m) => before == null || (m['id'] as int) < before)
        .take(20)
        .toList(),
  };
  int count(String op) => calls.where((c) => c.$1 == op).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'epoch milliseconds and ISO timestamps share one chronological order',
    () async {
      final p = CatchUpPort();
      final c = MarketplaceChatController(p);
      addTearDown(c.dispose);
      addTearDown(p.pushes.close);
      p.messages.addAll([
        {
          'id': 1,
          'time': DateTime.utc(2026, 1, 1, 0, 0, 20).millisecondsSinceEpoch,
        },
        {'id': 2, 'time': DateTime.utc(2026, 1, 1, 0, 0, 10).toIso8601String()},
      ]);
      await c.loadConversations();
      await c.open('p1');
      p.pushes.add({
        'kind': 'message',
        'ref': 'p1',
        'message': {
          'id': 3,
          'time': DateTime.utc(2026, 1, 1, 0, 0, 15).toIso8601String(),
        },
      });
      expect(c.thread.map((m) => m['id']), [2, 3, 1]);
    },
  );
  for (final missed in [0, 5, 45, 225]) {
    test(
      'resync catches up $missed missed messages with bounded cursor pages',
      () async {
        final p = CatchUpPort()..addThrough(25);
        final c = MarketplaceChatController(p);
        addTearDown(c.dispose);
        addTearDown(p.pushes.close);
        await c.loadConversations();
        await c.open('p1');
        final before = p.count('history');
        p.addThrough(25 + missed);
        p.pushes.add({'kind': 'resync'});
        await pumpEventQueue();
        expect(
          p.count('history') - before,
          missed == 225
              ? 10
              : missed == 45
              ? 3
              : 1,
        );
        expect(c.thread.map((m) => m['id']).toSet().length, c.thread.length);
        expect(c.hasGap, missed == 225);
        if (missed == 225) {
          expect(c.threadEnd, isFalse);
          expect(c.gapStartId, 51);
          await c.loadOlder();
          expect(c.hasGap, isTrue);
          await c.loadOlder();
          expect(c.hasGap, isFalse);
        }
        expect(c.thread.map((m) => m['id']).toList(), [
          for (var id = 6; id <= 25 + missed; id++) id,
        ]);
      },
    );
  }

  test(
    'closed thread reads no history on resync, catches up on reopen',
    () async {
      final p = CatchUpPort()..addThrough(25);
      final c = MarketplaceChatController(p);
      addTearDown(c.dispose);
      addTearDown(p.pushes.close);
      await c.open('p1');
      await c.close();
      p.addThrough(70);
      p.pushes.add({'kind': 'resync'});
      await pumpEventQueue();
      expect(p.count('history'), 1);
      await c.open('p1');
      expect(c.thread.map((m) => m['id']), [
        for (var id = 11; id <= 70; id++) id,
      ]);
      expect(c.hasGap, isFalse);
    },
  );

  test('push during directory and history reads keeps original anchor, order and dedup', () async {
    final p = CatchUpPort()..addThrough(25);
    final c = MarketplaceChatController(p);
    addTearDown(c.dispose);
    addTearDown(p.pushes.close);
    await c.open('p1');
    p.addThrough(70);
    p.listGate = Completer();
    p.pushes.add({'kind': 'resync'});
    p.pushes.add({'kind': 'message', 'ref': 'p1', 'message': p.messages.last});
    final newest = p.page();
    p.historyGate = Completer();
    p.listGate!.complete({
      'rows': [
        {'ref': 'p1', 'name': 'Fixture'},
      ],
    });
    await pumpEventQueue();
    p.addThrough(71);
    p.pushes.add({'kind': 'message', 'ref': 'p1', 'message': p.messages.last});
    final gate = p.historyGate!;
    p.historyGate = null;
    gate.complete(newest);
    await pumpEventQueue();
    expect(c.thread.map((m) => m['id']), [for (var id = 6; id <= 71; id++) id]);
    expect(c.hasGap, isFalse);
  });

  testWidgets(
    'directory/unread reconcile only while visible and foreground; 403 stops',
    (tester) async {
      final p = CatchUpPort();
      final c = MarketplaceChatController(p);
      addTearDown(c.dispose);
      addTearDown(p.pushes.close);
      await tester.pump(const Duration(minutes: 4));
      expect(p.calls, isEmpty);
      c.setVisible(true);
      await tester.pump(const Duration(seconds: 120));
      expect(p.count('conversations'), 1);
      expect(p.count('unread'), 1);
      expect(p.count('history'), 0);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 4));
      expect(p.count('conversations'), 1);
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(p.count('conversations'), 2);
      p.failure = 'marketplace.forbidden';
      await tester.pump(const Duration(seconds: 120));
      expect(p.count('conversations'), 3);
      p.pushes.add({'kind': 'resync'});
      await tester.pump(const Duration(minutes: 8));
      expect(p.count('conversations'), 3);
      c.setVisible(false);
    },
  );

  test('resync queued behind an older-page load preserves the pre-disconnect anchor', () async {
    final p = CatchUpPort()..addThrough(25);
    final c = MarketplaceChatController(p);
    addTearDown(c.dispose);
    addTearDown(p.pushes.close);
    await c.open('p1');
    final oldPage = p.page(6);
    p.historyGate = Completer();
    final older = c.loadOlder();
    p.addThrough(70);
    p.pushes.add({'kind': 'resync'});
    await pumpEventQueue();
    p.addThrough(71);
    p.pushes.add({'kind': 'message', 'ref': 'p1', 'message': p.messages.last});
    final gate = p.historyGate!;
    p.historyGate = null;
    gate.complete(oldPage);
    await older;
    await pumpEventQueue();
    expect(c.thread.map((m) => m['id']), [for (var id = 1; id <= 71; id++) id]);
    expect(c.hasGap, isFalse);
  });

  testWidgets(
    'gap separator has three locales and loading continues from gap cursor',
    (tester) async {
      size(tester, const Size(1200, 800));
      final p = CatchUpPort()..addThrough(25);
      final c = MarketplaceChatController(p);
      addTearDown(c.dispose);
      addTearDown(p.pushes.close);
      await tester.pumpWidget(
        scopedApp(
          Scaffold(
            body: MarketplaceTradeChatView(c, header: const Text('Chat')),
          ),
          InteractionSuite.scan,
        ),
      );
      await tester.pump();
      await c.open('p1');
      p.addThrough(250);
      p.pushes.add({'kind': 'resync'});
      await tester.pump();
      await tester.pump();
      expect(c.hasGap, isTrue);
      await tester.scrollUntilVisible(
        find.byKey(const Key('trade-chat-history-gap')),
        -400,
        maxScrolls: 100,
        scrollable: find
            .descendant(
              of: find.byWidgetPredicate(
                (w) => w is ListView && w.controller != null,
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const Key('trade-chat-history-gap')), findsOneWidget);
      expect(chatCopy['更早的消息尚未同步，请向上滚动加载。'], hasLength(3));
      final before = p.count('history');
      await tester.ensureVisible(find.byKey(const Key('trade-chat-gap-load')));
      await tester.tap(find.byKey(const Key('trade-chat-gap-load')));
      await tester.pump();
      expect(p.count('history'), before + 1);
      expect(p.calls.where((x) => x.$1 == 'history').last.$2['before'], 51);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
