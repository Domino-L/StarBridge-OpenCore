import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_controller.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_session.dart';

import 'community_announcements_dialog_test.dart'
    show AnnouncementsWorkspaceFake;
import 'community_announcements_controller_test.dart' show AnnouncementsFake;
import 'community_announcements_test.dart' show target;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  test('recent announcement return reuses success, stale return stays silent, manual refresh reads', () async {
    var now = DateTime(2026);
    final port = AnnouncementsFake();
    final model = CommunityAnnouncementsController(
      port,
      target,
      now: () => now,
    );
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await model.enter();
    final previous = model.page;
    await model.enter();
    expect(port.reads, hasLength(1));
    now = now.add(const Duration(seconds: 11));
    port.heldRead = Completer<CommunityAnnouncementsPage>();
    final returning = model.enter();
    model.refreshTimeLabels();
    expect(model.page, same(previous));
    expect(model.showProgress, false);
    await model.enter();
    expect(port.reads, hasLength(2));
    port.heldRead!.complete(CommunityAnnouncementsPage.parse(port.payload()));
    await returning;
    port.heldRead = null;
    await model.refresh();
    expect(port.reads, hasLength(3));
    port.failure = 'unavailable';
    await model.refresh();
    await model.enter();
    expect(port.reads, hasLength(5));
    port.failure = 'notAllowed';
    await model.enter();
    expect(model.page, isNull);
  });

  testWidgets(
    'leaving organization and returning retains announcement but account invalidation clears it',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = AnnouncementsWorkspaceFake();
      final session = CommunityWorkspaceSession();
      addTearDown(session.clear);
      addTearDown(port.changes.close);
      Widget page() => host(
        port,
        const Locale('zh', 'CN'),
        session: session,
        organizationKey: 'organization-a',
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final announcements = session
          .obtain(port, target, 'organization-a')
          .announcements!;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(port.reads, hasLength(1));
      expect(find.textContaining('远航准备通知'), findsOneWidget);
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(announcements.page, isNull);
      expect(find.textContaining('远航准备通知'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'organization details reuse the announcement already shown in header',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = AnnouncementsWorkspaceFake();
      addTearDown(port.changes.close);
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      expect(port.reads, hasLength(1));
      await tester.tap(find.byKey(const Key('community-open-details')));
      await tester.pumpAndSettle();
      expect(find.text('远航准备通知'), findsOneWidget);
      expect(
        port.reads,
        hasLength(1),
        reason: 'Opening details must reuse the current announcement snapshot.',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
