import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_controller.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'community_workspace_test.dart' show WorkspaceTestPort;
import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> memberRolePayload({String role = ''}) => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'memberRef': 'b' * 32,
  'editRef': 'c' * 32,
  'gameName': '',
  'callsign': '示例成员',
  'roleTitle': role.isEmpty ? '成员' : '领航员',
  'roleKey': role,
  'canAssign': true,
  'roles': <Map<String, Object?>>[
    {'key': 'custom_navigation', 'displayName': '领航员', 'color': '#9B7CFA'},
  ],
};

class MemberRoleFake extends WorkspaceTestPort
    implements CommunityMemberRolePort {
  @override
  bool memberRoleAvailable = true;
  int reads = 0, writes = 0;
  String currentRole = '';
  bool failRefresh = false, mismatch = false, canAssign = true;
  CommunityMemberRoleOutcome outcome = const CommunityMemberRoleOutcome(
    'accepted',
  );
  Completer<CommunityMemberRole>? pendingRead;
  Completer<CommunityMemberRoleOutcome>? pendingWrite;
  final confirmations = <bool>[];
  @override
  Future<CommunityMemberRole> readMemberRole({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) async {
    reads++;
    if (pendingRead != null) return pendingRead!.future;
    if (failRefresh && reads > 1) throw const CommunityFailure('unavailable');
    return CommunityMemberRole.parse(
      memberRolePayload(role: currentRole)
        ..['canAssign'] = canAssign
        ..['memberRef'] = 'b' * 32,
    );
  }

  @override
  Future<CommunityMemberRoleOutcome> saveMemberRole(
    String requestId,
    String editRef,
    String roleKey, {
    bool confirmUncertainRetry = false,
  }) async {
    writes++;
    confirmations.add(confirmUncertainRetry);
    if (pendingWrite != null) return pendingWrite!.future;
    if (outcome.status == 'accepted') currentRole = mismatch ? '' : roleKey;
    return outcome;
  }
}

void main() {
  test('conflict keeps choice and blocks another save until reread', () async {
    final port = MemberRoleFake()
      ..outcome = const CommunityMemberRoleOutcome(
        'rejected',
        error: 'conflict',
      );
    final controller = CommunityMemberRoleController(port, 'a' * 32, 'b' * 32);
    addTearDown(controller.dispose);
    addTearDown(port.changes.close);
    await controller.load();
    controller.select('custom_navigation');
    await controller.save();
    expect(controller.selectedKey, 'custom_navigation');
    expect(controller.error, 'conflict');
    await controller.save();
    expect(port.writes, 1);
    expect(controller.canSave, isFalse);
    await controller.load(discardChanges: true);
    expect(controller.selectedKey, '');
  });
  test(
    'wrong member read is rejected and invalidated late read stays cleared',
    () async {
      final port = MemberRoleFake()
        ..pendingRead = Completer<CommunityMemberRole>();
      final controller = CommunityMemberRoleController(
        port,
        'a' * 32,
        'b' * 32,
      );
      addTearDown(controller.dispose);
      addTearDown(port.changes.close);
      var pending = controller.load();
      port.pendingRead!.complete(
        CommunityMemberRole.parse(
          memberRolePayload()..['memberRef'] = 'e' * 32,
        ),
      );
      await pending;
      expect(controller.snapshot, isNull);
      expect(controller.error, 'dataInvalid');
      port.pendingRead = Completer<CommunityMemberRole>();
      pending = controller.load();
      port.changes.add(null);
      port.pendingRead!.complete(
        CommunityMemberRole.parse(memberRolePayload()),
      );
      await pending;
      expect(controller.snapshot, isNull);
      expect(controller.invalidated, isTrue);
    },
  );
  test('member assignment uses both current capabilities and scoped Bridge payload', () async {
    final host = CommunityHarness(
      capabilities: ['communities.memberRole', 'communities.saveMemberRole'],
      responses: {
        'communities.memberRole': memberRolePayload(),
        'communities.saveMemberRole': {
          'schemaVersion': 1,
          'status': 'accepted',
        },
      },
    );
    addTearDown(host.close);
    expect(host.adapter.memberRoleAvailable, isTrue);
    final read = await host.adapter.readMemberRole(
      targetRef: 'a' * 32,
      memberRef: 'b' * 32,
    );
    expect(
      (await host.adapter.saveMemberRole(
        'd' * 32,
        read.editRef,
        'custom_navigation',
      )).status,
      'accepted',
    );
    expect(host.requests.map((r) => r.name), [
      'account.getCurrent',
      'communities.memberRole',
      'account.getCurrent',
      'communities.saveMemberRole',
    ]);
    expect(host.requests.last.accountContext?.subject, 'test-subject');
    expect(host.requests.last.payload, {
      'schemaVersion': 1,
      'requestId': 'd' * 32,
      'editRef': 'c' * 32,
      'roleKey': 'custom_navigation',
      'confirmUncertainRetry': false,
    });
  });
  test('older Host does not expose assignment and sends nothing', () async {
    final host = CommunityHarness(capabilities: []);
    addTearDown(host.close);
    expect(host.adapter.memberRoleAvailable, isFalse);
    await expectLater(
      host.adapter.readMemberRole(targetRef: 'a' * 32, memberRef: 'b' * 32),
      throwsA(isA<CommunityFailure>()),
    );
    expect(host.requests, isEmpty);
  });
  for (final mutate in <void Function(Map<String, Object?>)>[
    (p) => p['canAssign'] = null,
    (p) => p['memberRef'] = 'raw-id',
    (p) => (p['roles'] as List).add((p['roles'] as List).first),
    (p) => ((p['roles'] as List).first as Map)['key'] = 'fleet_commander',
    (p) => ((p['roles'] as List).first as Map)['color'] = 'bad-color',
  ]) {
    test('malformed assignment projection rejected $mutate', () {
      expect(
        () => CommunityMemberRole.parse(memberRolePayload()..let(mutate)),
        throwsFormatException,
      );
    });
  }
  test(
    'assignment model is immutable and legacy long names are not truncated',
    () {
      final source = memberRolePayload();
      ((source['roles'] as List).first as Map)['displayName'] = '历史名称' * 20;
      final result = CommunityMemberRole.parse(source);
      expect(result.roles.first.name.length, 80);
      expect(() => result.roles.clear(), throwsUnsupportedError);
    },
  );
  test('save requires a changed allowed choice and verifies reread', () async {
    final port = MemberRoleFake();
    final controller = CommunityMemberRoleController(port, 'a' * 32, 'b' * 32);
    addTearDown(controller.dispose);
    addTearDown(port.changes.close);
    await controller.load();
    controller.select('fleet_commander');
    expect(controller.canSave, isFalse);
    controller.select('custom_navigation');
    await controller.save();
    expect(port.writes, 1);
    expect(port.reads, 2);
    expect(controller.saved, isTrue);
    await controller.save();
    expect(port.writes, 1);
    controller.select('');
    await controller.save();
    expect(port.currentRole, '');
  });
  test('unknown write requires reread and explicit consent even with fresh edit reference', () async {
    final port = MemberRoleFake()
      ..outcome = const CommunityMemberRoleOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    final controller = CommunityMemberRoleController(port, 'a' * 32, 'b' * 32);
    addTearDown(controller.dispose);
    addTearDown(port.changes.close);
    await controller.load();
    controller.select('custom_navigation');
    await controller.save();
    await controller.save();
    expect(port.writes, 1);
    expect(controller.needsRefresh, isTrue);
    await controller.load(discardChanges: true);
    controller.select('custom_navigation');
    await controller.save();
    expect(port.writes, 1);
    port.outcome = const CommunityMemberRoleOutcome('accepted');
    await controller.save(confirmUncertainRetry: true);
    expect(controller.saved, isTrue);
    expect(port.confirmations, [false, true]);
  });
  test(
    'accepted but failed refresh cannot resend; explicit reread confirms',
    () async {
      final port = MemberRoleFake()..failRefresh = true;
      final controller = CommunityMemberRoleController(
        port,
        'a' * 32,
        'b' * 32,
      );
      addTearDown(controller.dispose);
      addTearDown(port.changes.close);
      await controller.load();
      controller.select('custom_navigation');
      await controller.save();
      expect(controller.error, 'assignmentRefreshFailed');
      expect(controller.saved, isFalse);
      await controller.save();
      expect(port.writes, 1);
      port.failRefresh = false;
      await controller.load(discardChanges: true);
      expect(controller.saved, isTrue);
    },
  );
  test('changed authoritative role is not reported as saved', () async {
    final port = MemberRoleFake()..mismatch = true;
    final controller = CommunityMemberRoleController(port, 'a' * 32, 'b' * 32);
    addTearDown(controller.dispose);
    addTearDown(port.changes.close);
    await controller.load();
    controller.select('custom_navigation');
    await controller.save();
    expect(controller.saved, isFalse);
    expect(controller.error, 'assignmentChanged');
  });
  test('invalidation clears identity and ignores late assignment', () async {
    final port = MemberRoleFake()
      ..pendingWrite = Completer<CommunityMemberRoleOutcome>();
    final controller = CommunityMemberRoleController(port, 'a' * 32, 'b' * 32);
    addTearDown(controller.dispose);
    addTearDown(port.changes.close);
    await controller.load();
    controller.select('custom_navigation');
    final pending = controller.save();
    await controller.save();
    expect(port.writes, 1);
    port.changes.add(null);
    port.pendingWrite!.complete(const CommunityMemberRoleOutcome('accepted'));
    await pending;
    expect(controller.invalidated, isTrue);
    expect(controller.snapshot, isNull);
    expect(controller.saved, isFalse);
  });
  test('example assignments round trip through the same workspace and stay organization scoped', () async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    final reference = 1.toRadixString(16).padLeft(32, '0');
    final edit = await port.readMemberRole(
      targetRef: '00000000000000000000000000000002',
      memberRef: reference,
    );
    expect(
      (await port.saveMemberRole(
        'test',
        edit.editRef,
        'custom_navigation',
      )).status,
      'accepted',
    );
    expect(
      (await port.readWorkspace(
        '00000000000000000000000000000002',
        '',
        0,
      )).members[1].roleTitle,
      '领航员',
    );
    expect(
      (await port.readWorkspace(
        '00000000000000000000000000000001',
        '',
        0,
      )).members[1].roleTitle,
      '成员',
    );
    expect(
      (await port.readMemberRole(editRef: edit.editRef)).roleKey,
      'custom_navigation',
    );
  });
}

extension on Map<String, Object?> {
  void let(void Function(Map<String, Object?>) action) => action(this);
}
