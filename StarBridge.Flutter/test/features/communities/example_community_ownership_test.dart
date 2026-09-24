import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

String memberId(int index) => index.toRadixString(16).padLeft(32, '0');

void main() {
  test('transfer preserves members and other organizations, updates directory actions', () async {
    final port = ExampleCommunities();
    final model = CommunitiesModule(port);
    addTearDown(port.close);
    addTearDown(model.dispose);
    await model.refresh();
    model.open(
      model.directory!.items.singleWhere(
        (c) => c.targetRef == '00000000000000000000000000000002',
      ),
    );
    final edit = await port.readOwnershipTransfer(
      targetRef: '00000000000000000000000000000002',
      memberRef: memberId(1),
    );
    expect(edit.formerOwnerRoleTitle, '副负责人');
    expect(
      (await port.transferOwnership('transfer', edit.editRef)).status,
      'accepted',
    );
    await model.refresh(preserveSelection: true);
    expect(model.selected?.targetRef, '00000000000000000000000000000002');
    expect(model.selected?.relationship, 'member');
    expect(model.selected?.actions, contains('leave'));
    expect(
      model.joined
          .singleWhere((c) => c.targetRef == '00000000000000000000000000000002')
          .relationship,
      'member',
    );
    final page = await port.readWorkspace(
      '00000000000000000000000000000002',
      '',
      0,
    );
    expect(page.totalCount, 48);
    expect(page.members.where((m) => m.isOwner).single.memberRef, memberId(1));
    expect(page.members.where((m) => m.isSelf).single.memberRef, memberId(0));
    expect(page.members.first.roleTitle, '副负责人');
    expect(page.access['isOwner'], isFalse);
    expect(page.access['canRemoveMembers'], isTrue);
    expect(
      (await port.readWorkspace(
        '00000000000000000000000000000001',
        '',
        0,
      )).totalCount,
      12,
    );
    expect(
      (await port.readWorkspace(
        '00000000000000000000000000000001',
        '',
        0,
      )).members.first.isOwner,
      isTrue,
    );
    for (final id in [0, 1]) {
      final protected = await port.readMemberRemoval(
        targetRef: '00000000000000000000000000000002',
        memberRef: memberId(id),
      );
      expect(protected.canRemove, isFalse);
    }
    await expectLater(
      port.readMemberRole(
        targetRef: '00000000000000000000000000000002',
        memberRef: memberId(2),
      ),
      throwsA(isA<CommunityFailure>()),
    );
  });

  test('accepted replay cannot rejoin an organization after leaving', () async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    final edit = await port.readOwnershipTransfer(
      targetRef: '00000000000000000000000000000002',
      memberRef: memberId(1),
    );
    await port.transferOwnership('transfer', edit.editRef);
    await port.execute('leave', '00000000000000000000000000000002');
    expect(
      (await port.transferOwnership('transfer', edit.editRef)).status,
      'accepted',
    );
    final mine = await port.read(view: 'mine', query: '');
    expect(
      mine.items.any((c) => c.targetRef == '00000000000000000000000000000002'),
      isFalse,
    );
  });

  test('owner self and ordinary member cannot transfer', () async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    final self = await port.readOwnershipTransfer(
      targetRef: '00000000000000000000000000000002',
      memberRef: memberId(0),
    );
    expect(self.canTransfer, isFalse);
    expect(
      (await port.transferOwnership('self', self.editRef)).error,
      'notAllowed',
    );
    await expectLater(
      port.readOwnershipTransfer(
        targetRef: '00000000000000000000000000000001',
        memberRef: memberId(2),
      ),
      throwsA(isA<CommunityFailure>()),
    );
  });

  test('changed or removed successor requires fresh confirmation', () async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    final edit = await port.readOwnershipTransfer(
      targetRef: '00000000000000000000000000000002',
      memberRef: memberId(1),
    );
    final role = await port.readMemberRole(
      targetRef: '00000000000000000000000000000002',
      memberRef: memberId(1),
    );
    await port.saveMemberRole('role', role.editRef, 'custom_navigation');
    expect(
      (await port.transferOwnership('stale', edit.editRef)).error,
      'conflict',
    );
    final fresh = await port.readOwnershipTransfer(
      targetRef: '00000000000000000000000000000002',
      memberRef: memberId(1),
    );
    final removal = await port.readMemberRemoval(
      targetRef: '00000000000000000000000000000002',
      memberRef: memberId(1),
    );
    await port.removeMember('remove', removal.editRef);
    expect(
      (await port.transferOwnership('removed', fresh.editRef)).status,
      'rejected',
    );
    expect(
      (await port.readWorkspace(
        '00000000000000000000000000000002',
        '',
        0,
      )).access['isOwner'],
      isTrue,
    );
  });

  test(
    'only one concurrent successor wins and replay does not change it',
    () async {
      final port = ExampleCommunities();
      addTearDown(port.close);
      final first = await port.readOwnershipTransfer(
        targetRef: '00000000000000000000000000000002',
        memberRef: memberId(1),
      );
      final second = await port.readOwnershipTransfer(
        targetRef: '00000000000000000000000000000002',
        memberRef: memberId(2),
      );
      final results = await Future.wait([
        port.transferOwnership('first', first.editRef),
        port.transferOwnership('second', second.editRef),
      ]);
      expect(results.where((r) => r.status == 'accepted'), hasLength(1));
      final winner = (await port.readWorkspace(
        '00000000000000000000000000000002',
        '',
        0,
      )).members.singleWhere((m) => m.isOwner).memberRef;
      await port.transferOwnership('first', first.editRef);
      await port.transferOwnership('second', second.editRef);
      expect(
        (await port.readWorkspace(
          '00000000000000000000000000000002',
          '',
          0,
        )).members.singleWhere((m) => m.isOwner).memberRef,
        winner,
      );
      expect(
        (await port.transferOwnership('new', first.editRef)).error,
        'notAllowed',
      );
    },
  );
}
