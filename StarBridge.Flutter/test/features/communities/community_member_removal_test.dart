import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_member_removal_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_removal_controller.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'community_workspace_test.dart' show WorkspaceTestPort;
import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> removalPayload() => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'memberRef': 'b' * 32,
  'editRef': 'c' * 32,
  'gameName': '',
  'callsign': '示例成员',
  'roleTitle': '成员',
  'canRemove': true,
};

class RemovalFake extends WorkspaceTestPort
    implements CommunityMemberRemovalPort {
  @override
  bool memberRemovalAvailable = true;
  int reads = 0, writes = 0;
  bool removed = false, canRemove = true;
  String? readError;
  CommunityMemberRemovalOutcome outcome = const CommunityMemberRemovalOutcome(
    'accepted',
  );
  Completer<CommunityMemberRemoval>? pendingRead;
  Completer<CommunityMemberRemovalOutcome>? pendingWrite;
  final confirmations = <bool>[];
  @override
  Future<CommunityMemberRemoval> readMemberRemoval({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) async {
    reads++;
    if (pendingRead != null) return pendingRead!.future;
    if (readError != null) throw CommunityFailure(readError!);
    return CommunityMemberRemoval.parse(
      removalPayload()..['canRemove'] = canRemove,
    );
  }

  @override
  Future<CommunityMemberRemovalOutcome> removeMember(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  }) async {
    writes++;
    confirmations.add(confirmUncertainRetry);
    if (pendingWrite != null) return pendingWrite!.future;
    if (outcome.status == 'accepted') removed = true;
    return outcome;
  }
}

void main() {
  test(
    'Bridge requires removal capabilities and sends only scoped confirmation',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.memberRemoval', 'communities.removeMember'],
        responses: {
          'communities.memberRemoval': removalPayload(),
          'communities.removeMember': {
            'schemaVersion': 1,
            'status': 'accepted',
          },
        },
      );
      addTearDown(host.close);
      expect(host.adapter.memberRemovalAvailable, isTrue);
      final member = await host.adapter.readMemberRemoval(
        targetRef: 'a' * 32,
        memberRef: 'b' * 32,
      );
      expect(
        (await host.adapter.removeMember('d' * 32, member.editRef)).status,
        'accepted',
      );
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'communities.memberRemoval',
        'account.getCurrent',
        'communities.removeMember',
      ]);
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'requestId': 'd' * 32,
        'editRef': 'c' * 32,
        'confirmUncertainRetry': false,
      });
    },
  );
  test(
    'old Host does not advertise action or send unsupported removal',
    () async {
      final host = CommunityHarness(capabilities: ['communities.commands']);
      addTearDown(host.close);
      expect(host.adapter.memberRemovalAvailable, isFalse);
      expect(
        (await host.adapter.removeMember('d' * 32, 'c' * 32)).error,
        'unavailable',
      );
      expect(host.requests, isEmpty);
    },
  );
  for (final (field, value) in <(String, Object?)>[
    ('schemaVersion', 2),
    ('canRemove', 'yes'),
    ('memberRef', 'raw-account-id'),
    ('callsign', 'bad\nname'),
    ('private', 'x' * (16 * 1024)),
  ]) {
    test('reject malformed removal projection $field', () {
      expect(
        () => CommunityMemberRemoval.parse(removalPayload()..[field] = value),
        throwsFormatException,
      );
    });
  }
  test('malformed successful receipt is unknown, never confirmed', () async {
    final host = CommunityHarness(
      capabilities: ['communities.removeMember'],
      responses: {
        'communities.removeMember': {'schemaVersion': 2, 'status': 'accepted'},
      },
    );
    addTearDown(host.close);
    expect(
      (await host.adapter.removeMember('d' * 32, 'c' * 32)).status,
      'unknown',
    );
  });
  test(
    'reading does not remove, accepted command cannot be repeated',
    () async {
      final port = RemovalFake();
      final model = CommunityMemberRemovalController(port, 'a' * 32, 'b' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      expect(port.writes, 0);
      await model.remove();
      await model.remove();
      expect(model.removed, isTrue);
      expect(port.writes, 1);
    },
  );
  test(
    'unknown requires fresh read and explicit retry, not merely a new request',
    () async {
      final port = RemovalFake()
        ..outcome = const CommunityMemberRemovalOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
      final model = CommunityMemberRemovalController(port, 'a' * 32, 'b' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      await model.remove();
      await model.remove(confirmUncertainRetry: true);
      expect(port.writes, 1);
      await model.load();
      await model.remove();
      expect(port.writes, 1);
      port.outcome = const CommunityMemberRemovalOutcome('accepted');
      await model.remove(confirmUncertainRetry: true);
      expect(model.removed, isTrue);
      expect(port.confirmations, [false, true]);
    },
  );
  for (final failure in [
    'conflict',
    'notAllowed',
    'refreshRequired',
    'identityUnavailable',
  ]) {
    test('failed removal stays unconfirmed: $failure', () async {
      final port = RemovalFake()
        ..outcome = CommunityMemberRemovalOutcome('rejected', error: failure);
      final model = CommunityMemberRemovalController(port, 'a' * 32, 'b' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      await model.remove();
      expect(model.removed, isFalse);
      expect(model.canRemove, isFalse);
      expect(model.snapshot == null, failure != 'conflict');
    });
  }
  test('account change clears late read and concurrent late removal', () async {
    final port = RemovalFake()
      ..pendingRead = Completer<CommunityMemberRemoval>();
    var model = CommunityMemberRemovalController(port, 'a' * 32, 'b' * 32);
    addTearDown(port.changes.close);
    var pending = model.load();
    port.changes.add(null);
    port.pendingRead!.complete(CommunityMemberRemoval.parse(removalPayload()));
    await pending;
    expect(model.snapshot, isNull);
    model.dispose();
    port.pendingRead = null;
    port.pendingWrite = Completer<CommunityMemberRemovalOutcome>();
    model = CommunityMemberRemovalController(port, 'a' * 32, 'b' * 32);
    addTearDown(model.dispose);
    await model.load();
    pending = model.remove();
    await model.remove();
    expect(port.writes, 1);
    port.changes.add(null);
    port.pendingWrite!.complete(
      const CommunityMemberRemovalOutcome('accepted'),
    );
    await pending;
    expect(model.removed, isFalse);
    expect(model.snapshot, isNull);
  });
  test(
    'wrong target is rejected and protected member cannot be submitted',
    () async {
      final port = RemovalFake()
        ..pendingRead = Completer<CommunityMemberRemoval>();
      final model = CommunityMemberRemovalController(port, 'a' * 32, 'b' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      final pending = model.load();
      port.pendingRead!.complete(
        CommunityMemberRemoval.parse(
          removalPayload()..['memberRef'] = 'e' * 32,
        ),
      );
      await pending;
      expect(model.error, 'dataInvalid');
      expect(model.canRemove, isFalse);
      port.pendingRead = null;
      port.canRemove = false;
      await model.load();
      await model.remove();
      expect(port.writes, 0);
    },
  );
  test('example removal keeps stable pagination, other organizations and role assignment', () async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    final id = 1.toRadixString(16).padLeft(32, '0');
    final preview = await port.readMemberRemoval(
      targetRef: '00000000000000000000000000000002',
      memberRef: id,
    );
    expect(
      (await port.removeMember('request', preview.editRef)).status,
      'accepted',
    );
    expect(
      (await port.removeMember('request', preview.editRef)).status,
      'accepted',
    );
    final page = await port.readWorkspace(
      '00000000000000000000000000000002',
      '',
      0,
    );
    expect(page.totalCount, 47);
    expect(page.members.any((r) => r.memberRef == id), isFalse);
    expect(
      (await port.readWorkspace(
        '00000000000000000000000000000001',
        '',
        0,
      )).totalCount,
      12,
    );
    final shiftedId = 20.toRadixString(16).padLeft(32, '0');
    final role = await port.readMemberRole(
      targetRef: '00000000000000000000000000000002',
      memberRef: shiftedId,
    );
    expect(
      (await port.saveMemberRole(
        'assign',
        role.editRef,
        'custom_navigation',
      )).status,
      'accepted',
    );
    final shifted = await port.readMemberRemoval(
      targetRef: '00000000000000000000000000000002',
      memberRef: shiftedId,
    );
    expect(shifted.roleTitle, '领航员');
    expect(
      (await port.removeMember('request2', shifted.editRef)).status,
      'accepted',
    );
    expect(
      (await port.readWorkspace(
        '00000000000000000000000000000002',
        '',
        40,
      )).members.last.memberRef,
      47.toRadixString(16).padLeft(32, '0'),
    );
    final owner = await port.readMemberRemoval(
      targetRef: '00000000000000000000000000000002',
      memberRef: '0' * 32,
    );
    expect(owner.canRemove, isFalse);
    expect(
      (await port.removeMember('owner', owner.editRef)).error,
      'notAllowed',
    );
    await expectLater(
      port.readMemberRole(
        targetRef: '00000000000000000000000000000002',
        memberRef: id,
      ),
      throwsA(isA<CommunityFailure>()),
    );
  });
}
