import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_activity_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_attention.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';
import 'package:starbridge_flutter/features/communities/community_shortcuts.dart';

import 'community_navigation_cache_test.dart' show NavigationPort, card;
import 'community_navigation_test.dart' show shell;
import 'community_chat_controller_test.dart' show FakeChat, page;
import 'bridge_communities_test.dart' show CommunityHarness;
import 'community_chat_test.dart' show chatPage;
import 'community_chat_panel_test.dart' show showChat;
import '../friends/social_layout_test.dart' show loadFonts;

class UnreadPort extends NavigationPort
    implements
        CommunityChatPort,
        CommunityChatPreviewPort,
        CommunityActivityPort,
        CommunityChatSendPort {
  final activity = StreamController<void>.broadcast(sync: true);
  final chat = FakeChat()..next = page([], latest: 0, unread: 0, older: false);
  int previewReads = 0;
  @override
  bool get chatSendAvailable => true;
  @override
  Future<CommunityChatSendOutcome> sendChat(CommunityChatSendIntent intent) =>
      chat.sendChat(intent);
  @override
  bool get activityHealthy => true;
  @override
  Stream<void> get workspaceChanges => activity.stream;
  @override
  bool get chatAvailable => true;
  @override
  bool get chatReadReceiptsAvailable => true;
  @override
  Future<CommunityChatPage> readChatPreview(String targetRef) {
    return readChat(targetRef);
  }

  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) {
    previewReads++;
    return chat.readChat(targetRef, after: after, before: before);
  }

  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) => chat.markChatRead(targetRef, message);
  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) => chat.readChatDetail(targetRef, messageRef, offset, version);
  @override
  Future<void> close() async {
    await activity.close();
    await chat.changes.close();
    await super.close();
  }
}

void main() {
  setUpAll(loadFonts);
  Future<void> drain() => Future<void>.delayed(Duration.zero);
  late UnreadPort source;
  late CommunityChatAttention attention;
  setUp(() {
    source = UnreadPort();
    attention = CommunityChatAttention(source);
  });
  tearDown(() async {
    attention.dispose();
    await source.close();
  });
  testWidgets(
    'background unread accepts a healthy bridge response after three seconds',
    (tester) async {
      final host = CommunityHarness(
        capabilities: ['communities.chat', 'communities.chatDetail'],
        holdNames: {'communities.chat'},
        responses: {'communities.chat': chatPage()},
      );
      final projection = CommunityChatAttention(host.adapter);
      addTearDown(() async {
        projection.dispose();
        await host.close();
      });
      projection.bind(['a' * 32]);
      await tester.pump();
      final request = host.requests.singleWhere(
        (r) => r.name == 'communities.chat',
      );
      await tester.pump(const Duration(seconds: 3));
      expect(
        host.requests.where((r) => r.name == 'bridge.cancel'),
        isEmpty,
        reason: 'A healthy three-second read must not use the preview cutoff.',
      );
      await host.reply(request);
      await tester.pump();
      expect(projection.count('a' * 32), 2);
      expect(
        host.requests.where((r) => r.name == 'communities.markChatRead'),
        isEmpty,
      );
    },
  );
  test(
    'background preview updates without a chat controller or receipts',
    () async {
      source.chat.next = page([1], latest: 1, unread: 1);
      attention.bind([card.targetRef]);
      await drain();
      expect(attention.count(card.targetRef), 1);
      expect(source.chat.receipts, isEmpty);
      source.chat.next = page([2], latest: 2, unread: 2);
      source.activity.add(null);
      await drain();
      expect(attention.count(card.targetRef), 2);
    },
  );
  test('transient failure retains count; revoked access clears it', () async {
    source.chat.next = page([1], latest: 1, unread: 1);
    attention.bind([card.targetRef]);
    await drain();
    source.chat.failure = const CommunityFailure('unavailable');
    attention.refresh();
    await drain();
    expect(attention.count(card.targetRef), 1);
    expect(attention.needsReconciliation, isTrue);
    source.chat.failure = const CommunityFailure('dataInvalid');
    attention.refresh();
    await drain();
    expect(attention.count(card.targetRef), 1);
    source.chat.failure = const CommunityFailure('notAllowed');
    attention.refresh();
    await drain();
    expect(attention.count(card.targetRef), 0);
    expect(attention.needsReconciliation, isFalse);
  });
  test(
    'membership list updates do not flash unchanged unread badges',
    () async {
      source.chat.next = page([1], latest: 1, unread: 1);
      attention.bind([card.targetRef]);
      await drain();
      final observations = <int>[];
      attention.addListener(
        () => observations.add(attention.count(card.targetRef)),
      );
      source.chat.heldRead = Completer();
      attention.bind([card.targetRef, 'b' * 32]);
      expect(attention.count(card.targetRef), 1);
      expect(observations, isNot(contains(0)));
      source.chat.heldRead!.complete(page([1], latest: 1, unread: 1));
      await drain();
      expect(observations, isNot(contains(0)));
    },
  );
  test('account invalidation ignores a late successful preview', () async {
    final held = source.chat.heldRead = Completer();
    attention.bind([card.targetRef]);
    source.changes.add(null);
    held.complete(page([1], latest: 1, unread: 1));
    await drain();
    expect(attention.count(card.targetRef), 0);
    final reads = source.previewReads;
    source.activity.add(null);
    await drain();
    expect(source.previewReads, reads);
  });
  test('removed and rebound target cannot accept an old request', () async {
    final held = source.chat.heldRead = Completer();
    attention.bind([card.targetRef]);
    attention.bind([]);
    source.chat.heldRead = null;
    source.chat.next = page([], latest: 0, unread: 0);
    attention.bind([card.targetRef]);
    held.complete(page([8], latest: 8, unread: 8));
    await drain();
    expect(attention.count(card.targetRef), 0);
  });
  test(
    'visible read wins over late preview and stale draft notifications',
    () async {
      final chat = CommunityChatController(source, card.targetRef);
      addTearDown(chat.dispose);
      source.chat.next = page([1], latest: 1, unread: 1);
      attention.bind([card.targetRef]);
      await drain();
      await chat.refresh();
      attention.observe(chat);
      final held = source.chat.heldRead = Completer();
      attention.refresh();
      chat.setReadingContext(visible: true, foreground: true);
      await chat.acknowledgeVisible(chat.messages.single.messageRef);
      attention.observe(chat);
      expect(attention.count(card.targetRef), 0);
      held.complete(page([1], latest: 1, unread: 1));
      await drain();
      expect(attention.count(card.targetRef), 0);
      source.chat.heldRead = null;
      source.chat.next = page([2], latest: 2, unread: 1);
      attention.refresh();
      await drain();
      chat.updateDraft('next');
      attention.observe(chat);
      expect(attention.count(card.targetRef), 1);
    },
  );
  test('activity burst coalesces to one follow-up read', () async {
    final held = source.chat.heldRead = Completer();
    attention.bind([card.targetRef]);
    for (var i = 0; i < 20; i++) {
      source.activity.add(null);
    }
    expect(source.previewReads, 1);
    source.chat.heldRead = null;
    source.chat.next = page([2], latest: 2, unread: 2);
    held.complete(page([1], latest: 1, unread: 1));
    await drain();
    expect(source.previewReads, 2);
    expect(attention.count(card.targetRef), 2);
  });
  testWidgets('visible chat reads on activity without waiting for its timer', (
    tester,
  ) async {
    source.chat.next = page([1], latest: 1, unread: 1, older: false);
    await showChat(tester, source);
    final reads = source.previewReads;
    source.chat.next = page([2], latest: 2, unread: 1, older: false);
    source.activity.add(null);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(source.previewReads, greaterThan(reads));
    expect(find.text('Message 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'visible latest clears badge before receipt and failed receipt restores it',
    () async {
      final chat = CommunityChatController(source, card.targetRef);
      addTearDown(chat.dispose);
      chat.addListener(() => attention.observe(chat));
      source.chat.next = page([1], latest: 1, unread: 1);
      attention.bind([card.targetRef]);
      await drain();
      await chat.refresh();
      chat.setReadingContext(visible: true, foreground: true);
      final receipt = source.chat.heldReceipt = Completer();
      final pending = chat.acknowledgeVisible(chat.messages.single.messageRef);
      expect(chat.confirmedReadThrough, 0);
      expect(attention.count(card.targetRef), 0);
      var notifications = 0;
      chat.addListener(() => notifications++);
      await chat.acknowledgeVisible(chat.messages.single.messageRef);
      expect(
        notifications,
        0,
        reason: 'Repeated visible acknowledgment must not rebuild every frame.',
      );
      attention.refresh();
      await drain();
      expect(attention.count(card.targetRef), 0);
      receipt.complete(
        const CommunityChatReadReceipt('rejected', error: 'unavailable'),
      );
      await pending;
      expect(chat.confirmedReadThrough, 0);
      expect(attention.count(card.targetRef), 1);
    },
  );
  test('new unseen messages survive an older optimistic receipt', () async {
    final chat = CommunityChatController(source, card.targetRef);
    addTearDown(chat.dispose);
    chat.addListener(() => attention.observe(chat));
    source.chat.next = page([1], latest: 1, unread: 1);
    attention.bind([card.targetRef]);
    await drain();
    await chat.refresh();
    chat.setReadingContext(visible: true, foreground: true);
    final receipt = source.chat.heldReceipt = Completer();
    final pending = chat.acknowledgeVisible(chat.messages.single.messageRef);
    source.chat.next = page([2], latest: 2, unread: 1);
    attention.refresh();
    await drain();
    expect(attention.count(card.targetRef), 1);
    receipt.complete(
      const CommunityChatReadReceipt('accepted', readThrough: 1),
    );
    await pending;
    expect(chat.confirmedReadThrough, 1);
    expect(attention.count(card.targetRef), 1);
  });
  test(
    'receipt rollback is not blocked by a concurrent failed history read',
    () async {
      final chat = CommunityChatController(source, card.targetRef);
      addTearDown(chat.dispose);
      chat.addListener(() => attention.observe(chat));
      source.chat.next = page([1], latest: 1, unread: 1);
      attention.bind([card.targetRef]);
      await drain();
      await chat.refresh();
      chat.setReadingContext(visible: true, foreground: true);
      final receipt = source.chat.heldReceipt = Completer();
      final pending = chat.acknowledgeVisible(chat.messages.single.messageRef);
      final read = source.chat.heldRead = Completer();
      final refreshing = chat.refresh(silent: true);
      receipt.complete(
        const CommunityChatReadReceipt('rejected', error: 'unavailable'),
      );
      await pending;
      expect(attention.count(card.targetRef), 1);
      read.completeError(const CommunityFailure('unavailable'));
      await refreshing;
      source.chat.heldRead = null;
      attention.refresh();
      await drain();
      expect(attention.count(card.targetRef), 1);
    },
  );
  for (final openedOrganization in [false, true]) {
    testWidgets(
      'incoming chat shows unread without chat page: organizationOpen=$openedOrganization',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final port = UnreadPort();
        final module = CommunitiesModule(port);
        addTearDown(module.dispose);
        await tester.pumpWidget(shell(module));
        await tester.pumpAndSettle();
        if (openedOrganization) {
          await tester.tap(
            find.descendant(
              of: find.byType(CommunityShortcuts),
              matching: find.text(card.name),
            ),
          );
          await tester.pumpAndSettle();
        }
        port.chat.next = page([1], latest: 1, unread: 1, older: false);
        // A healthy presence heartbeat does not guarantee a chat notification.
        // Stay outside chat and do not manufacture a workspace change event.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(
          port.chat.receipts,
          isEmpty,
          reason: 'Background reads must not acknowledge messages.',
        );
        expect(
          find.descendant(
            of: find.byType(CommunityShortcuts),
            matching: find.byType(AttentionCount),
          ),
          findsOneWidget,
        );
        if (openedOrganization) {
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('community-section-chat')),
              matching: find.byType(AttentionCount),
            ),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'sidebar retries a failed unread read even when event transport is healthy',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = UnreadPort();
      port.chat.failure = const CommunityFailure('unavailable');
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      await tester.pumpWidget(shell(module));
      await tester.pumpAndSettle();
      expect(module.chatAttention.count(card.targetRef), 0);
      port.chat.failure = null;
      port.chat.next = page([1], latest: 1, unread: 1, older: false);
      // No new event: the earlier event has already been consumed by the failed read.
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(CommunityShortcuts),
          matching: find.byType(AttentionCount),
        ),
        findsOneWidget,
      );
      expect(port.chat.receipts, isEmpty);
      final settledReads = port.previewReads;
      expect(module.chatAttention.needsReconciliation, isFalse);
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(
        port.previewReads,
        greaterThan(settledReads),
        reason: 'The existing shell refresh reconciles missed chat events.',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
