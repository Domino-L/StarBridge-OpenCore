import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_profile_port.dart';
import 'package:starbridge_flutter/features/communities/community_roles_port.dart';
import 'package:starbridge_flutter/features/communities/community_roles_controller.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> rolesPayload({int revision = 7}) => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'editRef': 'b' * 32,
  'code': 'A',
  'name': 'Organization A',
  'profileRevision': revision,
  'access': {'canEditRoles': true, 'canAssignMembers': false},
  'roles': [
    for (final (index, key) in [
      'fleet_commander',
      'fleet_deputy_commander',
      'custom_navigation',
    ].indexed)
      <String, Object?>{
        'key': key,
        'displayName': ['负责人', '副负责人', '领航员'][index],
        'description': '',
        'color': '#9B7BFF',
        'sortOrder': index,
        'isSystem': index < 2,
        'isEnabled': true,
        'memberCount': index + 1,
        'permissions': [
          'fleet.profile.edit',
          'announcements.manage',
          'future.preserved',
          'schema.announcements-manage.v1',
        ],
        'createdAt': '2026-09-01T00:00:00Z',
        'updatedAt': '2026-09-07T00:00:00Z',
      },
  ],
};

class RolesFake implements CommunityRolesPort {
  final events = StreamController<void>.broadcast(sync: true);
  int reads = 0, writes = 0;
  bool failRefresh = false, expiredEdits = false;
  int revision = 7;
  List<CommunityRole>? saved;
  final confirmations = <bool>[];
  CommunityProfileOutcome result = const CommunityProfileOutcome(
    'accepted',
    revision: 8,
  );
  Completer<CommunityEditingRoles>? pendingRead;
  Completer<CommunityProfileOutcome>? pendingSave;
  @override
  bool get rolesAvailable => true;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<CommunityEditingRoles> readRoles({
    String? targetRef,
    String? editRef,
  }) async {
    reads++;
    if (expiredEdits && editRef != null) {
      throw const CommunityFailure('refreshRequired');
    }
    if (pendingRead != null) return pendingRead!.future;
    if (reads > 1 && failRefresh) throw const CommunityFailure('unavailable');
    final payload = rolesPayload(revision: revision);
    if (saved != null) {
      payload['roles'] = [
        for (final role in saved!)
          {
            ...role.toDraft(),
            'isSystem': role.system,
            'memberCount': role.memberCount,
            'createdAt': '2026-09-01T00:00:00Z',
            'updatedAt': '2026-09-07T00:00:00Z',
          },
      ];
    }
    return CommunityEditingRoles.parse(payload);
  }

  @override
  Future<CommunityProfileOutcome> saveRoles(
    String requestId,
    String editRef,
    List<CommunityRole> roles, {
    bool confirmUncertainRetry = false,
  }) async {
    writes++;
    confirmations.add(confirmUncertainRetry);
    if (pendingSave != null) return pendingSave!.future;
    if (result.status == 'accepted') {
      saved = roles;
      revision = result.revision!;
    }
    return result;
  }
}

void main() {
  test('automatic role lease renewal preserves unsaved role edits', () async {
    final port = RolesFake()..expiredEdits = true;
    final model = CommunityRolesController(port, 'a' * 32);
    addTearDown(model.dispose);
    await model.load();
    model.select('custom_navigation');
    model.update(name: 'Unsaved role');
    await model.refreshLease();
    expect(port.reads, 2);
    expect(port.writes, 0);
    expect(model.selected!.name, 'Unsaved role');
    expect(model.canSave, isTrue);
    expect(model.invalidated, isFalse);
  });
  test(
    'manual role refresh reacquires a lease instead of reusing expired editRef',
    () async {
      final fake = RolesFake();
      final model = CommunityRolesController(fake, 'a' * 32);
      await model.load();
      fake.expiredEdits = true;
      await model.load();
      expect(model.error, isNull);
      expect(model.invalidated, false);
      expect(fake.reads, 2);
      model.dispose();
      await fake.events.close();
    },
  );
  test(
    'new and renamed roles are short without truncating existing names',
    () async {
      final port = RolesFake();
      final controller = CommunityRolesController(port, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(port.events.close);
      await controller.load();
      expect(controller.update(name: '名' * 13), isFalse);
      expect(controller.update(name: '名' * 12), isTrue);
      expect(controller.update(description: '介' * 81), isFalse);
      expect(controller.update(description: '介' * 80), isTrue);
      expect(controller.update(description: '👩‍🚀' * 80), isTrue);
      expect(controller.update(description: '👩‍🚀' * 81), isFalse);
      final before = controller.roles.length;
      controller.add('名' * 13);
      expect(controller.roles.length, before);
      controller.add('👩‍🚀' * 12);
      expect(controller.roles.length, before + 1);
      final payload = rolesPayload();
      ((payload['roles'] as List).first as Map)['displayName'] = '历史名称' * 10;
      ((payload['roles'] as List).first as Map)['description'] = '历史介绍' * 30;
      expect(
        CommunityEditingRoles.parse(payload).roles.first.name,
        '历史名称' * 10,
      );
      port.saved = CommunityEditingRoles.parse(payload).roles;
      await controller.load(discardChanges: true);
      expect(controller.update(color: '#112233'), isTrue);
      await controller.save();
      expect(port.saved!.first.name, '历史名称' * 10);
      expect(port.saved!.first.description, '历史介绍' * 30);
    },
  );
  test(
    'restoring a permission restores a clean draft regardless of ID order',
    () async {
      final port = RolesFake();
      final controller = CommunityRolesController(port, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(port.events.close);
      await controller.load();
      controller.select('custom_navigation');
      controller.setPermission('announcements.manage', false);
      expect(controller.dirty, isTrue);
      controller.setPermission('announcements.manage', true);
      expect(controller.dirty, isFalse);
    },
  );
  test(
    'Bridge role reads and writes carry current account and only draft fields',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.roles', 'communities.saveRoles'],
        responses: {
          'communities.roles': rolesPayload(),
          'communities.saveRoles': {
            'schemaVersion': 1,
            'status': 'accepted',
            'profileRevision': 8,
          },
        },
      );
      addTearDown(host.close);
      expect(host.adapter.rolesAvailable, isTrue);
      final snapshot = await host.adapter.readRoles(targetRef: 'a' * 32);
      final result = await host.adapter.saveRoles(
        'c' * 32,
        snapshot.editRef,
        snapshot.roles,
      );
      expect(result.status, 'accepted');
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'communities.roles',
        'account.getCurrent',
        'communities.saveRoles',
      ]);
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      final row = (host.requests.last.payload['roles'] as List).first as Map;
      expect(row.containsKey('isSystem'), isFalse);
      expect(row.containsKey('memberCount'), isFalse);
    },
  );
  test('missing role capability hides entry and never dispatches', () async {
    final host = CommunityHarness();
    addTearDown(host.close);
    expect(host.adapter.rolesAvailable, isFalse);
    await expectLater(
      host.adapter.readRoles(targetRef: 'a' * 32),
      throwsA(isA<CommunityFailure>()),
    );
    expect(host.requests, isEmpty);
  });
  test('role projection is immutable and never exposes server-only fields', () {
    final source = rolesPayload();
    final snapshot = CommunityEditingRoles.parse(source);
    expect(snapshot.canAssignMembers, isFalse);
    expect(() => snapshot.roles.clear(), throwsUnsupportedError);
    expect(
      () => snapshot.roles.first.permissions.clear(),
      throwsUnsupportedError,
    );
    expect(snapshot.roles.first.toDraft().containsKey('isSystem'), isFalse);
    expect(snapshot.roles.first.toDraft().containsKey('memberCount'), isFalse);
  });
  for (final mutate in <void Function(Map<String, Object?>)>[
    (v) => v['schemaVersion'] = 2,
    (v) => v['targetRef'] = 'raw-account',
    (v) => v['profileRevision'] = -1,
    (v) => (v['access'] as Map)['canEditRoles'] = false,
    (v) => (v['roles'] as List).add((v['roles'] as List).first),
    (v) => ((v['roles'] as List).first as Map)['description'] = null,
    (v) => ((v['roles'] as List).first as Map)['permissions'] = ['x' * 129],
    (v) => ((v['roles'] as List).first as Map)['memberCount'] = -1,
  ]) {
    test('invalid role projection rejected $mutate', () {
      final source = rolesPayload();
      mutate(source);
      expect(() => CommunityEditingRoles.parse(source), throwsFormatException);
    });
  }
  test(
    'draft operations preserve WPF system seats and hidden grants',
    () async {
      final port = RolesFake();
      final controller = CommunityRolesController(port, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(port.events.close);
      await controller.load();
      expect(controller.setPermission('members.remove', true), isFalse);
      controller.removeSelected();
      expect(controller.roles.length, 3);
      controller.add('Owner copy', copySelected: true);
      expect(controller.roles.length, 3);
      controller.update(name: '组织负责人', color: '#49B5F8');
      expect(controller.dirty, isTrue);
      controller.discard();
      expect(controller.dirty, isFalse);
      controller.select('custom_navigation');
      controller.setPermission('announcements.manage', false);
      expect(controller.selected!.permissions, contains('future.preserved'));
      expect(
        controller.selected!.permissions,
        contains('schema.announcements-manage.v1'),
      );
      expect(
        controller.selected!.permissions,
        isNot(contains('announcements.manage')),
      );
      expect(controller.setPermission('broadcasts.publish', true), isFalse);
      controller.add('领航副本', copySelected: true);
      expect(controller.selected!.memberCount, 0);
      expect(controller.selected!.system, isFalse);
      expect(controller.selected!.permissions, contains('future.preserved'));
      expect(port.writes, 0);
      await controller.save();
      expect(port.writes, 1);
      expect(controller.dirty, isFalse);
      expect(controller.snapshot!.revision, 8);
    },
  );
  test('conflict retains draft; refresh is explicit', () async {
    final port = RolesFake()
      ..result = const CommunityProfileOutcome('rejected', error: 'conflict');
    final controller = CommunityRolesController(port, 'a' * 32);
    addTearDown(controller.dispose);
    addTearDown(port.events.close);
    await controller.load();
    controller.update(name: 'Draft');
    await controller.save();
    expect(controller.error, 'conflict');
    expect(controller.dirty, isTrue);
    expect(controller.canSave, isFalse);
    await controller.load();
    expect(port.reads, 1);
    await controller.load(discardChanges: true);
    expect(controller.dirty, isFalse);
  });
  test(
    'unknown cannot replay after refresh without explicit confirmation',
    () async {
      final port = RolesFake()
        ..result = const CommunityProfileOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
      final controller = CommunityRolesController(port, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(port.events.close);
      await controller.load();
      controller.update(name: 'Draft');
      await controller.save();
      await controller.save();
      expect(port.writes, 1);
      await controller.load(discardChanges: true);
      controller.update(name: 'Reviewed');
      expect(controller.requiresRetryConfirmation, isTrue);
      await controller.save();
      expect(port.writes, 1);
      await controller.save(confirmUncertainRetry: true);
      expect(port.writes, 2);
      expect(port.confirmations.last, isTrue);
    },
  );
  test(
    'accepted receipt with failed reread does not silently clear the draft',
    () async {
      final port = RolesFake()..failRefresh = true;
      final controller = CommunityRolesController(port, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(port.events.close);
      await controller.load();
      controller.update(name: 'Saved draft');
      await controller.save();
      expect(controller.error, 'refreshAfterSave');
      expect(controller.canSave, isFalse);
      expect(controller.dirty, isTrue);
      port.failRefresh = false;
      await controller.load(discardChanges: true);
      expect(controller.selected!.name, 'Saved draft');
      expect(controller.dirty, isFalse);
      expect(port.writes, 1);
    },
  );
  test('late account read cannot restore role data', () async {
    final port = RolesFake()..pendingRead = Completer<CommunityEditingRoles>();
    final controller = CommunityRolesController(port, 'a' * 32);
    addTearDown(controller.dispose);
    addTearDown(port.events.close);
    final pending = controller.load();
    port.events.add(null);
    port.pendingRead!.complete(CommunityEditingRoles.parse(rolesPayload()));
    await pending;
    expect(controller.roles, isEmpty);
    expect(controller.invalidated, isTrue);
  });
  test(
    'concurrent save and late completion never cross account boundaries',
    () async {
      final port = RolesFake()
        ..pendingSave = Completer<CommunityProfileOutcome>();
      final controller = CommunityRolesController(port, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(port.events.close);
      await controller.load();
      controller.update(name: 'Private');
      final pending = controller.save();
      await controller.save();
      expect(port.writes, 1);
      port.events.add(null);
      port.pendingSave!.complete(
        const CommunityProfileOutcome('accepted', revision: 8),
      );
      await pending;
      expect(controller.roles, isEmpty);
      expect(port.reads, 1);
    },
  );
}
