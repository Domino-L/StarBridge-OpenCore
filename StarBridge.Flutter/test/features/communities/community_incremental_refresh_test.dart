import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_header.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_copy.dart';

import 'community_workspace_test.dart'
    show WorkspaceTestPort, workspacePayload, mediaChunk;
import 'community_workspace_view_test.dart' show host, openMemberActions;
import 'community_member_role_test.dart' show MemberRoleFake;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  testWidgets('visible workspace recovers offline reads without manual refresh', (
    tester,
  ) async {
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    final state = tester.state<CommunityWorkspaceViewState>(
      find.byType(CommunityWorkspaceView),
    );
    final previous = state.model.workspace;
    final header = tester.element(find.byType(CommunityWorkspaceHeader));
    port.reader = (_, _, _) async =>
        throw const CommunityFailure('unavailable');
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(state.model.workspace, same(previous));
    expect(state.model.error, 'unavailable');
    expect(tester.element(find.byType(CommunityWorkspaceHeader)), same(header));
    port.reader = (_, _, _) async =>
        CommunityWorkspace.parse(workspacePayload());
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(state.model.error, isNull);
    expect(state.model.workspace, isNotNull);
    expect(tester.element(find.byType(CommunityWorkspaceHeader)), same(header));
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'transport failure preserves the workspace and retry recovers',
    () async {
      final port = WorkspaceTestPort();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      final previous = model.workspace;
      port.reader = (_, _, _) async =>
          throw const CommunityFailure('unavailable');
      await model.load();
      expect(model.workspace, same(previous));
      expect(model.error, 'unavailable');
      port.reader = (_, _, _) async =>
          CommunityWorkspace.parse(workspacePayload());
      await model.load();
      expect(model.error, isNull);
      expect(model.workspace, isNotNull);
    },
  );
  testWidgets(
    'cancelling member role assignment does not reread the workspace',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = MemberRoleFake();
      addTearDown(port.changes.close);
      var reads = 0;
      port.reader = (ref, query, _) async {
        reads++;
        final payload = workspacePayload(target: ref, query: query);
        (payload['access'] as Map)['isOwner'] = true;
        ((payload['members'] as List).first as Map)['isSelf'] = false;
        return CommunityWorkspace.parse(payload);
      };
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      await openMemberActions(tester, 'b' * 32);
      await tester.tap(find.byKey(ValueKey('assign-member-${'b' * 32}')));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(CommunityMemberRoleDialog));
      await tester.tap(find.byTooltip(memberRoleText(context, 'close')));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityMemberRoleDialog), findsNothing);
      expect(reads, 1);
      expect(port.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'background metadata keeps the same mounted header and scroll position',
    (tester) async {
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      final state = tester.state<CommunityWorkspaceViewState>(
        find.byType(CommunityWorkspaceView),
      );
      final header = tester.element(find.byType(CommunityWorkspaceHeader));
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      final position = scroll.position.pixels;
      final pending = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => pending.future;
      final read = state.model.load();
      await tester.pump();
      expect(
        tester.element(find.byType(CommunityWorkspaceHeader)),
        same(header),
      );
      expect(scroll.position.pixels, position);
      expect(
        find.byKey(const ValueKey('community-refresh-progress')),
        findsOneWidget,
      );
      pending.complete(CommunityWorkspace.parse(workspacePayload()));
      await read;
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byType(CommunityWorkspaceHeader)),
        same(header),
      );
      expect(scroll.position.pixels, position);
      expect(
        find.byKey(const ValueKey('community-refresh-progress')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'opening and leaving settings without edits does not reload the organization',
    (tester) async {
      final port = WorkspaceTestPort();
      var reads = 0;
      port.reader = (reference, _, _) async {
        reads++;
        final payload = workspacePayload(target: reference);
        (payload['access'] as Map)['isOwner'] = true;
        return CommunityWorkspace.parse(payload);
      };
      addTearDown(port.changes.close);
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('community-section-manage')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('community-settings-back')));
      await tester.pumpAndSettle();
      expect(
        reads,
        1,
        reason: 'Navigation alone must not refetch the organization.',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('metadata refresh retains visible data and does not redownload unchanged images', () async {
    final port = WorkspaceTestPort();
    var mediaReads = 0;
    final payload = workspacePayload()..['hasLogo'] = true;
    port.reader = (_, _, _) async => CommunityWorkspace.parse(payload);
    port.mediaReader = (_, _) async {
      mediaReads++;
      return mediaChunk(Uint8List.fromList([1, 2, 3]), 0);
    };
    final model = CommunityWorkspaceController(port, 'a' * 32);
    addTearDown(() async {
      model.dispose();
      await port.changes.close();
    });
    await model.load();
    final previous = model.workspace;
    final bytes = model.image('logo');
    final pending = Completer<CommunityWorkspace>();
    port.reader = (_, _, _) => pending.future;
    final reading = model.load();
    expect(model.workspace, same(previous));
    expect(model.image('logo'), same(bytes));
    pending.complete(CommunityWorkspace.parse(payload));
    await reading;
    expect(mediaReads, 1);
    port.reader = (_, _, _) async => CommunityWorkspace.parse(payload);
    await model.load(refreshImages: {'logo'});
    expect(
      mediaReads,
      2,
      reason: 'An accepted logo change explicitly invalidates only its image.',
    );
    payload['hasLogo'] = false;
    await model.load();
    expect(
      model.image('logo'),
      isNull,
      reason: 'Removed images must not remain visible.',
    );
  });
}
