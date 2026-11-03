import '../common/organization_announcement_management_session_test.dart'
    show FixtureManagementPort;
import 'official_fleet_announcement_actual_wire_test.dart' show hostWire;
import 'official_fleet_governance_test.dart' show governanceWire;
import '../communities/bridge_communities_test.dart' show CommunityHarness;

import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_governance.dart';

import 'package:starbridge_flutter/features/common/organization_communication_port.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import '../communities/community_ships_test.dart' show shipRow;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_overview_port.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final oldHost in [false, true]) {
    testWidgets(
      'official settings consumes the real typed context; old Host=$oldHost',
      (tester) async {
        final host = CommunityHarness(
          capabilities: oldHost ? [] : [BridgeOfficialFleetGovernance.command],
          responses: {
            BridgeOfficialFleetGovernance.command: governanceWire(
              'context-unconfigured',
            ),
          },
        );
        addTearDown(host.close);
        await _pumpFleetShell(
          tester,
          configure: (composition) =>
              composition.officialFleet.communication.configureGovernance(
                owner: host.adapter,
                create: () => BridgeOfficialFleetGovernance(host.adapter),
              ),
        );
        await tester.tap(find.byKey(const ValueKey('/fleet')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('official-fleet-tab-manage')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('official-fleet-settings-nav-permissions')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            Key(oldHost ? 'governance-unavailable' : 'governance-permissions'),
          ),
          findsOneWidget,
        );
        if (!oldHost) {
          expect(
            find.byKey(const Key('governance-root-provider')),
            findsOneWidget,
          );
        }
        expect(
          host.requests
              .where((row) => row.name == BridgeOfficialFleetGovernance.command)
              .length,
          // Entering the fleet asks once for automatic enabling, the page once.
          oldHost ? 0 : 2,
        );
        expect(
          host.requests.any(
            (row) => row.name.contains('manage') || row.name.contains('save'),
          ),
          isFalse,
        );
      },
    );
  }
  testWidgets(
    'departed viewer queries own pending without workspace or positive management',
    (tester) async {
      final port = FixtureManagementPort()
        ..managementAvailable = false
        ..pending = hostWire('lost-ack-02-pending-response');
      await _pumpFleetShell(
        tester,
        fleet: InMemoryOfficialFleetAdapter(
          initial: OfficialFleetSnapshot.notMember(
            freshness: OfficialFleetFreshness.live,
            resourceVersion: 12,
            observedAtUtc: DateTime.utc(2026, 9, 1, 12),
          ),
        ),
        configure: (composition) => composition.officialFleet.communication
            .configureAnnouncementManagement(owner: port, create: () => port),
      );
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('official-fleet-announcement-outcomes')),
      );
      await tester.pumpAndSettle();
      final requestId = port.pending['items'] as List;
      final id = (requestId.single as Map)['requestId'];
      await tester.tap(find.byKey(ValueKey('announcement-query-$id')));
      await tester.pumpAndSettle();
      expect(port.queries.single.$1, id);
      expect(port.editorReads, 0);
      expect(port.managed, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets(
    'directory scroll position survives tab return without row details',
    (tester) async {
      final members = List.generate(
        100,
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
      final search = find.byKey(const Key('official-fleet-members-search'));
      await tester.enterText(search, '测试成员');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final next = find.byKey(const Key('official-fleet-members-next-page'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('第 2 / 2 页'), findsOneWidget);
      final scroll = _memberScroll(tester);
      expect(scroll.maxScrollExtent, greaterThan(460));
      scroll.jumpTo(460);
      await tester.pumpAndSettle();
      final originalOffset = scroll.pixels;
      expect(originalOffset, closeTo(460, 1));
      await tester.tap(find.byKey(const Key('official-fleet-open-details')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-details-close')));
      await tester.pumpAndSettle();
      expect(_memberScroll(tester).pixels, closeTo(originalOffset, 1));
      final ships = find.byKey(const Key('official-fleet-tab-ships'));
      await tester.ensureVisible(ships);
      await tester.tap(ships);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('community-ships-retry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller?.text, '测试成员');
      expect(find.text('第 2 / 2 页'), findsOneWidget);
      expect(_memberScroll(tester).pixels, closeTo(originalOffset, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed search stays editable and can be retried or cleared', (
    tester,
  ) async {
    final port = _FailingSearchPort();
    await _pumpFleetShell(tester, members: port);
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();
    final search = find.byKey(const Key('official-fleet-members-search'));
    await tester.enterText(search, 'temporary');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('official-fleet-members-unavailable')),
      findsOneWidget,
    );
    expect(search, findsOneWidget);
    expect(tester.widget<TextField>(search).controller?.text, 'temporary');
    port.fail = false;
    await tester.ensureVisible(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(port.queries.last.search, 'temporary');
    expect(find.textContaining('已注册成员 · 0'), findsOneWidget);
    expect(find.textContaining('已注册成员 · 0 / 0'), findsNothing);
    expect(
      find.byKey(const Key('official-fleet-members-empty')),
      findsOneWidget,
    );
    await tester.enterText(search, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('official-fleet-members-rows')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid search stays local and clearing it restores normal input',
    (tester) async {
      final port = _FailingSearchPort()..fail = false;
      await _pumpFleetShell(tester, members: port);
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('official-fleet-members-search'));
      final reads = port.queries.length;
      for (final invalid in ['🚀' * 65, 'bad\u0000query']) {
        await tester.enterText(search, invalid);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(port.queries, hasLength(reads));
        expect(find.text('搜索内容过长或含有无效字符。'), findsOneWidget);
        expect(
          find.byKey(const Key('official-fleet-members-rows')),
          findsOneWidget,
        );
      }
      await tester.enterText(search, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(port.queries.last.search, '');
      expect(
        find.byKey(const Key('official-fleet-members-rows')),
        findsOneWidget,
      );
      await tester.enterText(search, '多米诺');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(port.queries.last.search, '多米诺');
      expect(find.text('搜索内容过长或含有无效字符。'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partial source does not claim complete roster or known pagination',
    (tester) async {
      await _pumpFleetShell(tester, members: _PartialMembersPort());
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      expect(find.text('仅显示已注册 SCM 的成员，不代表完整官网名单。'), findsOneWidget);
      expect(find.textContaining('已注册成员'), findsOneWidget);
      expect(find.textContaining('已注册成员 ·'), findsNothing);
      expect(find.text('第 1 页'), findsNothing);
      expect(
        find.byKey(const Key('official-fleet-members-filter-online')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('official-fleet-members-jump-input')),
        findsNothing,
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
    'member query survives tab return and member names never open row details',
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
      await tester.tap(find.byKey(const Key('official-fleet-open-details')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-details-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller?.text, '多米诺');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('official-fleet-members-rows')),
          matching: find.text('多米诺'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('official-fleet-member-details')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('official-fleet-members-rows')),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(search).controller?.text, '多米诺');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown enrollment never becomes presence or a profile target', (
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
    expect(
      find.byKey(const Key('official-fleet-member-details')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('official-fleet-members-rows')),
      findsOneWidget,
    );
    expect(find.text('Mixed_CASE'), findsOneWidget);
    expect(find.text('应用接入状态尚未确认'), findsNothing);
    expect(find.text('状态未知'), findsNothing);
    expect(find.text('服务器'), findsNothing);
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
      expect(find.textContaining('我的官网职位'), findsOneWidget);
      expect(find.text("Aster's Wing"), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('official-fleet-context-header')),
          matching: find.textContaining('Officer · 4★'),
        ),
        findsOneWidget,
      );
      expect(find.text('SCM 最新'), findsOneWidget);
      // Two screens: the top screen offers the sections, none is open yet.
      expect(
        find.byKey(const Key('official-fleet-section-rail')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('official-fleet-members')), findsNothing);
      expect(
        find.byKey(const Key('official-fleet-tab-overview')),
        findsNothing,
      );
      expect(find.byKey(const Key('official-fleet-tab-profile')), findsNothing);
      expect(find.text('本周联合训练安排'), findsNothing);

      await tester.tap(find.byKey(const Key('official-fleet-open-details')));
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

      await tester.tap(find.byKey(const Key('official-fleet-details-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('official-fleet-members')), findsOneWidget);
      expect(
        find.byKey(const Key('official-fleet-members-rows')),
        findsOneWidget,
      );
      expect(find.text('多米诺'), findsOneWidget);
      // This old review fixture supplies only a shard display string;
      // 0.7.1 region presentation never treats it as verified region metadata.
      expect(find.text('暂无可见信息'), findsWidgets);
      expect(find.text('亚洲 · 同服务器'), findsNothing);
      expect(find.text('克拉克'), findsOneWidget);
      expect(find.text('未关联星海舰桥'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared organization header keeps members as the default work surface',
    (tester) async {
      await _pumpFleetShell(
        tester,
        overview: InMemoryOfficialFleetOverviewAdapter.forReview(),
      );
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      // The top screen's holo header shows the announcement.
      expect(
        find.byKey(const Key('official-fleet-header-expand')),
        findsNothing,
      );
      expect(find.text('本周联合训练安排'), findsOneWidget);
      // Unavailable sections stay visible but cannot be opened.
      for (final id in ['channel', 'broadcasts']) {
        final cell = find.byKey(Key('official-fleet-tab-$id'));
        expect(tester.widget<FocusableActionDetector>(cell).enabled, isFalse);
        await tester.tap(cell);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('official-fleet-section-rail')),
          findsOneWidget,
        );
      }
      // The wheel opens the default work surface: members.
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.hover(
          tester.getCenter(find.byKey(const Key('official-fleet-holo-banner'))),
        ),
      );
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('official-fleet-members')), findsOneWidget);
      for (final id in ['channel', 'broadcasts']) {
        expect(
          tester
              .widget<GestureDetector>(find.byKey(Key('official-fleet-tab-$id')))
              .onTap,
          isNull,
        );
      }
      expect(
        find.byKey(const Key('official-fleet-tab-operations')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shared header expands and collapses at minimum width', (
    tester,
  ) async {
    await _pumpFleetShell(
      tester,
      size: const Size(760, 720),
      overview: InMemoryOfficialFleetOverviewAdapter.forReview(),
    );
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    // The top screen clips the header to fit; collapsing opens the section
    // under the slim bar and expanding returns to the top screen.
    expect(find.text('本周联合训练安排'), findsOneWidget);
    await tester.tap(find.byKey(const Key('official-fleet-header-collapse')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('official-fleet-header-compact')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('official-fleet-members')), findsOneWidget);
    await tester.tap(find.byKey(const Key('official-fleet-header-expand')));
    await tester.pumpAndSettle();
    expect(find.text('本周联合训练安排'), findsOneWidget);
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
      find.byKey(const Key('official-fleet-open-details')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-open-details')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('official-fleet-profile-details-unavailable')),
      findsOneWidget,
    );
    expect(find.text('详细舰队资料暂时不可用'), findsOneWidget);
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
      find.byKey(const Key('official-fleet-open-details')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-open-details')));
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
    expect(find.text('成员名单与在线状态即将推出。'), findsOneWidget);
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
    expect(
      find.text('RSI 官网职位'),
      findsWidgets,
      reason: 'The 0.7.1 compact groups retain their field labels',
    );
    expect(find.text('Master · 5★'), findsOneWidget);
    expect(find.text('飞船'), findsWidgets);
    expect(find.text('位置'), findsWidgets);
    expect(find.text('游戏中'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ships tile shows the shared total from one read', (
    tester,
  ) async {
    final port = _SharedShips();
    await _pumpFleetShell(tester, sharedShips: port);
    await tester.tap(find.byKey(const ValueKey('/fleet')));
    await tester.pumpAndSettle();
    expect(find.text('共享 3 艘'), findsOneWidget);
    expect(find.text('还没有成员共享舰船'), findsNothing);
    expect(port.targets, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final width in [760.0, 1280.0]) {
    testWidgets(
      'official ships reuse community fields at $width with actual verified workspace address',
      (tester) async {
        final port = _SharedShips();
        await _pumpFleetShell(
          tester,
          size: Size(width, 1000),
          sharedShips: port,
        );
        await tester.tap(find.byKey(const ValueKey('/fleet')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('official-fleet-tab-ships')),
        );
        await tester.tap(find.byKey(const Key('official-fleet-tab-ships')));
        await tester.pumpAndSettle();
        expect(find.byType(CommunityShipsPanel), findsOneWidget);
        expect(port.targets, isNotEmpty);
        expect(port.targets.toSet(), {'a' * 32});
        expect(find.text('Synthetic shared ship 1'), findsOneWidget);
        expect(find.text('Synthetic holder 1'), findsOneWidget);
        expect(find.textContaining('175'), findsWidgets);
        expect(find.textContaining('运输'), findsWidgets);
        expect(
          find.byType(UserAvatarMenu),
          findsNothing,
          reason:
              'Membership context alone never grants holder profile actions',
        );
        expect(
          find.text('可请求'),
          findsNothing,
          reason: 'No unimplemented borrow authority is fabricated',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'production unavailable adapter never substitutes old example ships',
    (tester) async {
      await _pumpFleetShell(tester);
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-ships')));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityShipsPanel), findsOneWidget);
      expect(find.byKey(const Key('community-ships-retry')), findsOneWidget);
      expect(find.text('克拉克'), findsNothing);
      expect(find.text('Synthetic shared ship 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'all ship scrolling stays within the bounded shared Panel inside the fleet frame',
    (tester) async {
      await _pumpFleetShell(
        tester,
        size: const Size(1280, 1000),
        sharedShips: _SharedShips(),
      );
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-ships')));
      await tester.pumpAndSettle();
      // The redone page (2026-10-29) opens on the card view.
      final row = find.byKey(
        ValueKey('community-ship-card-${1.toRadixString(16).padLeft(32, '0')}'),
      );
      expect(row, findsOneWidget);
      final vertical = find.byWidgetPredicate(
        (w) =>
            w is Scrollable &&
            axisDirectionToAxis(w.axisDirection) == Axis.vertical,
      );
      expect(
        find.ancestor(of: find.byType(CommunityShipsPanel), matching: vertical),
        findsNothing,
        reason:
            'Fleet frame must not wrap the shared Panel in an extra viewport',
      );
      final positions = find
          .ancestor(of: row, matching: vertical)
          .evaluate()
          .map(
            (element) => (element as StatefulElement).state as ScrollableState,
          )
          .map((state) => state.position)
          .toList();
      expect(positions, isNotEmpty);
      for (final position in positions) {
        expect(position.viewportDimension, isPositive);
        expect(position.viewportDimension.isFinite, isTrue);
      }
      expect(tester.takeException(), isNull);
    },
  );
}

ScrollPosition _memberScroll(WidgetTester tester) {
  final rows = find.byKey(const Key('official-fleet-members-rows'));
  final vertical = find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable &&
        axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
  );
  expect(
    find.descendant(of: rows, matching: vertical),
    findsNothing,
    reason: 'Member rows must not create a nested scrolling viewport',
  );
  final owner = find.ancestor(of: rows, matching: vertical);
  expect(owner, findsOneWidget);
  return tester.state<ScrollableState>(owner).position;
}

Future<void> _pumpFleetShell(
  WidgetTester tester, {
  InMemoryOfficialFleetAdapter? fleet,
  OfficialFleetMembersPort? members,
  OfficialFleetOverviewPort? overview,
  CommunityShipsPort? sharedShips,
  Size size = const Size(1280, 800),
  bool signedIn = true,
  void Function(AppComposition)? configure,
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
    officialFleetSharedShipsPort: sharedShips,
    officialFleetCommunicationFactory: sharedShips == null
        ? null
        : (_) => _WorkspaceContext(),
  );
  configure?.call(composition);
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

class _FailingSearchPort implements OfficialFleetMembersPort {
  bool fail = true;
  final queries = <OfficialFleetMemberDirectoryQuery>[];
  final delegate = InMemoryOfficialFleetMembersAdapter.forReview();
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async {
    queries.add(query);
    if (fail && query.search == 'temporary') {
      throw StateError('Transient source failure');
    }
    return delegate.read(query);
  }

  @override
  Future<void> close() async {}
}

// Synthetic authorized public projection only, through the real production
// shared port and parser. Never used by default production composition.
class _SharedShips implements CommunityShipsPort {
  final targets = <String>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    targets.add(targetRef);
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': 2,
      'query': query!.toPayload(),
      'targetRef': targetRef,
      'revision': 'b' * 64,
      'offset': offset,
      'next': null,
      'totalCount': 3,
      'matchedCount': 3,
      'ships': [
        for (var i = 1; i <= 3; i++)
          {
            ...shipRow(),
            'shipRef': i.toRadixString(16).padLeft(32, '0'),
            'displayName': 'Synthetic shared ship $i',
            'ownerCallsign': 'Synthetic holder $i',
            'ownerHasAvatar': false,
            'hasCustomImage': false,
            'ownerOnline': false,
            'ownerLiveStatus': 'Unknown',
            'catalogPriceUsd': '175',
          },
      ],
    });
  }
}

class _WorkspaceContext extends Fake implements OrganizationCommunicationPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get chatAvailable => false;
  @override
  bool get announcementsAvailable => false;
  @override
  Future<OrganizationCommunicationContext> open() async =>
      OrganizationCommunicationContext('a' * 32, 'ASTER');
  @override
  Future<void> close() async {}
}
