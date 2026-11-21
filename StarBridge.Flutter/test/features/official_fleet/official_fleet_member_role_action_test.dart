import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_governance_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_governance_management.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_member_role_dialog.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_section.dart';

import '../friends/social_layout_test.dart' show app;
import 'official_fleet_governance_management_test.dart' show ManagementFake;
import 'official_fleet_governance_test.dart' show governanceWire;

const _source = 'officialFleet:7';

Map<String, Object?> _context({bool delegate = true, bool rally = true}) {
  final row = Map<String, Object?>.from(governanceWire('context-observed'));
  final root = Map<String, Object?>.from(row['rootAuthority'] as Map);
  root['controls'] = [
    {'action': 'activate', 'state': 'denied', 'reason': 'explicitRootControl'},
    {'action': 'recover', 'state': 'allowed', 'reason': 'explicitRootControl'},
    {
      'action': 'delegate',
      'state': delegate ? 'allowed' : 'denied',
      'reason': delegate
          ? 'explicitRootDelegation'
          : 'rootActivationNotCurrent',
    },
  ];
  return {
    ...row,
    'rootAuthority': root,
    if (rally)
      'capabilities': [
        ...(row['capabilities'] as List),
        {
          'capability': 'rally.manage',
          'state': 'denied',
          'reason': 'explicitRootDelegation',
        },
      ],
  };
}

final class _Governance
    implements
        OrganizationGovernancePort,
        OfficialFleetGovernanceManagementProvider {
  _Governance(this.row, {this.failure});
  Map<String, Object?> row;
  Object? failure;
  int reads = 0;
  final changes = StreamController<void>.broadcast(sync: true);
  final fake = ManagementFake();
  @override
  OfficialFleetGovernanceManagementPort get management => fake;
  @override
  bool get available => true;
  @override
  bool get canActivate => true;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<OrganizationGovernanceContext> read(String sourceRef) async {
    reads++;
    if (failure case final error?) throw error;
    return OrganizationGovernanceContext.parse(row, sourceRef);
  }

  @override
  Future<OrganizationActivationOutcome> setActivation(
    String sourceRef, {
    required bool active,
    required String operationId,
    required int expectedPolicyRevision,
  }) async => throw UnimplementedError();

  @override
  Future<void> close() async {}
}

OfficialFleetMember _member(String name, {int? rank = 3, bool self = false}) =>
    OfficialFleetMember(
      memberRef: name * 8,
      callsign: name,
      gameId: 'game-$name',
      officialRankName: 'Member',
      officialRankValue: rank,
      presence: OfficialFleetMemberPresence.offline,
      sharingPaused: false,
      identityState: OfficialFleetMemberIdentityState.starBridge,
      starBridgeConnected: true,
      isSelf: self,
      server: const OfficialFleetMemberField.value('s'),
      ship: const OfficialFleetMemberField.value('s'),
      location: const OfficialFleetMemberField.value('s'),
    );

final _other = _member('other'), _leader = _member('leader', rank: 1);
final _self = _member('myself', self: true);

Finder _menu(OfficialFleetMember member) =>
    find.byKey(ValueKey('member-actions-${member.memberRef}'));

Future<void> _show(WidgetTester tester, _Governance? governance) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final module = createOfficialFleetMembersModule(
    InMemoryOfficialFleetMembersAdapter([_other, _leader, _self]),
  );
  await module.open(_source);
  await tester.pumpWidget(
    app(
      SingleChildScrollView(
        child: OfficialFleetMembersSection(
          sourceRef: _source,
          module: module,
          governance: governance,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a leader gets the menu on other members only', (tester) async {
    final governance = _Governance(_context());
    await _show(tester, governance);
    expect(_menu(_other), findsOneWidget);
    expect(_menu(_leader), findsNothing, reason: 'Other 5★ are fixed');
    expect(_menu(_self), findsNothing, reason: 'A leader keeps its own rights');
    expect(governance.reads, 1, reason: 'One read, none per row');
    expect(governance.fake.reads, isEmpty, reason: 'No read until used');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the menu opens the existing role dialog', (tester) async {
    final governance = _Governance(_context());
    await _show(tester, governance);
    await tester.tap(_menu(_other));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置角色'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<OfficialFleetMemberRoleDialog>(
      find.byType(OfficialFleetMemberRoleDialog),
    );
    expect(dialog.member['memberRef'], _other.memberRef);
    expect(dialog.roles, isNotEmpty);
    expect(
      governance.fake.reads.map((read) => read.$1),
      containsAll(['readRoleTemplates', 'readMemberRoles']),
    );
    expect(tester.takeException(), isNull);
  });

  for (final (name, make) in <(String, _Governance Function())>[
    ('without delegation', () => _Governance(_context(delegate: false))),
    ('on an older relay', () => _Governance(_context(rally: false))),
    (
      'when refused',
      () => _Governance(
        _context(),
        failure: const CommunityFailure('notAllowed'),
      ),
    ),
    (
      'when the read fails',
      () => _Governance(
        _context(),
        failure: const CommunityFailure('unavailable'),
      ),
    ),
  ]) {
    testWidgets('no menu $name', (tester) async {
      await _show(tester, make());
      expect(_menu(_other), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no menu when the Host cannot assign', (tester) async {
    final governance = _Governance(_context());
    governance.fake.commands = {'readMemberRoles', 'readRoleTemplates'};
    await _show(tester, governance);
    expect(_menu(_other), findsNothing);
    expect(governance.reads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no governance port means no menu', (tester) async {
    await _show(tester, null);
    expect(_menu(_other), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lost right takes the menu away', (tester) async {
    final governance = _Governance(_context());
    await _show(tester, governance);
    expect(_menu(_other), findsOneWidget);
    governance.row = _context(delegate: false);
    governance.changes.add(null);
    await tester.pumpAndSettle();
    expect(_menu(_other), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
