import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_session.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';

import 'community_navigation_cache_test.dart' show NavigationPort;
import 'community_section_return_test.dart' show CountedPort;
import 'community_workspace_test.dart' show workspacePayload;
import 'community_workspace_view_test.dart' show host;
import 'community_image_test_support.dart';
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  testWidgets('only visible authorized workspace announces overlay context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final port = NavigationPort();
    addTearDown(port.close);
    final focuses = <String>[];
    Widget page(bool active) => host(
      port,
      const Locale('zh', 'CN'),
      active: active,
      onFocused: focuses.add,
    );
    await tester.pumpWidget(page(false));
    await settleCommunityImages(tester);
    expect(focuses, isEmpty);
    await tester.pumpWidget(page(true));
    await settleCommunityImages(tester);
    expect(focuses, isNotEmpty);
    final state = tester.state<CommunityWorkspaceViewState>(
      find.byType(CommunityWorkspaceView),
    );
    expect(focuses.toSet(), {state.model.workspace!.code});
    await tester.pumpWidget(page(false));
    await settleCommunityImages(tester);
    focuses.clear();
    await state.model.load(silent: true);
    await settleCommunityImages(tester);
    expect(focuses, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'least-recent organization is evicted, not the just-revisited one',
    () async {
      final port = NavigationPort();
      final session = CommunityWorkspaceSession(capacity: 2);
      addTearDown(session.clear);
      addTearDown(port.close);
      final a = session.obtain(port, 'a' * 32, 'org-a');
      await a.enter('a' * 32);
      final b = session.obtain(port, 'b' * 32, 'org-b');
      await b.enter('b' * 32);
      session.obtain(port, 'a' * 32, 'org-a');
      final c = session.obtain(port, 'c' * 32, 'org-c');
      await c.enter('c' * 32);
      expect(a.workspace, isNotNull);
      expect(b.workspace, isNull);
      expect(c.workspace, isNotNull);
      expect(session.obtain(port, 'a' * 32, 'org-a'), same(a));
      expect(session.obtain(port, 'b' * 32, 'org-b'), isNot(same(b)));
    },
  );

  test(
    'account invalidation clears every cached organization and late reply',
    () async {
      final port = NavigationPort();
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      final a = module.workspaceSession.obtain(port, 'a' * 32, 'org-a');
      await a.enter('a' * 32);
      final b = module.workspaceSession.obtain(port, 'b' * 32, 'org-b');
      await b.enter('b' * 32);
      final pending = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => pending.future;
      final reading = a.load(silent: true);
      port.changes.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(a.workspace, isNull);
      expect(b.workspace, isNull);
      pending.complete(CommunityWorkspace.parse(workspacePayload()));
      await reading;
      expect(a.workspace, isNull);
      expect(
        module.workspaceSession.obtain(port, 'b' * 32, 'org-b'),
        isNot(same(b)),
      );
    },
  );

  test(
    'a revoked organization loses its data without borrowing another snapshot',
    () async {
      var now = DateTime(2026);
      final port = NavigationPort();
      final session = CommunityWorkspaceSession(now: () => now);
      addTearDown(session.clear);
      addTearDown(port.close);
      final a = session.obtain(port, 'a' * 32, 'org-a');
      await a.enter('a' * 32);
      final b = session.obtain(port, 'b' * 32, 'org-b');
      await b.enter('b' * 32);
      final snapshotB = b.workspace;
      now = now.add(const Duration(seconds: 11));
      port.reader = (_, _, _) async =>
          throw const CommunityFailure('notAllowed');
      await session.obtain(port, 'a' * 32, 'org-a').enter('a' * 32);
      expect(a.workspace, isNull);
      expect(a.error, 'notAllowed');
      expect(b.workspace, same(snapshotB));
    },
  );

  test(
    'speculation does not replace or populate other organizations',
    () async {
      final port = NavigationPort();
      final session = CommunityWorkspaceSession(capacity: 1);
      addTearDown(session.clear);
      addTearDown(port.close);
      final a = session.obtain(port, 'a' * 32, 'org-a');
      await a.enter('a' * 32);
      var reads = 0;
      port.reader = (target, query, offset) async {
        reads++;
        return CommunityWorkspace.parse(
          workspacePayload(target: target, query: query),
        );
      };
      await session.prefetch(port, 'b' * 32, 'org-b');
      expect(reads, 0);
      expect(session.obtain(port, 'a' * 32, 'org-a'), same(a));
      expect(a.workspace, isNotNull);
    },
  );

  for (final section in ['chat', 'ships']) {
    testWidgets('real view restores $section after switching A to B to A', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = CountedPort();
      final session = CommunityWorkspaceSession();
      addTearDown(session.clear);
      addTearDown(port.changes.close);
      Widget page(String id) => host(
        port,
        const Locale('zh', 'CN'),
        target: id * 32,
        organizationKey: 'org-$id',
        session: session,
      );
      await tester.pumpWidget(page('a'));
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(ValueKey('community-section-$section')));
      await settleCommunityImages(tester);
      final a = tester
          .state<CommunityWorkspaceViewState>(
            find.byType(CommunityWorkspaceView),
          )
          .model;
      final chatA = a.chat;
      final shipsA = a.ships;
      await tester.pumpWidget(page('b'));
      await settleCommunityImages(tester);
      final b = tester
          .state<CommunityWorkspaceViewState>(
            find.byType(CommunityWorkspaceView),
          )
          .model;
      expect(b, isNot(same(a)));
      expect(b.targetRef, 'b' * 32);
      expect(b.selectedSection, 'members');
      final chatReads = port.chatReads, shipReads = port.shipReads;
      await tester.pumpWidget(page('a'));
      await settleCommunityImages(tester);
      final returned = tester
          .state<CommunityWorkspaceViewState>(
            find.byType(CommunityWorkspaceView),
          )
          .model;
      expect(returned, same(a));
      expect(returned.selectedSection, section);
      expect(returned.chat, same(chatA));
      expect(returned.ships, same(shipsA));
      expect(
        find.byType(
          section == 'chat' ? CommunityChatPanel : CommunityShipsPanel,
        ),
        findsOneWidget,
      );
      expect(port.chatReads, chatReads);
      expect(port.shipReads, shipReads);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
