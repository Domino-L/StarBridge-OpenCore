import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_governance_settings.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_governance_management.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_governance_workspace.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rank_settings.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_role_editor.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_member_role_dialog.dart';

import '../communities/bridge_communities_test.dart' show CommunityHarness;
import 'official_fleet_governance_management_test.dart'
    show
        ManagementFake,
        AuthorityFake,
        pump,
        pumpDialog,
        sample,
        templates,
        member,
        source,
        target;

void main() {
  test(
    'an incomplete role receipt remains uncertain after null keys drop',
    () async {
      final host = CommunityHarness(
        capabilities: ['officialFleet.manageRoleTemplates'],
        responses: {
          'officialFleet.manageRoleTemplates': {
            'schemaVersion': 1,
            'sourceRef': source,
            'editRef': '1' * 32,
            'requestId': '2' * 32,
            'action': 'create',
            'status': 'accepted',
          },
        },
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetGovernanceManagement(
        host.adapter,
        const Stream.empty(),
      );
      expect(
        await port.write('manageRoleTemplates', source, {
          'editRef': '1' * 32,
          'requestId': '2' * 32,
          'action': 'create',
          'metadata': {
            'displayName': '角色',
            'description': '',
            'color': '#123456',
            'sortOrder': 0,
          },
          'permissions': [],
        }),
        'operationOutcomeUnknown',
      );
    },
  );
  test(
    'member request uses the actual officialFleet.read advertisement',
    () async {
      final host = CommunityHarness(
        capabilities: ['officialFleet.read'],
        responses: {
          'officialFleet.getMembers': {
            'schemaVersion': 1,
            'sourceRef': source,
            'search': '',
            'filter': 'all',
            'pageNumber': 1,
            'pageSize': 25,
            'totalCount': 1,
            'totalPages': 1,
            'coverage': 'scmRegisteredMembers',
            'members': [
              {
                'memberRef': target,
                'callsign': '成员甲',
                'officialRankName': '成员',
                'presence': 'unknown',
              },
            ],
          },
        },
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetGovernanceManagement(
        host.adapter,
        const Stream.empty(),
      );
      expect(port.supports('getMembers'), isTrue);
      final page = await port.read('getMembers', source, {
        'search': '',
        'filter': 'all',
        'pageNumber': 1,
        'pageSize': 25,
      });
      expect(governanceRows(page['members']).single['memberRef'], target);
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'officialFleet.getMembers',
      ]);
    },
  );
  test('held read is fenced when the account generation changes', () async {
    final host = CommunityHarness(
      capabilities: ['officialFleet.readRankPolicy'],
      holdNames: {'officialFleet.readRankPolicy'},
      responses: {'officialFleet.readRankPolicy': sample('cxgov-ranks')},
    );
    addTearDown(host.close);
    final port = BridgeOfficialFleetGovernanceManagement(
      host.adapter,
      const Stream.empty(),
    );
    final pending = port.read('readRankPolicy', source);
    final rejected = expectLater(pending, throwsA(isA<CommunityFailure>()));
    await host.readArrived.future;
    host.session.advanceGeneration(host.session.activeGeneration + 1);
    await rejected;
    expect(
      host.requests.where((r) => r.name == 'officialFleet.readRankPolicy'),
      hasLength(1),
    );
  });
  test(
    'a remote failure after send is uncertain and never replayed by the port',
    () async {
      final host = CommunityHarness(
        capabilities: ['officialFleet.writeRankPolicy'],
        errors: {'officialFleet.writeRankPolicy': 'communities.unavailable'},
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetGovernanceManagement(
        host.adapter,
        const Stream.empty(),
      );
      expect(
        await port.write('writeRankPolicy', source, {
          'operationId': 'same-intent',
          'expectedPolicyRevision': 12,
          'rows': sample('cxgov-ranks')['rows'],
        }),
        'operationOutcomeUnknown',
      );
      expect(
        host.requests.where((r) => r.name == 'officialFleet.writeRankPolicy'),
        hasLength(1),
      );
    },
  );
  test(
    'port rejects extra client-claimed authority before account admission',
    () async {
      final host = CommunityHarness(
        capabilities: ['officialFleet.writeRankPolicy'],
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetGovernanceManagement(
        host.adapter,
        const Stream.empty(),
      );
      await expectLater(
        port.write('writeRankPolicy', source, {
          'operationId': 'op',
          'expectedPolicyRevision': 12,
          'rows': [],
          'rank': 1,
        }),
        throwsA(isA<CommunityFailure>()),
      );
      expect(host.requests, isEmpty);
    },
  );
  testWidgets('new Host with old relay hides all management sections', (
    tester,
  ) async {
    final port = ManagementFake()..pages.remove('readRankPolicy');
    addTearDown(port.changes.close);
    final authority = AuthorityFake(port, delegate: true, audit: true);
    await pump(
      tester,
      OfficialFleetGovernanceWorkspace(
        port: authority,
        source: source,
        onAuthorityRead: (_) {},
        builder: (panes, accept, unavailable) => Column(
          children: [
            TextButton(
              onPressed: () async => accept(await authority.read(source)),
              child: const Text('读取'),
            ),
            for (final pane in panes) Text(pane.id),
          ],
        ),
      ),
    );
    await tester.tap(find.text('读取'));
    await tester.pumpAndSettle();
    expect(find.text('roles'), findsNothing);
    expect(find.text('ranks'), findsNothing);
    expect(find.text('audit'), findsNothing);
    expect(port.reads.map((r) => r.$1), ['readRankPolicy']);
  });
  for (final capability in [
    'readRankPolicy',
    'readMemberRoles',
    'readGovernanceAudit',
  ]) {
    testWidgets(
      'each section requires its matching Host capability: $capability',
      (tester) async {
        final port = ManagementFake()
          ..commands = {
            'readRankPolicy',
            'readMemberRoles',
            'readGovernanceAudit',
          }
          ..commands!.remove(capability);
        addTearDown(port.changes.close);
        final authority = AuthorityFake(port, delegate: true, audit: true);
        await pump(
          tester,
          OfficialFleetGovernanceWorkspace(
            port: authority,
            source: source,
            onAuthorityRead: (_) {},
            builder: (panes, accept, unavailable) => Column(
              children: [
                TextButton(
                  onPressed: () async => accept(await authority.read(source)),
                  child: const Text('读取'),
                ),
                for (final pane in panes) Text(pane.id),
              ],
            ),
          ),
        );
        await tester.tap(find.text('读取'));
        await tester.pumpAndSettle();
        final id = {
          'readRankPolicy': 'ranks',
          'readMemberRoles': 'roles',
          'readGovernanceAudit': 'audit',
        }[capability]!;
        expect(find.text(id), findsNothing);
      },
    );
  }
  testWidgets('rank conflict rereads table and authority and says so', (
    tester,
  ) async {
    final port = ManagementFake()..outcomes.add('conflict');
    addTearDown(port.changes.close);
    var reads = 0;
    await pump(
      tester,
      OfficialFleetRankSettings(
        port: port,
        source: source,
        initial: sample('cxgov-ranks'),
        onAuthorityRead: () async {
          ++reads;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('rank-save')));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(port.reads.single.$1, 'readRankPolicy');
    expect(find.textContaining('已重新读取'), findsOneWidget);
  });
  testWidgets(
    'rank unknown retry retains id and revision while draft is locked',
    (tester) async {
      final port = ManagementFake()
        ..outcomes.addAll(['operationOutcomeUnknown', 'duplicate']);
      addTearDown(port.changes.close);
      await pump(
        tester,
        OfficialFleetRankSettings(
          port: port,
          source: source,
          initial: sample('cxgov-ranks'),
          onAuthorityRead: () async {},
        ),
      );
      await tester.tap(find.byKey(const Key('rank-save')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('rank-2-rally')))
            .onChanged,
        isNull,
      );
      expect(find.text('重试原操作'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rank-save')));
      await tester.pumpAndSettle();
      expect(port.writes[0].$1, port.writes[1].$1);
      expect(port.writes[0].$2, port.writes[1].$2);
    },
  );
  testWidgets('changing settings panes preserves an uncertain rank intent', (
    tester,
  ) async {
    final port = ManagementFake()
      ..outcomes.addAll(['operationOutcomeUnknown', 'duplicate']);
    addTearDown(port.changes.close);
    final authority = AuthorityFake(port);
    // This frame has a bounded parent; content panes themselves scroll.
    await pump(
      tester,
      SizedBox(
        height: 900,
        child: OrganizationGovernanceSettings(
          port: authority,
          sourceRef: source,
          name: '舰队',
          onBack: () async {},
          initialPane: 'ranks',
          panesBefore: [
            OrganizationGovernancePane(
              id: 'ranks',
              retainState: true,
              icon: StandardIconSemantic.adminPanelSettings,
              builder: (_) => OfficialFleetRankSettings(
                port: port,
                source: source,
                initial: sample('cxgov-ranks'),
                onAuthorityRead: () async {},
              ),
            ),
          ],
          label: (key) => key,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('rank-save')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('official-fleet-settings-nav-permissions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('official-fleet-settings-nav-ranks')),
    );
    await tester.pumpAndSettle();
    expect(find.text('重试原操作'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rank-save')));
    await tester.pumpAndSettle();
    expect(port.writes[0].$1, port.writes[1].$1);
    expect(port.writes[0].$2, port.writes[1].$2);
  });
  testWidgets('discarding a new role sends no write', (tester) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    await pumpDialog(
      tester,
      OfficialFleetRoleEditor(
        port: port,
        source: source,
        page: templates(),
        onChanged: () async {},
      ),
    );
    await tester.enterText(find.byKey(const Key('role-name')), '未保存');
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(port.writes, isEmpty);
    expect(find.byKey(const Key('role-name')), findsNothing);
  });
  testWidgets('assign unknown retry keeps grant id and activation binding', (
    tester,
  ) async {
    final port = ManagementFake()
      ..outcomes.addAll(['operationOutcomeUnknown', 'duplicate']);
    addTearDown(port.changes.close);
    await pumpDialog(
      tester,
      OfficialFleetMemberRoleDialog(
        port: port,
        source: source,
        member: member(),
        roles: governanceRows(templates()['roles']),
        onChanged: (_) async {},
        onAuthorityRead: () async {},
      ),
    );
    await tester.tap(find.byKey(const Key('member-role-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('召集员').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-role-assign')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试原操作'));
    await tester.pumpAndSettle();
    expect(port.writes[0].$1, port.writes[1].$1);
    expect(port.writes[0].$2, port.writes[1].$2);
    expect(port.writes.first.$2['targetRef'], target);
  });
}
