import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/community_member_override.dart';
import 'package:starbridge_flutter/features/settings/community_member_sharing.dart';
import 'package:starbridge_flutter/features/settings/community_member_visibility_dialog.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';

import 'community_sharing_test.dart'
    show SharingFixture, target, membershipTime;
import 'local_privacy_page_test.dart' show app, viewport;

void main() {
  setUpAll(() async {
    for (final entry in const {
      'Source Sans 3': 'SourceSans3VF-Upright.ttf',
      'Source Han Sans CN': 'SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load('assets/fonts/${entry.value}'))).load();
    }
  });
  test('individual rules round trip without changing legacy JSON shape', () {
    final scope = target('A').choice(fields: 15);
    expect(scope.toJson().containsKey('memberOverrides'), false);
    final restricted = scope.copyWith(
      memberOverrides: [
        CommunityMemberOverride(
          accountId: 'member-0',
          joinedAt: membershipTime,
          fields: 2,
        ),
      ],
    );
    final loaded = CommunitySharingScope.fromJson(restricted.toJson());
    final row = member(0);
    expect(row.effectiveFields(loaded), 2);
    expect(row.effectiveFields(loaded.copyWith(fields: 1)), 0);
    expect(row.effectiveFields(loaded.copyWith(memberOverrides: [])), 15);
    final rejoined = CommunitySharingMember.fromJson({
      ...memberJson(0),
      'joinedAt': '2026-09-13T00:00:00Z',
      'defaultCanView': false,
    });
    expect(rejoined.effectiveFields(loaded), 0);
    expect(
      () => scope.copyWith(
        memberOverrides: [
          CommunityMemberOverride(
            accountId: 'X',
            joinedAt: membershipTime,
            fields: 1,
          ),
          CommunityMemberOverride(
            accountId: 'x',
            joinedAt: membershipTime,
            fields: 2,
          ),
        ],
      ),
      throwsFormatException,
    );
  });

  test('full member directory loads every page once', () async {
    final port = MemberFixture()..count = 205;
    final controller = LocalPrivacyController(port);
    addTearDown(controller.dispose);
    await controller.refresh();
    final rows = await controller.readCommunityMembers(
      target('A').choice(fields: 15),
    );
    expect(rows.length, 205);
    expect(port.offsets, [0, 100, 200]);
  });

  testWidgets(
    'search and member edits are staged and cancellation leaves source untouched',
    (tester) async {
      viewport(tester, const Size(1100, 850));
      final port = MemberFixture()..count = 205;
      final controller = LocalPrivacyController(port);
      addTearDown(controller.dispose);
      await controller.refresh();
      final scope = controller.draft!.communities!.single;
      CommunitySharingScope? result;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<CommunitySharingScope>(
                  context: context,
                  builder: (_) => CommunityMemberVisibilityDialog(
                    controller: controller,
                    target: target('A'),
                    scope: scope,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('privacy-member-search')),
        'Member 204',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('privacy-member-member-204-ship')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('privacy-member-member-204-ship')));
      await tester.pumpAndSettle();
      expect(controller.draft!.communities!.single.memberOverrides, isNull);
      await tester.tap(find.byKey(const Key('privacy-member-confirm')));
      await tester.pumpAndSettle();
      expect(result!.memberOverrides!.single.fields, 13);
      expect(result!.memberOverrides!.single.accountId, 'member-204');
      expect(port.writes, 0);
      expect(port.offsets, [0, 100, 200]);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy-member-member-0-ship')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(controller.draft!.communities!.single.memberOverrides, isNull);
      expect(port.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy conversion requires confirmation and preserves individual denials',
    (tester) async {
      viewport(tester, const Size(1100, 850));
      final port = MemberFixture()..legacyFields = {0: 3, 1: 2};
      final scope = CommunitySharingScope(
        code: 'A',
        joinedAt: membershipTime,
        fields: 3,
        administratorsCanView: false,
        allMembersCanView: false,
        visibilityGroupIds: ['legacy'],
        memberOverrides: [
          CommunityMemberOverride(
            accountId: 'member-0',
            joinedAt: membershipTime,
            fields: 0,
          ),
        ],
      );
      port.settings = port.settings.copyWith(communities: [scope]);
      final controller = LocalPrivacyController(port);
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => editCommunityMemberVisibility(
                context,
                controller,
                target('A'),
                scope,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('privacy-member-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(TextButton, '转换旧范围'));
      await tester.pumpAndSettle();
      expect(controller.draft!.communities!.single.visibilityGroupIds, [
        'legacy',
      ]);
      await tester.tap(find.widgetWithText(FilledButton, '转换旧范围'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy-member-confirm')));
      await tester.pumpAndSettle();
      final changed = controller.draft!.communities!.single;
      expect(changed.visibilityGroupIds, isEmpty);
      expect(
        changed.memberOverrides!.map((r) => '${r.accountId}:${r.fields}'),
        ['member-0:0', 'member-1:2'],
      );
      expect(changed.allMembersCanView, false);
      expect(port.settings.communities!.single.visibilityGroupIds, ['legacy']);
      expect(port.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('member sheet fits narrow windows and large text', (
    tester,
  ) async {
    viewport(tester, const Size(430, 900));
    final controller = LocalPrivacyController(MemberFixture());
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      app(
        CommunityMemberVisibilityDialog(
          controller: controller,
          target: target('A'),
          scope: target('A').choice(fields: 15),
        ),
        textScale: 1.6,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_MEMBER_VISIBILITY')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/member-visibility-narrow.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}

Map<String, Object?> memberJson(int index) => {
  'accountId': 'member-$index',
  'joinedAt': membershipTime,
  'name': 'Member $index',
  'handle': 'Handle_$index',
  'defaultCanView': true,
  'isSelf': false,
  'legacyGroupFields': 0,
};
CommunitySharingMember member(int index) =>
    CommunitySharingMember.fromJson(memberJson(index));

class MemberFixture extends SharingFixture
    implements CommunityMemberSharingPort {
  MemberFixture() {
    settings = LocalPrivacySettings.editorDefaults.copyWith(
      communities: [target('A').choice(fields: 15)],
    );
  }
  int count = 3;
  Map<int, int> legacyFields = {};
  final offsets = <int>[];
  @override
  bool get communityMemberSharingSupported => true;
  @override
  Future<CommunityMemberPage> readCommunityMembers(
    CommunitySharingScope scope, {
    int offset = 0,
    String? revision,
  }) async {
    offsets.add(offset);
    return CommunityMemberPage.fromJson(
      {
        'schemaVersion': 3,
        'code': scope.code,
        'joinedAt': scope.joinedAt,
        'revision': 'A' * 64,
        'offset': offset,
        'total': count,
        'members': [
          for (var i = offset; i < count && i < offset + 100; i++)
            {
              ...memberJson(i),
              'defaultCanView': scope.allMembersCanView,
              'legacyGroupFields': legacyFields[i] ?? 0,
            },
        ],
      },
      scope,
      offset,
      revision,
    );
  }
}
