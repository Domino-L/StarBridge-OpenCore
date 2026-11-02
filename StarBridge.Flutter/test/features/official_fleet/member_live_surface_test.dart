import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_member_row.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rail_previews.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_section.dart';
import 'package:starbridge_flutter/shared/embedded_avatar.dart';

import '../settings/local_privacy_page_test.dart' show app, viewport;
import 'member_live_refresh_test.dart' show PendingMembers, pilot, source;

OfficialFleetMemberDirectoryProjection page(
  int count, {
  int? total,
  bool presence = true,
}) => OfficialFleetMemberDirectoryProjection.fromSnapshot(
  OfficialFleetMemberDirectorySnapshot.available(
    query: const OfficialFleetMemberDirectoryQuery(sourceRef: source),
    members: [for (var i = 0; i < count; i++) onlinePilot('$i')],
    totalCount: total ?? count,
    onlineCount: null,
    inGameCount: null,
    totalPages: total == null ? 1 : 2,
    runtimeCapabilities: OfficialFleetMemberRuntimeCapabilities(
      presence: presence,
    ),
  ),
);

OfficialFleetMember onlinePilot(String ref) => OfficialFleetMember(
  memberRef: ref,
  callsign: 'Pilot $ref',
  gameId: '',
  officialRankName: null,
  officialRankValue: null,
  presence: ref == '0'
      ? OfficialFleetMemberPresence.inGame
      : OfficialFleetMemberPresence.online,
  server: const OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
  ship: const OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
  location: const OfficialFleetMemberField(
    OfficialFleetMemberFieldState.unknown,
  ),
  starBridgeConnected: true,
  identityState: OfficialFleetMemberIdentityState.starBridge,
);

void main() {
  testWidgets(
    'self local changes update card avatar/count and preserve unchanged row widget',
    (tester) async {
      viewport(tester, const Size(1400, 1000));
      final port = PendingMembers();
      final module = createOfficialFleetMembersModule(port);
      final local = ValueNotifier(
        const OfficialFleetSelfPresence(
          key: 'presence.online',
          sharingAllowed: true,
        ),
      );
      module.bindSelfPresence(local, (_) => local.value);
      final opening = module.open(source);
      addTearDown(() {
        module.dispose();
        local.dispose();
      });
      await tester.pumpWidget(
        app(
          Column(
            children: [
              ValueListenableBuilder<OfficialFleetMemberDirectoryProjection>(
                valueListenable: module.projection,
                builder: (context, members, _) => SizedBox(
                  width: 320,
                  child: OfficialFleetRailPreviews.members(
                    context,
                    members,
                    null,
                    source,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: OfficialFleetMembersSection(
                    sourceRef: source,
                    module: module,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      port.complete(0, [pilot('self'), pilot('other')]);
      await opening;
      await tester.pumpAndSettle();
      final otherRow = find.byKey(const ValueKey('member-row-other'));
      final original = tester.widget<OrganizationMemberRow>(otherRow);
      expect(find.text('游戏中 0 · 在线 1'), findsOneWidget);
      final cardAvatars = find.descendant(
        of: find.byKey(const Key('official-fleet-tile-members')),
        matching: find.byType(EmbeddedAvatar),
      );
      expect(cardAvatars, findsOneWidget);
      local.value = const OfficialFleetSelfPresence(
        key: 'presence.away',
        sharingAllowed: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('游戏中 0 · 在线 0'), findsOneWidget);
      expect(cardAvatars, findsNothing);
      expect(tester.widget(otherRow), same(original));
      local.value = const OfficialFleetSelfPresence(
        key: 'presence.online',
        sharingAllowed: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('游戏中 0 · 在线 1'), findsOneWidget);
      expect(cardAvatars, findsOneWidget);
      local.value = const OfficialFleetSelfPresence(
        key: 'presence.invisible',
        sharingAllowed: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('游戏中 0 · 在线 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final count in [1, 3]) {
    testWidgets(
      'schema2 complete $count-person card uses exact page counts and avatars',
      (tester) async {
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => SizedBox(
                width: 320,
                child: OfficialFleetRailPreviews.members(
                  context,
                  page(count),
                  null,
                  source,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(EmbeddedAvatar), findsNWidgets(count));
        expect(find.text('游戏中 1 · 在线 ${count - 1}'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'partial card shows avatars and enter-all without guessed counts',
    (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => SizedBox(
              width: 320,
              child: OfficialFleetRailPreviews.members(
                context,
                page(3, total: 80),
                null,
                source,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmbeddedAvatar), findsNWidgets(3));
      expect(find.text('进入查看全部'), findsOneWidget);
      expect(find.textContaining('游戏中'), findsNothing);
      expect(find.text('暂时无法显示成员在线状态'), findsNothing);
    },
  );
  testWidgets('missing presence capability keeps unavailable note', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) =>
              OfficialFleetRailPreviews.members(
                context,
                page(1, presence: false),
                null,
                source,
              ) ??
              const Text('暂时无法显示成员在线状态'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法显示成员在线状态'), findsOneWidget);
    expect(find.byType(EmbeddedAvatar), findsNothing);
  });
  testWidgets(
    'runtime update never displays refreshing text but manual refresh does',
    (tester) async {
      viewport(tester, const Size(1400, 1000));
      final port = PendingMembers();
      final module = createOfficialFleetMembersModule(port);
      addTearDown(module.dispose);
      final opening = module.open(source);
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: OfficialFleetMembersSection(
              sourceRef: source,
              module: module,
            ),
          ),
        ),
      );
      await tester.pump();
      port.complete(0, [pilot('self')]);
      await opening;
      await tester.pumpAndSettle();
      port.changes.add(null);
      await tester.pump();
      expect(find.textContaining('正在更新成员'), findsNothing);
      port.complete(1, [pilot('self', name: 'Updated')]);
      await tester.pumpAndSettle();
      expect(find.textContaining('Updated'), findsOneWidget);
      final refresh = module.refresh();
      await tester.pump();
      expect(find.textContaining('正在更新成员'), findsOneWidget);
      port.complete(2, [pilot('self')]);
      await refresh;
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
