import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_session.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import 'community_shared_media_test.dart' show SharedMediaPort;
import 'community_workspace_view_test.dart' show host;
import 'community_image_test_support.dart';
import '../friends/social_layout_test.dart' show loadFonts;

class CountedPort extends SharedMediaPort {
  int chatReads = 0, shipReads = 0;
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) {
    chatReads++;
    return super.readChat(targetRef, after: after, before: before);
  }

  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) {
    shipReads++;
    return super.readShips(
      targetRef,
      offset: offset,
      revision: revision,
      query: query,
    );
  }
}

void main() {
  setUpAll(loadFonts);
  for (final section in ['chat', 'ships']) {
    testWidgets('$section retains its read model across root navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = CountedPort();
      final session = CommunityWorkspaceSession();
      addTearDown(session.clear);
      addTearDown(port.changes.close);
      Widget page() => host(
        port,
        const Locale('zh', 'CN'),
        session: session,
        organizationKey: 'organization-a',
      );
      Future<void> open() async {
        await tester.pumpWidget(page());
        await settleCommunityImages(tester);
        await tester.tap(find.byKey(ValueKey('community-section-$section')));
        await settleCommunityImages(tester);
      }

      dynamic current() => tester.state(
        find.byType(
          section == 'chat' ? CommunityChatPanel : CommunityShipsPanel,
        ),
      );
      await open();
      final previous = current().model;
      final readCount = section == 'chat' ? port.chatReads : port.shipReads;
      final snapshot = section == 'chat'
          ? previous.messages.length
          : previous.page;
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
        await tester.pumpWidget(page());
        await settleCommunityImages(tester);
        expect(current().model, same(previous));
      expect(section == 'chat' ? port.chatReads : port.shipReads, readCount);
      expect(
        section == 'chat' ? previous.messages.length : previous.page,
        snapshot,
      );
      await tester.pumpWidget(const SizedBox());
      port.changes.add(null);
      await tester.pump();
      expect(
        section == 'chat' ? previous.messages.isEmpty : previous.page == null,
        true,
      );
    });
  }
}
