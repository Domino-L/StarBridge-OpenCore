import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/community_online_members_controller.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'community_workspace_test.dart';
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  test('background roster read preserves visible members until confirmed replacement', () async {
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    final model = CommunityOnlineMembersController(port, 'a' * 32);
    addTearDown(model.dispose);
    await model.refresh();
    final pending = Completer<CommunityWorkspace>();
    port.reader = (_, _, _) => pending.future;
    final read = model.refresh(silent: true);
    expect(model.showProgress, isFalse);
    expect(model.total, 1);
    expect(model.scanned, 1);
    expect(model.members, hasLength(1));
    pending.completeError(const CommunityFailure('unavailable'));
    await read;
    expect(model.members, hasLength(1));
    expect(model.error, 'unavailable');
    port.reader = (_, _, _) async => throw const CommunityFailure('notAllowed');
    await model.refresh();
    expect(model.members, isEmpty);
  });
  test(
    'unfiltered pagination is bounded and partial counts remain explicit',
    () async {
      final port = WorkspaceTestPort();
      final offsets = <int>[];
      port.reader = (target, query, offset) async {
        expect(query, isEmpty);
        offsets.add(offset);
        final base = workspacePayload(target: target);
        final member = Map<String, Object?>.from(
          (base['members'] as List).first as Map,
        );
        return CommunityWorkspace.parse({
          ...base,
          'offset': offset,
          'totalCount': 221,
          'matchedCount': 221,
          'next': offset + 20 < 221 ? offset + 20 : null,
          'members': List.generate(
            (221 - offset).clamp(0, 20),
            (i) => {
              ...member,
              'memberRef': (offset + i).toRadixString(16).padLeft(32, '0'),
              'online': offset + i == 20 || offset + i == 220,
            },
          ),
        });
      };
      final model = CommunityOnlineMembersController(port, 'a' * 32);
      await model.refresh();
      expect(offsets.length, 10);
      expect(model.members.length, 1);
      expect(model.partial, isTrue);
      expect(model.scanned, 200);
      await model.loadMore();
      expect(model.members.length, 2);
      expect(model.partial, isFalse);
      expect(offsets.last, 220);
      model.dispose();
      await port.changes.close();
    },
  );
  test('hidden paused contradictory offline and unknown presence never count as online', () async {
    final base = workspacePayload();
    final row = Map<String, Object?>.from(
      (base['members'] as List).first as Map,
    );
    for (final state in [
      'InGame',
      'AppOnline',
      'Away',
      'Paused',
      'Offline',
      'Invisible',
      'Unknown',
    ]) {
      final member = CommunityWorkspaceMember.parse({
        ...row,
        'liveStatus': state,
      });
      expect(
        CommunityOnlineMembersController.visibleOnline(member),
        ['InGame', 'AppOnline', 'Away'].contains(state),
      );
    }
    expect(
      CommunityOnlineMembersController.visibleOnline(
        CommunityWorkspaceMember.parse({...row, 'online': false}),
      ),
      isFalse,
    );
  });
  test('invalidation drops late reads and cached names', () async {
    final port = WorkspaceTestPort();
    final pending = Completer<CommunityWorkspace>();
    port.reader = (_, _, _) => pending.future;
    final model = CommunityOnlineMembersController(port, 'a' * 32);
    final read = model.refresh();
    port.changes.add(null);
    await Future<void>.delayed(Duration.zero);
    pending.complete(CommunityWorkspace.parse(workspacePayload()));
    await read;
    expect(model.members, isEmpty);
    expect(model.invalidated, isTrue);
    model.dispose();
    await port.changes.close();
  });
  test('wrong organization response cannot populate roster', () async {
    final port = WorkspaceTestPort();
    port.reader = (_, _, _) async =>
        CommunityWorkspace.parse(workspacePayload(target: 'b' * 32));
    final model = CommunityOnlineMembersController(port, 'a' * 32);
    await model.refresh();
    expect(model.members, isEmpty);
    expect(model.error, 'refreshRequired');
    model.dispose();
    await port.changes.close();
  });
  for (final width in [420.0, 1200.0]) {
    testWidgets('all members returns to existing member page $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = ExampleCommunities();
      addTearDown(port.close);
      await tester.pumpWidget(
        host(
          port,
          const Locale('zh', 'CN'),
          target: '00000000000000000000000000000001',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('community-section-chat')));
      await tester.pumpAndSettle();
      if (width == 420) {
        await tester.tap(find.byKey(const Key('community-online-toggle')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('community-all-members')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const Key('community-section-members')),
            )
            .selected,
        isTrue,
      );
      expect(find.byKey(const Key('community-online-members')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [420.0, 1200.0]) {
      testWidgets('online sidebar and draft survive toggles $locale $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1050);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final port = ExampleCommunities();
        addTearDown(port.close);
        await tester.pumpWidget(
          host(port, locale, target: '00000000000000000000000000000001'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('community-section-chat')));
        await tester.pumpAndSettle();
        final toggle = find.byKey(const Key('community-online-toggle'));
        final panel = find.byKey(const Key('community-online-members'));
        final draft = find.byType(TextField);
        await tester.enterText(draft, 'unsent draft');
        if (width == 420) {
          expect(panel, findsNothing);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
        }
        expect(panel, findsOneWidget);
        expect(
          find.descendant(of: panel, matching: find.text('示例组织所有者')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: panel, matching: find.text('C2 Hercules')),
          findsNothing,
        );
        final avatar = find
            .descendant(of: panel, matching: find.byType(UserAvatarMenu))
            .first;
        await tester.tap(avatar);
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsWidgets);
        await tester.tap(avatar);
        await tester.pumpAndSettle();
        if (width == 420) {
          await tester.tap(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(TextButton),
                )
                .last,
          );
        } else {
          await tester.tap(toggle);
        }
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(
          tester.widget<TextField>(draft).controller!.text,
          'unsent draft',
        );
        if (width == 1200) {
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(draft).controller!.text,
            'unsent draft',
          );
          if (locale.countryCode == 'CN') {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('workspace-capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await File('build/community-online-members.png')
                  .writeAsBytes(bytes.buffer.asUint8List());
              image.dispose();
            });
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}
