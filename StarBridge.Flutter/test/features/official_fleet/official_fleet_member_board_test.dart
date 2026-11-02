import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_controls.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_section.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_member_views.dart';

import '../friends/social_layout_test.dart' show app, loadFonts;

OfficialFleetMember member(
  String name, {
  OfficialFleetMemberPresence presence = OfficialFleetMemberPresence.offline,
  bool sharingPaused = false,
  OfficialFleetMemberIdentityState identity =
      OfficialFleetMemberIdentityState.starBridge,
}) => OfficialFleetMember(
  memberRef: 'fixture:$name',
  callsign: name,
  gameId: 'game-$name',
  officialRankName: 'Member',
  officialRankValue: 1,
  presence: presence,
  sharingPaused: sharingPaused,
  identityState: identity,
  starBridgeConnected: identity == OfficialFleetMemberIdentityState.starBridge,
  server: const OfficialFleetMemberField.value('hidden server'),
  ship: const OfficialFleetMemberField.value('hidden ship'),
  location: const OfficialFleetMemberField.value('hidden location'),
);

class _PagingPort implements OfficialFleetMembersPort {
  _PagingPort(int count)
    : delegate = InMemoryOfficialFleetMembersAdapter([
        for (var i = 0; i < count; i++) member('Pilot ${'$i'.padLeft(3, '0')}'),
      ]);
  final InMemoryOfficialFleetMembersAdapter delegate;
  final calls = <(OfficialFleetMemberDirectoryQuery, InteractionSource)>[];
  @override
  Stream<void> get invalidations => delegate.invalidations;
  @override
  Future<void> close() => delegate.close();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) {
    calls.add((query, currentStarBridgeActivationSource));
    return delegate.read(query);
  }
}

Future<void> _pagingView(
  WidgetTester tester,
  OfficialFleetMembersModule module,
) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await module.open('officialFleet:7');
  await tester.pumpWidget(
    app(
      SingleChildScrollView(
        child: OfficialFleetMembersSection(
          sourceRef: 'officialFleet:7',
          module: module,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _pagingControl(String name) =>
    find.byKey(Key('official-fleet-members-$name'));

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('unknown totals do not invent a usable paging command', (
    tester,
  ) async {
    final module = createOfficialFleetMembersModule(_PagingPort(3));
    addTearDown(module.dispose);
    for (final total in [null, 0, 1, 3]) {
      final query = OfficialFleetMemberDirectoryQuery(
        sourceRef: 'officialFleet:7',
        pageNumber: total == 1 ? 1 : 2,
      );
      final projection = OfficialFleetMemberDirectoryProjection.fromSnapshot(
        OfficialFleetMemberDirectorySnapshot.available(
          query: query,
          members: const [],
          totalCount: null,
          onlineCount: null,
          inGameCount: null,
          totalPages: total,
        ),
      );
      final pagination = officialFleetMemberPagination(projection, module);
      final multiple = total != null && total > 1;
      expect(pagination.page, multiple ? 2 : isNull);
      expect(pagination.totalPages, multiple ? total : isNull);
      expect(pagination.onJump, multiple ? isNotNull : isNull);
      expect(pagination.onPrevious, multiple ? isNotNull : isNull);
      expect(pagination.onNext, multiple ? isNotNull : isNull);
      expect(pagination.showNavigationWhenDisabled, isTrue);
      expect(pagination.pageSize, 50);
      expect(pagination.onPageSize, isNotNull);
    }
  });

  testWidgets(
    'one page keeps disabled navigation and a working footer page size',
    (tester) async {
      final port = _PagingPort(3);
      final module = createOfficialFleetMembersModule(port);
      addTearDown(module.dispose);
      await _pagingView(tester, module);
      final board = tester.widget<OrganizationMemberBoard>(
        find.byType(OrganizationMemberBoard),
      );
      expect(board.pagination.page, isNull);
      expect(board.pagination.totalPages, isNull);
      expect(board.pagination.onJump, isNull);
      expect(_pagingControl('jump-input'), findsNothing);
      for (final direction in ['previous-page', 'next-page']) {
        expect(
          tester.widget<ButtonStyleButton>(_pagingControl(direction)).onPressed,
          isNull,
        );
      }
      final select = _pagingControl('page-size');
      expect(
        find.descendant(
          of: find.byType(OrganizationMemberPaginationBar),
          matching: select,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(OrganizationMemberToolbar),
          matching: select,
        ),
        findsNothing,
      );
      port.calls.clear();
      await _reveal(tester, select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(find.text('25').last);
      await tester.pumpAndSettle();
      expect(port.calls, hasLength(1));
      expect(port.calls.single.$1.pageSize, 25);
      expect(port.calls.single.$1.pageNumber, 1);
      expect(port.calls.single.$2, InteractionSource.pointer);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('multiple pages retain pointer next and keyboard jump source', (
    tester,
  ) async {
    final port = _PagingPort(120);
    final module = createOfficialFleetMembersModule(port);
    addTearDown(module.dispose);
    await _pagingView(tester, module);
    expect(module.projection.value.totalPages, 3);
    port.calls.clear();
    await _reveal(tester, _pagingControl('next-page'));
    await tester.tap(_pagingControl('next-page'));
    await tester.pumpAndSettle();
    expect(port.calls, hasLength(1));
    expect(port.calls.last.$1.pageNumber, 2);
    expect(port.calls.last.$2, InteractionSource.pointer);
    await _reveal(tester, _pagingControl('jump-input'));
    await tester.enterText(_pagingControl('jump-input'), '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(port.calls, hasLength(2));
    expect(port.calls.last.$1.pageNumber, 3);
    expect(port.calls.last.$2, InteractionSource.keyboard);
    expect(module.projection.value.members, hasLength(20));
    expect(
      tester.widget<ButtonStyleButton>(_pagingControl('next-page')).onPressed,
      isNull,
    );
    final beforeInvalid = port.calls.length;
    await _reveal(tester, _pagingControl('jump-input'));
    await tester.enterText(_pagingControl('jump-input'), '4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(port.calls, hasLength(beforeInvalid));
    expect(module.projection.value.query!.pageNumber, 3);
    await _reveal(tester, _pagingControl('page-size'));
    await tester.tap(_pagingControl('page-size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25').last);
    await tester.pumpAndSettle();
    expect(port.calls, hasLength(beforeInvalid + 1));
    expect(port.calls.last.$1.pageSize, 25);
    expect(port.calls.last.$1.pageNumber, 1);
    expect(port.calls.last.$2, InteractionSource.pointer);
    expect(module.projection.value.totalPages, 5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final hiddenState in [
    OfficialFleetMemberFieldState.notShared,
    OfficialFleetMemberFieldState.restricted,
  ]) {
    testWidgets('withheld location wins over arrival $hiddenState', (
      tester,
    ) async {
      final row = OfficialFleetMember(
        memberRef: 'a' * 64,
        callsign: 'Visible member',
        gameId: '',
        officialRankName: 'Member',
        officialRankValue: 1,
        presence: OfficialFleetMemberPresence.inGame,
        identityState: OfficialFleetMemberIdentityState.starBridge,
        starBridgeConnected: true,
        server: const OfficialFleetMemberField.value('US'),
        serverRegion: 'US',
        hasServerSession: true,
        ship: const OfficialFleetMemberField.value('C2 Hercules'),
        location: OfficialFleetMemberField(
          hiddenState,
          value: 'Private target',
        ),
        arrivalPending: true,
      );
      await tester.pumpWidget(
        app(
          OfficialFleetMemberRow(
            member: row,
            wide: true,
            sourceRef: 'officialFleet:7',
            onOpen: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = tester
          .widget<OrganizationMemberRow>(find.byType(OrganizationMemberRow))
          .entry;
      expect(entry.runtime.location.text, '暂无可见信息');
      expect(entry.runtime.location.isPlaceholder, isTrue);
      expect(find.textContaining('地点待确认'), findsNothing);
      expect(find.textContaining('Private target'), findsNothing);
      expect(find.text('暂无可见信息'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'four identities across three raw states keep identity separate from presence',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final identity in ['visible', 'private', 'unlinked', 'restricted']) {
        for (final raw in [
          OfficialFleetMemberPresence.inGame,
          OfficialFleetMemberPresence.offline,
          OfficialFleetMemberPresence.unknown,
        ]) {
          final linked = identity == 'visible';
          final restricted = identity == 'private' || identity == 'restricted';
          final reference = 'a' * 64;
          final row = OfficialFleetMember(
            memberRef: reference,
            callsign: 'Name $identity',
            gameId: 'Game $identity',
            officialRankName: 'Member',
            officialRankValue: 1,
            presence: raw,
            server: const OfficialFleetMemberField.value('Runtime server'),
            ship: const OfficialFleetMemberField.value('Runtime ship'),
            location: const OfficialFleetMemberField.value('Runtime location'),
            starBridgeConnected: linked ? true : null,
            identityState: linked
                ? OfficialFleetMemberIdentityState.starBridge
                : restricted
                ? OfficialFleetMemberIdentityState.restricted
                : OfficialFleetMemberIdentityState.scm,
            profileTargetRef: linked ? reference : null,
          );
          await tester.pumpWidget(
            app(
              Center(
                child: SizedBox(
                  width: 1250,
                  child: OfficialFleetMemberRow(
                    member: row,
                    wide: true,
                    sourceRef: 'officialFleet:7',
                    onOpen: () => fail('Only the identity may open a menu'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final shared = tester.widget<OrganizationMemberRow>(
            find.byType(OrganizationMemberRow),
          );
          expect(
            shared.entry.presence,
            linked
                ? switch (raw) {
                    OfficialFleetMemberPresence.inGame =>
                      OrganizationMemberPresence.inGame,
                    OfficialFleetMemberPresence.offline =>
                      OrganizationMemberPresence.offline,
                    _ => OrganizationMemberPresence.unknown,
                  }
                : OrganizationMemberPresence.unknown,
            reason: '$identity/$raw',
          );
          expect(
            find.byType(UserAvatarMenu),
            linked ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('资料受限的成员'),
            restricted ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Game $identity'),
            restricted ? findsNothing : findsOneWidget,
          );
          expect(shared.entry.roleColor, isNull);
          expect(shared.entry.actions, isNull);
          expect(find.text('隐身'), findsNothing);
          expect(find.text('未关联'), findsNothing);
          if (!(linked && raw == OfficialFleetMemberPresence.inGame)) {
            expect(find.text('游戏中'), findsNothing);
            expect(find.text('离线'), findsOneWidget);
            expect(find.text('—'), findsNothing);
            expect(find.text('未进入游戏'), findsNWidgets(3));
            for (final field in [
              'Runtime server',
              'Runtime ship',
              'Runtime location',
            ]) {
              expect(find.text(field), findsNothing);
            }
            expect(
              tester.widget<Text>(find.text('离线')).style?.color,
              tester
                  .element(find.byType(OrganizationMemberStatus))
                  .tokens
                  .colors
                  .offline,
            );
            expect(
              [shared.entry.server, shared.entry.ship, shared.entry.location],
              ['未进入游戏', '未进入游戏', '未进入游戏'],
            );
          }
          await tester.tap(find.text('Member · 1★'));
          await tester.pumpAndSettle();
          expect(find.text('查看资料'), findsNothing);
          final status = find.byType(OrganizationMemberStatus);
          await tester.tap(
            find.descendant(of: status, matching: find.byType(Text)),
          );
          await tester.pumpAndSettle();
          expect(find.text('查看资料'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'current fleet source uses the shared board with only identity and RSI rank',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = createOfficialFleetMembersModule(
        InMemoryOfficialFleetMembersAdapter([
          member('SCM member', identity: OfficialFleetMemberIdentityState.scm),
        ]),
      );
      addTearDown(module.dispose);
      await module.open('officialFleet:7');
      await tester.pumpWidget(
        app(
          OfficialFleetMembersSection(
            sourceRef: 'officialFleet:7',
            module: module,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final board = tester.widget<OrganizationMemberBoard>(
        find.byType(OrganizationMemberBoard),
      );
      expect(board.columns.keys, ['member', 'role']);
      expect(board.filters, isEmpty);
      expect(board.onlineCount, isNull);
      expect(board.inGameCount, isNull);
      expect(find.text('RSI 官网职位'), findsOneWidget);
      expect(find.text('服务器'), findsNothing);
      expect(find.byType(OrganizationMemberStatus), findsNothing);
      expect(find.text('未进入游戏'), findsNothing);
      expect(find.text('状态未知'), findsNothing);
      expect(find.text('未关联'), findsNothing);
      expect(find.byType(UserAvatarMenu), findsNothing);
      await tester.tap(find.text('SCM member'));
      await tester.pumpAndSettle();
      expect(module.selectedMemberRef.value, isNull);
      expect(
        find.byKey(const Key('official-fleet-member-details')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'offline, manual offline, invisible and paused in-game rows share public runtime presentation',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = createOfficialFleetMembersModule(
        InMemoryOfficialFleetMembersAdapter(
          [
            member('ordinary'),
            member('manual'),
            member(
              'invisible',
              presence: OfficialFleetMemberPresence.invisible,
            ),
            member(
              'paused',
              presence: OfficialFleetMemberPresence.inGame,
              sharingPaused: true,
            ),
          ],
          runtimeCapabilities:
              const OfficialFleetMemberRuntimeCapabilities.all(),
        ),
      );
      addTearDown(module.dispose);
      await module.open('officialFleet:7');
      await tester.pumpWidget(
        app(
          OfficialFleetMembersSection(
            sourceRef: 'officialFleet:7',
            module: module,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final board = tester.widget<OrganizationMemberBoard>(
        find.byType(OrganizationMemberBoard),
      );
      expect(board.columns.keys, [
        'member',
        'role',
        'server',
        'ship',
        'location',
        'presence',
      ]);
      expect(board.onlineCount, 0);
      expect(board.inGameCount, 0);
      for (final row in board.rows) {
        expect(row.presence, OrganizationMemberPresence.offline);
        expect(
          [row.server, row.ship, row.location],
          ['未进入游戏', '未进入游戏', '未进入游戏'],
        );
        expect(row.roleColor, isNull);
        expect(row.actions, isNull);
      }
      expect(find.text('离线'), findsNWidgets(4));
      expect(find.text('未进入游戏'), findsNWidgets(12));
      expect(find.text('隐身'), findsNothing);
      expect(find.text('共享已暂停'), findsNothing);
      expect(find.text('hidden server'), findsNothing);
      await tester.tap(
        find.byKey(const Key('official-fleet-members-filter-online')),
      );
      await tester.pumpAndSettle();
      expect(module.projection.value.members, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
