import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_overview_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_port.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signed-out fleet identifies the SCM account source', (
    tester,
  ) async {
    await _pumpFleetShell(tester, signedIn: false);
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('official-fleet-scm-brand')), findsOneWidget);
    expect(find.text('登录后查看官网舰队'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory scroll position survives detail and tab return', (
    tester,
  ) async {
    final members = List.generate(
      50,
      (index) => OfficialFleetMember(
        memberRef: 'test-member:$index',
        callsign: '测试成员${index.toString().padLeft(2, '0')}',
        gameId: 'Test_$index',
        officialRankName: null,
        officialRankValue: null,
        presence: OfficialFleetMemberPresence.away,
        server: const OfficialFleetMemberField(
          OfficialFleetMemberFieldState.notShared,
        ),
        ship: const OfficialFleetMemberField(
          OfficialFleetMemberFieldState.notShared,
        ),
        location: const OfficialFleetMemberField(
          OfficialFleetMemberFieldState.notShared,
        ),
        starBridgeConnected: true,
      ),
    );
    await _pumpFleetShell(
      tester,
      members: InMemoryOfficialFleetMembersAdapter(members),
      size: const Size(1000, 1000),
    );
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();
    final list = find.byKey(const Key('official-fleet-members-virtual-list'));
    tester.widget<ListView>(list).controller!.jumpTo(460);
    await tester.pumpAndSettle();
    final originalOffset = tester.widget<ListView>(list).controller!.offset;
    await tester.tap(
      find
          .descendant(of: list, matching: find.byType(InkWell))
          .hitTestable()
          .first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('official-fleet-member-details')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('official-fleet-member-details-close')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListView>(list).controller!.offset,
      closeTo(originalOffset, 1),
    );
    await tester.tap(find.byKey(const Key('official-fleet-tab-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListView>(list).controller!.offset,
      closeTo(originalOffset, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'partial source does not claim complete roster or known pagination',
    (tester) async {
      await _pumpFleetShell(tester, members: _PartialMembersPort());
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      expect(find.text('仅显示已注册 SCM 的成员，不代表完整官网名单。'), findsOneWidget);
      expect(find.text('第 1 / — 页'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const Key('official-fleet-members-filter-online')),
            )
            .onSelected,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('official-fleet-members-next-page')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'member query survives tab return and narrow detail has a return path',
    (tester) async {
      await _pumpFleetShell(tester, size: const Size(1000, 1000));
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('official-fleet-members-search'));
      await tester.enterText(search, '多米诺');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller?.text, '多米诺');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('official-fleet-members-virtual-list')),
          matching: find.text('多米诺'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('official-fleet-member-details')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('official-fleet-members-virtual-list')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('official-fleet-member-details-close')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('official-fleet-members-virtual-list')),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(search).controller?.text, '多米诺');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown enrollment and rank remain unknown in wide details', (
    tester,
  ) async {
    const member = OfficialFleetMember(
      memberRef: 'member:unknown',
      callsign: '成员',
      gameId: 'Mixed_CASE',
      officialRankName: null,
      officialRankValue: null,
      presence: OfficialFleetMemberPresence.unknown,
      server: OfficialFleetMemberField(OfficialFleetMemberFieldState.notShared),
      ship: OfficialFleetMemberField(OfficialFleetMemberFieldState.restricted),
      location: OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
      starBridgeConnected: null,
    );
    await _pumpFleetShell(
      tester,
      size: const Size(1920, 1080),
      members: const InMemoryOfficialFleetMembersAdapter([member]),
    );
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('official-fleet-member-member:unknown')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('official-fleet-member-details')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('official-fleet-members-virtual-list')),
      findsOneWidget,
    );
    expect(find.text('(Mixed_CASE)'), findsWidgets);
    expect(find.text('应用接入状态尚未确认'), findsOneWidget);
    expect(find.text('状态未知'), findsWidgets);
    expect(find.textContaining('null'), findsNothing);
    expect(find.text('离线'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renders RSI membership via SCM without inventing StarBridge data',
    (tester) async {
      await _pumpFleetShell(tester);
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('official-fleet-context-header')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('official-fleet-rank-spine')), findsNothing);
      expect(
        find.byKey(const Key('official-fleet-my-official-position')),
        findsOneWidget,
      );
      expect(find.text('我的官网职位'), findsOneWidget);
      expect(find.text("Aster's Wing"), findsOneWidget);
      expect(find.text('Officer · 4★'), findsOneWidget);
      expect(find.text('SCM 最新'), findsOneWidget);
      expect(
        find.byKey(const Key('official-fleet-overview-unavailable')),
        findsOneWidget,
      );
      expect(find.text('协作概览暂时不可用'), findsOneWidget);
      expect(find.text('本周联合训练安排'), findsNothing);
      expect(find.text('0'), findsNothing);

      await tester.tap(find.byKey(const Key('official-fleet-tab-profile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('official-fleet-profile')), findsOneWidget);
      expect(find.text('1286 名官网成员'), findsOneWidget);
      expect(find.text('RSI 官网公开简介'), findsOneWidget);
      expect(find.text('SCM 补充介绍'), findsOneWidget);
      expect(find.text('主要方向'), findsOneWidget);
      expect(find.text('探索'), findsOneWidget);
      expect(find.text('StarBridge 角色 · 行动协调员'), findsOneWidget);
      expect(find.text('officialFleet:7'), findsNothing);
      expect(find.text('舰队资源版本'), findsNothing);

      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('official-fleet-members')), findsOneWidget);
      expect(
        find.byKey(const Key('official-fleet-members-virtual-list')),
        findsOneWidget,
      );
      expect(find.text('多米诺'), findsOneWidget);
      expect(find.text('亚洲 · 同服务器'), findsOneWidget);
      expect(find.text('克拉克'), findsOneWidget);
      expect(find.text('尚未接入 StarBridge'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review overview renders actionable fleet facts without SCM mix',
    (tester) async {
      await _pumpFleetShell(
        tester,
        overview: InMemoryOfficialFleetOverviewAdapter.forReview(),
      );
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('official-fleet-current-announcement')),
        findsOneWidget,
      );
      expect(find.text('本周联合训练安排'), findsOneWidget);
      expect(find.text('官网成员'), findsOneWidget);
      expect(find.text('1286'), findsOneWidget);
      expect(find.text('可见在线'), findsOneWidget);
      expect(find.text('38'), findsOneWidget);
      expect(find.text('需要处理'), findsOneWidget);
      expect(
        find.byKey(const Key('official-fleet-overview-task-members')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('official-fleet-overview-task-members')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('official-fleet-members')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('review overview preserves its hierarchy at minimum width', (
    tester,
  ) async {
    await _pumpFleetShell(
      tester,
      size: const Size(760, 720),
      overview: InMemoryOfficialFleetOverviewAdapter.forReview(),
    );
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('official-fleet-current-announcement')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('official-fleet-overview-snapshot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('official-fleet-overview-tasks')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an explicit no-membership state', (tester) async {
    await _pumpFleetShell(
      tester,
      fleet: InMemoryOfficialFleetAdapter(
        initial: OfficialFleetSnapshot.notMember(
          freshness: OfficialFleetFreshness.live,
          resourceVersion: 12,
          observedAtUtc: DateTime.utc(2026, 9, 1, 12),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('official-fleet-not-member')), findsOneWidget);
    expect(find.text('尚未加入 RSI 官网舰队'), findsOneWidget);
  });

  testWidgets('keeps unconnected profile fields explicit in production state', (
    tester,
  ) async {
    await _pumpFleetShell(
      tester,
      fleet: InMemoryOfficialFleetAdapter(
        initial: OfficialFleetSnapshot.available(
          fleet: const OfficialFleetSummary(
            sourceRef: 'officialFleet:9',
            sid: 'NORTH',
            name: 'Northwind',
            officialRankName: 'Member',
            officialRankValue: 1,
          ),
          freshness: OfficialFleetFreshness.live,
          resourceVersion: 3,
          observedAtUtc: DateTime.utc(2026, 9, 1, 12),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('official-fleet-tab-profile')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-tab-profile')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('official-fleet-profile-details-unavailable')),
      findsOneWidget,
    );
    expect(find.text('详细舰队资料尚未接入'), findsOneWidget);
    expect(find.text('officialFleet:9'), findsNothing);
    expect(find.text('舰队资源版本'), findsNothing);
  });

  testWidgets('profile preserves readable order at the minimum content width', (
    tester,
  ) async {
    await _pumpFleetShell(tester, size: const Size(760, 720));
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('official-fleet-tab-profile')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-tab-profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('official-fleet-profile')), findsOneWidget);
    expect(find.text('舰队介绍'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('production member state never substitutes sample roster data', (
    tester,
  ) async {
    await _pumpFleetShell(
      tester,
      members: UnavailableOfficialFleetMembersAdapter(),
    );
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('official-fleet-members-unavailable')),
      findsOneWidget,
    );
    expect(find.text('成员目录暂时不可用'), findsOneWidget);
    expect(find.text('多米诺'), findsNothing);
  });

  testWidgets('member banners retain every field at the minimum width', (
    tester,
  ) async {
    await _pumpFleetShell(tester, size: const Size(760, 720));
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('official-fleet-tab-members')),
    );
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();

    expect(find.text('服务器'), findsWidgets);
    expect(find.text('RSI 官网职位'), findsWidgets);
    expect(find.text('舰船'), findsWidgets);
    expect(find.text('位置'), findsWidgets);
    expect(find.text('游戏中'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review ship library preserves WPF information density', (
    tester,
  ) async {
    await _pumpFleetShell(
      tester,
      ships: InMemoryOfficialFleetShipsAdapter.forReview(),
    );
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('official-fleet-tab-ships')),
    );
    await tester.tap(find.byKey(const Key('official-fleet-tab-ships')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('official-fleet-ships')), findsOneWidget);
    expect(
      find.byKey(const Key('official-fleet-ships-size-distribution')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('official-fleet-ships-virtual-list')),
      findsOneWidget,
    );
    expect(find.text('共享舰船'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('秃鹫'), findsOneWidget);
    expect(find.text('\$175'), findsOneWidget);
    expect(
      find.byKey(const Key('official-fleet-ship-layout-dense-ship:vulture-1')),
      findsOneWidget,
    );
    expect(find.text('克拉克'), findsOneWidget);
    expect(find.text('Anvil Carrack'), findsOneWidget);
    expect(find.text('\$600'), findsOneWidget);
    expect(find.text('铁甲突袭'), findsOneWidget);
    expect(find.text('由我共享'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('production ship library never substitutes sample ships', (
    tester,
  ) async {
    await _pumpFleetShell(tester);
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('official-fleet-tab-ships')),
    );
    await tester.tap(find.byKey(const Key('official-fleet-tab-ships')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('official-fleet-ships-unavailable')),
      findsOneWidget,
    );
    expect(find.text('克拉克'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ship library keeps all domain fields at compact width', (
    tester,
  ) async {
    await _pumpFleetShell(
      tester,
      size: const Size(760, 720),
      ships: InMemoryOfficialFleetShipsAdapter.forReview(),
    );
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('official-fleet-tab-ships')),
    );
    await tester.tap(find.byKey(const Key('official-fleet-tab-ships')));
    await tester.pumpAndSettle();

    expect(find.text('舰级构成'), findsOneWidget);
    expect(find.text('大型 2'), findsOneWidget);
    expect(find.text('秃鹫'), findsOneWidget);
    expect(find.text('打捞'), findsOneWidget);
    expect(find.text('远航者'), findsOneWidget);
    expect(find.text('可飞'), findsWidgets);
    expect(find.text('可请求'), findsWidgets);
    expect(
      find.byKey(
        const Key('official-fleet-ship-layout-compact-ship:vulture-1'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop ship grid aligns columns and fills tall workspaces', (
    tester,
  ) async {
    await _pumpFleetShell(
      tester,
      size: const Size(1280, 1000),
      ships: InMemoryOfficialFleetShipsAdapter.forReview(),
    );
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-tab-ships')));
    await tester.pumpAndSettle();

    final shipList = find.byKey(const Key('official-fleet-ships-virtual-list'));
    expect(tester.getSize(shipList).height, greaterThanOrEqualTo(530));
    final vultureOwnerX = tester.getTopLeft(find.text('Citizen-2802')).dx;
    final polarisOwnerX = tester.getTopLeft(find.text('Citizen-2803')).dx;
    expect(vultureOwnerX, closeTo(polarisOwnerX, 0.1));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFleetShell(
  WidgetTester tester, {
  InMemoryOfficialFleetAdapter? fleet,
  OfficialFleetMembersPort? members,
  OfficialFleetOverviewPort? overview,
  OfficialFleetShipsPort? ships,
  Size size = const Size(1280, 800),
  bool signedIn = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final composition = AppComposition.forTest(
    windowChrome: InMemoryWindowChrome(),
    accountPort: InMemoryAccountAdapter.forReview(
      signedIn ? AccountReviewState.signedIn : AccountReviewState.signedOut,
    ),
    officialFleetPort:
        fleet ?? InMemoryOfficialFleetAdapter.forReview(signedIn: signedIn),
    officialFleetMembersPort:
        members ?? InMemoryOfficialFleetMembersAdapter.forReview(),
    officialFleetOverviewPort:
        overview ?? UnavailableOfficialFleetOverviewAdapter(),
    officialFleetShipsPort: ships,
  );
  await tester.pumpWidget(StarBridgeApp(composition: composition));
  await tester.pumpAndSettle();
}

class _PartialMembersPort implements OfficialFleetMembersPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async => OfficialFleetMemberDirectorySnapshot.available(
    query: query,
    members: const [],
    totalCount: null,
    onlineCount: null,
    inGameCount: null,
    totalPages: null,
    coverage: OfficialFleetRosterCoverage.scmRegisteredMembers,
  );
  @override
  Future<void> close() async {}
}
