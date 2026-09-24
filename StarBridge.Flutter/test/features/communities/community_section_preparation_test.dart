import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_session.dart';

import 'community_section_return_test.dart' show CountedPort;
import 'community_workspace_view_test.dart' show host;
import 'community_image_test_support.dart';
import '../friends/social_layout_test.dart' show loadFonts;

class PreparingPort extends CountedPort {
  Completer<void>? chatGate;
  int receipts = 0;
  @override
  bool get chatReadReceiptsAvailable => true;
  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String target,
    CommunityChatMessage message,
  ) {
    receipts++;
    return super.markChatRead(target, message);
  }

  @override
  Future<CommunityChatPage> readChat(
    String target, {
    int after = 0,
    int before = 0,
  }) async {
    final result = super.readChat(target, after: after, before: before);
    await chatGate?.future;
    return result;
  }
}

void main() {
  setUpAll(loadFonts);
  test(
    'unmounted workspaces finish section preparation without marking chat read',
    () async {
      final port = PreparingPort();
      final session = CommunityWorkspaceSession();
      addTearDown(session.clear);
      addTearDown(port.changes.close);
      for (var i = 0; i < 8; i++) {
        if (!await session.prepareNext(
          port,
          'a' * 32,
          'organization-a',
          'zh-CN',
        )) {
          break;
        }
      }
      expect(port.chatReads, 1);
      expect(port.shipReads, 1);
      expect(port.receipts, 0);
      expect(
        await session.prepareNext(port, 'a' * 32, 'organization-a', 'zh-CN'),
        false,
      );
      final model = session.obtain(port, 'a' * 32, 'organization-a');
      expect(model.ships!.page, isNotNull);
      await model.enter('a' * 32);
      await model.prepareNextSection('zh-CN');
      expect(port.shipReads, 1);
    },
  );
  for (final scenario in [
    'hidden',
    'foreground ships',
    'account invalidation',
  ]) {
    testWidgets('section preparation respects $scenario', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = PreparingPort()..chatGate = Completer<void>();
      final session = CommunityWorkspaceSession();
      addTearDown(session.clear);
      addTearDown(port.changes.close);
      Widget page(bool visible) => TickerMode(
        enabled: visible,
        child: host(
          port,
          const Locale('zh', 'CN'),
          session: session,
          organizationKey: 'organization-a',
        ),
      );
      Future<void> tick() async {
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
      }

      await tester.pumpWidget(page(scenario != 'hidden'));
      await settleCommunityImages(tester);
      await tick();
      if (scenario == 'hidden') {
        expect(port.chatReads, 0);
        expect(port.shipReads, 0);
        await tester.pumpWidget(page(true));
        await tick();
      }
      expect(port.chatReads, 1);
      expect(port.shipReads, 0);
      final old = session.obtain(port, 'a' * 32, 'organization-a').chat!;
      if (scenario == 'foreground ships') {
        await tester.tap(find.byKey(const ValueKey('community-section-ships')));
        await settleCommunityImages(tester);
        expect(
          port.shipReads,
          1,
          reason: 'An explicit click bypasses the speculative queue.',
        );
      } else if (scenario == 'hidden') {
        await tester.pumpWidget(page(false));
      } else {
        port.changes.add(null);
        await tester.pump();
      }
      port.chatGate!.complete();
      await tester.pump();
      await tick();
      expect(port.shipReads, scenario == 'foreground ships' ? 1 : 0);
      expect(port.receipts, 0);
      if (scenario == 'account invalidation') expect(old.messages, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'entering organization prepares chat then ships without visiting tabs or reading messages',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = PreparingPort()..chatGate = Completer<void>();
      final session = CommunityWorkspaceSession();
      addTearDown(session.clear);
      addTearDown(port.changes.close);
      await tester.pumpWidget(
        host(
          port,
          const Locale('zh', 'CN'),
          session: session,
          organizationKey: 'organization-a',
        ),
      );
      await settleCommunityImages(tester);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(port.chatReads, 1);
      expect(
        port.shipReads,
        0,
        reason: 'Low priority ships wait for pending chat.',
      );
      expect(port.receipts, 0);
      port.chatGate!.complete();
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(port.shipReads, 1);
      expect(port.receipts, 0);
      await tester.tap(find.byKey(const ValueKey('community-section-ships')));
      await settleCommunityImages(tester);
      expect(
        port.shipReads,
        1,
        reason: 'Opening ships consumes prepared data.',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
