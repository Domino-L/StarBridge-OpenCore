import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

String id(int index) => index.toRadixString(16).padLeft(32, '0');

void main() {
  test(
    'exit clears selected and joined organization without touching another',
    () async {
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
      final edit = await port.readOwnershipExit(
        targetRef: '00000000000000000000000000000002',
        memberRef: id(40),
      );
      expect(edit.successor.leaveAfterTransfer, isTrue);
      expect(
        (await port.leaveWithSuccessor('exit', edit.editRef)).status,
        'accepted',
      );
      await model.refresh(preserveSelection: true);
      await model.refreshJoined();
      expect(model.selected, isNull);
      expect(model.joined.map((c) => c.targetRef), [
        '00000000000000000000000000000001',
      ]);
      await expectLater(
        port.readWorkspace('00000000000000000000000000000002', '', 0),
        throwsA(isA<CommunityFailure>()),
      );
      final discover = await port.read(view: 'discover', query: '');
      final card = discover.items.singleWhere(
        (c) => c.targetRef == '00000000000000000000000000000002',
      );
      expect(card.memberCount, 47);
      expect(card.relationship, 'none');
      expect(
        (await port.readWorkspace(
          '00000000000000000000000000000001',
          '',
          0,
        )).totalCount,
        12,
      );
      expect(
        (await port.leaveWithSuccessor('exit', edit.editRef)).status,
        'accepted',
      );
      expect(
        (await port.read(view: 'discover', query: '')).items
            .singleWhere(
              (c) => c.targetRef == '00000000000000000000000000000002',
            )
            .memberCount,
        47,
      );
      // Rejoining later is ordinary membership; replay cannot expel or promote it.
      await port.execute('join', '00000000000000000000000000000002');
      await port.leaveWithSuccessor('exit', edit.editRef);
      final rejoined = await port.readWorkspace(
        '00000000000000000000000000000002',
        '',
        0,
      );
      expect(rejoined.totalCount, 48);
      expect(rejoined.access.values.every((value) => !value), isTrue);
      expect(
        rejoined.members.singleWhere((m) => m.isSelf).roleTitle,
        isNot('副负责人'),
      );
      expect(
        (await port.readWorkspace(
          '00000000000000000000000000000002',
          '',
          40,
        )).members.singleWhere((m) => m.isOwner).memberRef,
        id(40),
      );
    },
  );

  test(
    'ordinary transfer and exit have separate confirmations and replay intents',
    () async {
      final port = ExampleCommunities();
      addTearDown(port.close);
      final transfer = await port.readOwnershipTransfer(
        targetRef: '00000000000000000000000000000002',
        memberRef: id(2),
      );
      final exit = await port.readOwnershipExit(
        targetRef: '00000000000000000000000000000002',
        memberRef: id(3),
      );
      expect(
        (await port.leaveWithSuccessor('wrong-exit', transfer.editRef)).status,
        'rejected',
      );
      expect(
        (await port.transferOwnership('wrong-transfer', exit.editRef)).status,
        'rejected',
      );
      await expectLater(
        port.readOwnershipExit(editRef: transfer.editRef),
        throwsA(isA<CommunityFailure>()),
      );
      await expectLater(
        port.readOwnershipTransfer(editRef: exit.editRef),
        throwsA(isA<CommunityFailure>()),
      );
      expect(
        (await port.readWorkspace(
          '00000000000000000000000000000002',
          '',
          0,
        )).access['isOwner'],
        isTrue,
      );
      expect(
        (await port.leaveWithSuccessor('exit', exit.editRef)).status,
        'accepted',
      );
      expect(
        (await port.transferOwnership('exit', exit.editRef)).error,
        'requestChanged',
      );
      expect(
        (await port.transferOwnership('old', transfer.editRef)).status,
        'rejected',
      );
    },
  );

  test(
    'self, ordinary member, removed or role-changed successor cannot leave',
    () async {
      final port = ExampleCommunities();
      addTearDown(port.close);
      final self = await port.readOwnershipExit(
        targetRef: '00000000000000000000000000000002',
        memberRef: id(0),
      );
      expect(self.canLeave, isFalse);
      expect(
        (await port.leaveWithSuccessor('self', self.editRef)).status,
        'rejected',
      );
      await expectLater(
        port.readOwnershipExit(
          targetRef: '00000000000000000000000000000001',
          memberRef: id(3),
        ),
        throwsA(isA<CommunityFailure>()),
      );
      final edit = await port.readOwnershipExit(
        targetRef: '00000000000000000000000000000002',
        memberRef: id(4),
      );
      final staleRole = await port.readOwnershipExit(
        targetRef: '00000000000000000000000000000002',
        memberRef: id(6),
      );
      final role = await port.readMemberRole(
        targetRef: '00000000000000000000000000000002',
        memberRef: id(6),
      );
      await port.saveMemberRole('role', role.editRef, 'custom_navigation');
      expect(
        (await port.leaveWithSuccessor('stale-role', staleRole.editRef)).error,
        'conflict',
      );
      final removal = await port.readMemberRemoval(
        targetRef: '00000000000000000000000000000002',
        memberRef: id(4),
      );
      await port.removeMember('remove', removal.editRef);
      expect(
        (await port.leaveWithSuccessor('removed', edit.editRef)).status,
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
    },
  );

  test('concurrent retaining and exit requests have one winner', () async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    final keep = await port.readOwnershipTransfer(
      targetRef: '00000000000000000000000000000002',
      memberRef: id(3),
    );
    final exit = await port.readOwnershipExit(
      targetRef: '00000000000000000000000000000002',
      memberRef: id(5),
    );
    final results = await Future.wait([
      port.transferOwnership('keep', keep.editRef),
      port.leaveWithSuccessor('exit', exit.editRef),
    ]);
    expect(results.where((r) => r.status == 'accepted'), hasLength(1));
  });
}
