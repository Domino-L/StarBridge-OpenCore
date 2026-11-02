import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_message_receive_polling.dart';

class CatchupPort implements DirectMessagesPort, DirectReadReceiptPort {
  final time = DateTime.utc(2026, 10, 28);
  late final peer = Conversation('peer', 'Peer', '', time, 2000, 'friend');
  final afters = <int>[];
  final befores = <int>[];
  final receipts = <int>[];
  int latest = 1;
  int? failAfter;
  String? olderFailure;
  bool stuck = false, overlap = false;
  Future<void> Function(int)? duringRead;
  @override
  bool get supportsReadReceipts => true;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<List<Conversation>> directory() async => [peer];
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    afters.add(after);
    if (before > 0) {
      befores.add(before);
      if (olderFailure != null) throw DirectReadFailure(olderFailure!);
      final start = (before - 50).clamp(1, latest);
      return DirectPage(ref, [
        for (var i = start; i < before; i++)
          DirectMessage(i, 'message-$i', true, 'fixture', time, null),
      ], start, latest, start > 1, 'friend', canSend: true);
    }
    await duringRead?.call(after);
    if (after == failAfter) throw const DirectReadFailure('unavailable');
    final end = after == 0 ? 1 : (after + 50).clamp(0, latest);
    final start = overlap ? after : after + 1;
    final rows = stuck
        ? <DirectMessage>[]
        : [
            for (var i = start; i <= end; i++)
              DirectMessage(i, 'message-$i', true, 'fixture', time, null),
          ];
    return DirectPage(
      ref,
      rows,
      rows.firstOrNull?.sequence ?? 0,
      latest,
      false,
      'friend',
      canSend: true,
    );
  }

  @override
  Future<DirectReadReceipt> markRead(String ref, int through) async {
    receipts.add(through);
    return DirectReadReceipt(through, 0);
  }

  @override
  void cancel() {}
  @override
  Future<void> close() async {}
}

void main() {
  Future<DirectMessagesModule> open(CatchupPort port) async {
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.openFriend(port.peer);
    return module;
  }

  test(
    'one receive reads every after page before offering a read receipt',
    () async {
      final port = CatchupPort();
      final module = await open(port);
      module.editDraft('keep draft');
      port.latest = 126;
      port.duringRead = (_) async => module.markVisibleRead(1);
      await module.receive();
      expect(port.afters, [0, 1, 51, 101]);
      expect(port.receipts, isEmpty);
      expect(module.messages.length, 126);
      expect(module.hasNewer, isFalse);
      expect(module.draft, 'keep draft');
      await module.markVisibleRead(126);
      expect(port.receipts, [126]);
      await module.receive();
      expect(module.messages.length, 126);
    },
  );

  test('older paging errors keep the displayed window and draft', () async {
    final port = CatchupPort();
    final module = await open(port);
    port.latest = 1201;
    for (var i = 0; i < 3; i++) { await module.receive(); }
    module.editDraft('keep');
    final retained = module.messages;
    for (final failure in ['target_changed', 'data_invalid', 'unavailable', 'limit']) {
      port.olderFailure = failure;
      await module.load(older: true);
      expect(module.messages, retained);
      expect(module.draft, 'keep');
      expect(module.hasOlder, isTrue);
    }
  });

  test(
    'ten page cap leaves backlog for next receive and rolls retained history',
    () async {
      final port = CatchupPort();
      final module = await open(port);
      port.latest = 1201;
      await module.receive();
      expect(port.afters.length, 11);
      expect(module.messages.last.sequence, 501);
      expect(module.hasNewer, isTrue);
      await module.markVisibleRead(501);
      expect(port.receipts, isEmpty);
      await module.receive();
      await module.receive();
      expect(module.messages.last.sequence, 1201);
      expect(module.messages.length, 1000);
      expect(module.hasOlder, isTrue);
      expect(module.hasNewer, isFalse);
      await module.load(older: true);
      expect(module.messages.map((m) => m.sequence), List.generate(1000, (i) => i + 152));
      await module.load(older: true);
      expect(port.befores, [202, 152]);
      expect(module.messages.map((m) => m.sequence), List.generate(1000, (i) => i + 102));
      expect(module.messages.map((m) => m.id).toSet().length, 1000);
      expect(module.hasNewer, isTrue);
      // Returning towards the live tail must also work after trimming its end.
      await module.receive();
      expect(module.messages.last.sequence, 1201);
      expect(module.messages.length, 1000);
    },
  );

  test('failed page resumes from last committed sequence', () async {
    final port = CatchupPort();
    final module = await open(port);
    port.latest = 126;
    port.failAfter = 51;
    expect(await module.receive(), DirectMessageReceiveResult.failed);
    expect(module.messages.last.sequence, 51);
    expect(module.hasNewer, isTrue);
    port.failAfter = null;
    await module.receive();
    expect(port.afters, [0, 1, 51, 51, 101]);
    expect(module.messages.last.sequence, 126);
  });

  test(
    'stalled or overlapping page stops safely without losing history',
    () async {
      for (final overlap in [false, true]) {
        final port = CatchupPort();
        final module = await open(port);
        port.latest = 126;
        port.overlap = overlap;
        port.stuck = !overlap;
        expect(await module.receive(), DirectMessageReceiveResult.failed);
        expect(port.afters, [0, 1]);
        expect(module.messages.single.sequence, 1);
        expect(module.historySyncError, 'data_invalid');
      }
    },
  );

  testWidgets(
    'a moving latest still obeys the page cap without acknowledging backlog',
    (tester) async {
      final port = CatchupPort();
      final module = await open(port);
      port.latest = 126;
      port.duringRead = (_) async {
        port.latest += 50;
      };
      await module.receive();
      expect(port.afters.length, 11);
      expect(module.messages.last.sequence, 501);
      expect(module.hasNewer, isTrue);
      await module.markVisibleRead(501);
      expect(port.receipts, isEmpty);
      port.duringRead = null;
      await module.receive();
      expect(module.messages.last.sequence, 626);
    },
  );

  test(
    'switching conversation during catch-up retires the old pages',
    () async {
      final port = CatchupPort();
      final module = await open(port);
      port.latest = 126;
      port.duringRead = (after) async {
        if (after == 51) module.back();
      };
      expect(await module.receive(), DirectMessageReceiveResult.invalidated);
      expect(port.afters, [0, 1, 51]);
      expect(module.selected, isNull);
      expect(module.messages, isEmpty);
      expect(port.receipts, isEmpty);
    },
  );

  testWidgets(
    'healthy push checks once per minute; losing push restores fallback',
    (tester) async {
      var reads = 0, healthy = true;
      final polling = DirectMessageReceivePolling(
        read: () async {
          reads++;
          return DirectMessageReceiveResult.unchanged;
        },
        isHealthy: () => healthy,
      );
      final lease = polling.observe(() => true);
      Future<void> seconds(int n) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
        }
      }

      await seconds(60);
      expect(reads, 1);
      await seconds(1);
      expect(reads, 2);
      healthy = false;
      await seconds(1);
      expect(reads, 3);
      await seconds(2);
      expect(reads, 4);
      lease.dispose();
      polling.dispose();
    },
  );
}
