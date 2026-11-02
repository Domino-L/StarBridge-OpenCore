import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_read_schedule.dart';

import 'community_chat_controller_test.dart' show page;

final _target = 'a' * 32;

final class _Port
    implements
        CommunityChatPort,
        CommunityAuthorProjectionPort,
        CommunityChatAuthorRenewalPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final reads = <String>[];
  bool renewalOn = true;
  Object? renewalFailure;
  CommunityChatPage next = page([1, 2], latest: 2, unread: 5, older: false);
  CommunityChatPage renewalPage = page([], latest: 2, unread: 0, older: false);
  Completer<CommunityChatPage>? heldRenewal, heldFull;
  Object? fullFailure;
  @override
  bool get chatAvailable => true;
  @override
  bool get chatReadReceiptsAvailable => true;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async {
    reads.add('chat');
    return next;
  }

  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) => throw UnimplementedError();
  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) => throw UnimplementedError();
  @override
  bool get authorIdentitiesAvailable => true;
  @override
  Stream<void> get authorIdentityChanges => const Stream.empty();
  @override
  Future<CommunityChatPage> readChatAuthors(
    String targetRef, {
    int after = 0,
    int before = 0,
    List<String> observeMessageRefs = const [],
  }) async {
    reads.add('full');
    if (fullFailure != null) throw fullFailure!;
    return heldFull?.future ?? next;
  }

  @override
  bool get chatAuthorRenewalAvailable => renewalOn;
  @override
  Future<CommunityChatPage> renewChatAuthors(
    String targetRef, {
    int after = 0,
    List<String> observeMessageRefs = const [],
  }) async {
    reads.add('renew');
    if (renewalFailure != null) throw renewalFailure!;
    return heldRenewal?.future ?? renewalPage;
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('schedule', () {
    late List<String> reads;
    late DateTime now;
    var healthy = true, renewal = true, active = true, visible = true;
    var succeed = true;
    CommunityChatReadSchedule make() => CommunityChatReadSchedule(
      renewalPace: const Duration(seconds: 4),
      canRead: () => visible,
      pushHealthy: () => healthy,
      renewalAvailable: () => renewal,
      userActive: () => active,
      now: () => now,
      read: ({required renewal}) async {
        reads.add(renewal ? 'renew' : 'full');
        return (renewal: renewal, ok: succeed);
      },
    );
    Future<void> pass(WidgetTester tester, int seconds) async {
      for (var i = 0; i < seconds; i++) {
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
      }
    }

    setUp(() {
      reads = [];
      now = DateTime.utc(2026, 10, 30, 12);
      healthy = renewal = active = visible = succeed = true;
    });

    test('names are confirmed once a minute in the real client', () {
      expect(
        CommunityChatReadSchedule.renewalInterval,
        const Duration(seconds: 60),
      );
    });

    testWidgets('healthy push: renew every 4 s, full read every 30 s', (
      tester,
    ) async {
      final schedule = make();
      await pass(tester, 24);
      expect(reads, List.filled(6, 'renew'));
      await pass(tester, 8);
      expect(reads.where((read) => read == 'full'), hasLength(1));
      expect(reads.first, 'renew');
      schedule.dispose();
    });

    testWidgets('an unhealthy push keeps the old 3 s read, so nothing is later', (
      tester,
    ) async {
      healthy = false;
      final schedule = make();
      await pass(tester, 12);
      expect(reads, List.filled(4, 'full'));
      schedule.dispose();
    });

    testWidgets('the switch off: no renewal, only the slow reconciliation', (
      tester,
    ) async {
      renewal = false;
      final schedule = make();
      await pass(tester, 29);
      expect(reads, isEmpty);
      await pass(tester, 5);
      expect(reads, ['full']);
      schedule.dispose();
    });

    testWidgets('nobody active: a healthy push needs no reads', (tester) async {
      active = false;
      final schedule = make();
      await pass(tester, 120);
      expect(reads, isEmpty);
      active = true;
      schedule.poke();
      await pass(tester, 1);
      expect(reads, isNotEmpty, reason: 'Input brings it back at once.');
      schedule.dispose();
    });

    testWidgets('nobody active and no push: slower, not stopped', (
      tester,
    ) async {
      active = false;
      healthy = false;
      final schedule = make();
      await pass(tester, 45);
      expect(reads, List.filled(3, 'full'));
      schedule.dispose();
    });

    testWidgets('hidden or in the background reads nothing', (tester) async {
      visible = false;
      final schedule = make();
      await pass(tester, 60);
      expect(reads, isEmpty);
      schedule.dispose();
    });

    testWidgets('failures back off to a minute; success returns to the pace', (
      tester,
    ) async {
      succeed = false;
      final schedule = make();
      await pass(tester, 4);
      expect(reads, hasLength(1));
      await pass(tester, 7);
      expect(reads, hasLength(1), reason: 'Not again after 4 seconds.');
      await pass(tester, 1);
      expect(reads, hasLength(2));
      await pass(tester, 300);
      final capped = reads.length;
      await pass(tester, 240);
      // Four minutes at the cap, names and messages each about once a minute.
      expect(reads.length - capped, inInclusiveRange(3, 10));
      succeed = true;
      await pass(tester, 61);
      final recovered = reads.length;
      await pass(tester, 4);
      expect(reads, hasLength(recovered + 1));
      schedule.dispose();
    });

    testWidgets('names failing do not hold back the messages fallback', (
      tester,
    ) async {
      final schedule = CommunityChatReadSchedule(
        renewalPace: const Duration(seconds: 4),
        canRead: () => visible,
        pushHealthy: () => healthy,
        renewalAvailable: () => renewal,
        userActive: () => active,
        now: () => now,
        read: ({required renewal}) async {
          reads.add(renewal ? 'renew' : 'full');
          return (renewal: renewal, ok: !renewal);
        },
      );
      await pass(tester, 40);
      expect(reads.where((read) => read == 'renew').length, lessThan(5));
      healthy = false;
      reads.clear();
      await pass(tester, 9);
      expect(
        reads.where((read) => read == 'full').length,
        greaterThanOrEqualTo(2),
        reason: 'A push turning unhealthy is noticed within the old 3 s pace.',
      );
      schedule.dispose();
    });

    testWidgets('names recover though full reads keep succeeding', (
      tester,
    ) async {
      var namesWork = false;
      final schedule = CommunityChatReadSchedule(
        renewalPace: const Duration(seconds: 4),
        canRead: () => visible,
        pushHealthy: () => healthy,
        renewalAvailable: () => renewal,
        userActive: () => active,
        now: () => now,
        read: ({required renewal}) async {
          reads.add(renewal ? 'renew' : 'full');
          return (renewal: renewal, ok: !renewal || namesWork);
        },
      );
      await pass(tester, 200);
      expect(reads.where((read) => read == 'renew').length, lessThan(9));
      namesWork = true;
      await pass(tester, 61);
      reads.clear();
      await pass(tester, 12);
      // Back at the 4 s pace; a reconciliation may stand in for one of them.
      expect(reads, hasLength(3));
      expect(reads.where((read) => read == 'renew').length, greaterThan(1));
      schedule.dispose();
    });

    testWidgets('a read that did not run is not a failure', (tester) async {
      final schedule = CommunityChatReadSchedule(
        renewalPace: const Duration(seconds: 4),
        canRead: () => visible,
        pushHealthy: () => healthy,
        renewalAvailable: () => renewal,
        userActive: () => active,
        now: () => now,
        read: ({required renewal}) async {
          reads.add('busy');
          return null;
        },
      );
      await pass(tester, 10);
      expect(reads.length, greaterThanOrEqualTo(2), reason: 'Tries again soon.');
      schedule.dispose();
    });

    testWidgets('a renewal that became a failing full read backs off as both', (
      tester,
    ) async {
      final schedule = CommunityChatReadSchedule(
        renewalPace: const Duration(seconds: 4),
        canRead: () => visible,
        pushHealthy: () => healthy,
        renewalAvailable: () => renewal,
        userActive: () => active,
        now: () => now,
        read: ({required renewal}) async {
          reads.add(renewal ? 'renew' : 'full');
          return (renewal: false, ok: false);
        },
      );
      await pass(tester, 13);
      expect(reads, hasLength(2), reason: 'At 4 s and 12 s, not every 4 s.');
      await pass(tester, 300);
      final capped = reads.length;
      await pass(tester, 240);
      expect(reads.length - capped, inInclusiveRange(3, 10));
      schedule.dispose();
    });

    testWidgets('an owed read runs at once and backs off when it fails', (
      tester,
    ) async {
      var owed = true;
      renewal = false;
      final schedule = CommunityChatReadSchedule(
        renewalPace: const Duration(seconds: 4),
        canRead: () => visible,
        pushHealthy: () => healthy,
        renewalAvailable: () => renewal,
        userActive: () => active,
        catchUpDue: () => owed,
        now: () => now,
        read: ({required renewal}) async {
          reads.add(renewal ? 'renew' : 'full');
          return (renewal: renewal, ok: false);
        },
      );
      await pass(tester, 1);
      expect(reads, ['full'], reason: 'No wait for the reconciliation.');
      await pass(tester, 7);
      expect(reads, ['full'], reason: 'Failed once: next after 8 s.');
      await pass(tester, 1);
      expect(reads, ['full', 'full']);
      await pass(tester, 300);
      final capped = reads.length;
      await pass(tester, 240);
      expect(reads.length - capped, inInclusiveRange(3, 5));
      owed = false;
      schedule.dispose();
    });

    testWidgets('a full read succeeding elsewhere ends the backoff', (
      tester,
    ) async {
      var owed = false;
      renewal = false;
      final schedule = CommunityChatReadSchedule(
        renewalPace: const Duration(seconds: 4),
        canRead: () => visible,
        pushHealthy: () => healthy,
        renewalAvailable: () => renewal,
        userActive: () => active,
        catchUpDue: () => owed,
        now: () => now,
        read: ({required renewal}) async {
          reads.add('full');
          if (reads.length == 1) return (renewal: renewal, ok: false);
          owed = false;
          return (renewal: renewal, ok: true);
        },
      );
      await pass(tester, 31);
      expect(reads, hasLength(1));
      schedule.noteContentRead();
      owed = true;
      schedule.poke();
      await pass(tester, 1);
      expect(reads, hasLength(2), reason: 'No leftover backoff on a pushed read.');
      schedule.dispose();
    });

    testWidgets('an owed read waits behind another window, then runs', (
      tester,
    ) async {
      var owed = true;
      final schedule = CommunityChatReadSchedule(
        renewalPace: const Duration(seconds: 4),
        canRead: () => visible,
        pushHealthy: () => healthy,
        renewalAvailable: () => false,
        userActive: () => active,
        catchUpDue: () => owed,
        now: () => now,
        read: ({required renewal}) async {
          reads.add('full');
          owed = false;
          return (renewal: renewal, ok: true);
        },
      );
      visible = false;
      await pass(tester, 20);
      expect(reads, isEmpty);
      visible = true;
      await pass(tester, 3);
      expect(reads, isNotEmpty);
      schedule.dispose();
    });

    testWidgets('a pushed full read resets the reconciliation', (tester) async {
      final schedule = make();
      await pass(tester, 28);
      schedule.noteContentRead();
      await pass(tester, 20);
      expect(reads.where((read) => read == 'full'), isEmpty);
      schedule.dispose();
    });
  });

  group('controller', () {
    late _Port port;
    late CommunityChatController model;
    setUp(() async {
      port = _Port();
      model = CommunityChatController(port, _target)
        ..setReadingContext(visible: true, foreground: true);
      await model.refresh();
      port.reads.clear();
    });
    tearDown(() async {
      model.dispose();
      await port.changes.close();
    });

    test('a renewal takes no channel read and keeps unread and send state', () async {
      final unread = model.unreadCount, canSend = model.canSend;
      final latest = model.latestSequence;
      final read = await model.refresh(silent: true, renewal: true);
      expect(read, (renewal: true, ok: true));
      expect(model.catchUp.due, isFalse);
      expect(port.reads, ['renew']);
      expect(model.canSend, canSend);
      expect(model.unreadCount, unread);
      expect(model.latestSequence, latest);
    });

    test('a renewal that finds new messages owes the full read', () async {
      var asked = 0;
      model.catchUp.onDue = () => asked++;
      port.renewalPage = page([3], latest: 3, unread: 0, older: false);
      port.next = page([], latest: 3, unread: 1, older: false);
      await model.refresh(silent: true, renewal: true);
      expect(model.messages.last.sequence, 3, reason: 'New messages come too.');
      expect((model.catchUp.due, asked), (true, 1));
      await model.refresh(silent: true);
      expect(model.catchUp.due, isFalse);
      expect(model.latestSequence, 3);
      expect(model.unreadCount, 1, reason: 'Count and mark move together.');
    });

    test('a mark the full read cannot confirm is asked about only once', () async {
      port.renewalPage = page([], latest: 7, unread: 0, older: false);
      port.next = page([], latest: 2, unread: 0, older: false);
      await model.refresh(silent: true, renewal: true);
      expect(model.catchUp.due, isTrue);
      await model.refresh(silent: true);
      expect((model.catchUp.due, model.latestSequence), (false, 2));
      await model.refresh(silent: true, renewal: true);
      expect(model.catchUp.due, isFalse, reason: 'Same answer, no new read.');
      port.renewalPage = page([], latest: 8, unread: 0, older: false);
      await model.refresh(silent: true, renewal: true);
      expect(model.catchUp.due, isTrue);
    });

    test('only a full read that worked reports itself', () async {
      var reported = 0;
      model.catchUp.onFullRead = () => reported++;
      port.next = page([], latest: 2, unread: 0, older: false);
      await model.refresh(silent: true, renewal: true);
      expect(reported, 0);
      await model.refresh(silent: true);
      expect(reported, 1);
      port.fullFailure = const CommunityFailure('unavailable');
      await model.refresh(silent: true);
      expect(reported, 1);
    });

    test('a failed full read is still owed', () async {
      port.renewalPage = page([], latest: 7, unread: 0, older: false);
      await model.refresh(silent: true, renewal: true);
      port.fullFailure = const CommunityFailure('unavailable');
      final read = await model.refresh(silent: true);
      expect(read, (renewal: false, ok: false));
      expect(model.catchUp.due, isTrue);
    });

    test('a failed renewal costs names, not the conversation', () async {
      port.renewalFailure = const CommunityFailure('unavailable');
      expect(
        await model.refresh(silent: true, renewal: true),
        (renewal: true, ok: false),
      );
      expect(model.error, isNull);
      expect(model.messages, isNotEmpty);
      port.renewalFailure = null;
      expect(
        await model.refresh(silent: true, renewal: true),
        (renewal: true, ok: true),
      );
    });

    test('lost access during a renewal ends the conversation', () async {
      port.renewalFailure = const CommunityFailure('notAllowed');
      await model.refresh(silent: true, renewal: true);
      expect(model.invalidated, isTrue);
      expect(model.messages, isEmpty);
    });

    test('a push during a read is owed, and the schedule is told at once', () async {
      var asked = 0;
      model.catchUp.onDue = () => asked++;
      port.heldRenewal = Completer();
      final renewal = model.refresh(silent: true, renewal: true);
      await _settle();
      expect(await model.refresh(silent: true), isNull, reason: 'Busy.');
      expect(port.reads, ['renew']);
      port.heldRenewal!.complete(port.renewalPage);
      port.heldRenewal = null;
      await renewal;
      expect(model.catchUp.due, isTrue);
      expect(asked, 1);
      expect(model.loading, isFalse, reason: 'Free for that read to start.');
    });

    test('a push during a full read survives that read finishing', () async {
      port
        ..next = page([], latest: 2, unread: 0, older: false)
        ..heldFull = Completer();
      final full = model.refresh(silent: true);
      await _settle();
      await model.refresh(silent: true);
      port.heldFull!.complete(port.next);
      port.heldFull = null;
      await full;
      expect(model.catchUp.due, isTrue);
    });

    test('without renewal, or out of sight, it is the normal read', () async {
      port.renewalOn = false;
      await model.refresh(silent: true, renewal: true);
      expect(port.reads, ['full']);
      port
        ..renewalOn = true
        ..reads.clear();
      model.setReadingContext(visible: true, foreground: false);
      expect(model.authorRenewalAvailable, isFalse);
    });
  });
}
