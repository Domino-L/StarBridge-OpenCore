import 'communities_module.dart';
import 'community_workspace_port.dart';
import 'community_member_removal_port.dart';

typedef ExampleWorkspaceReader = Future<CommunityWorkspace> Function(
  String,
  String,
  int,
);

Future<(CommunityWorkspace, CommunityWorkspaceMember)>
findExampleCommunityMember(
  ExampleWorkspaceReader read,
  String targetRef,
  String memberRef,
) async {
  var page = await read(targetRef, '', 0);
  while (true) {
    final member = page.members
        .where((row) => row.memberRef == memberRef)
        .firstOrNull;
    if (member != null) return (page, member);
    final next = page.next;
    if (next == null || next <= page.offset) {
      throw const CommunityFailure('refreshRequired');
    }
    page = await read(targetRef, '', next);
  }
}

/// Example-only mutation state; no production fallback and no account access.
final class ExampleCommunityMemberRemoval {
  final removed = <String, Set<String>>{};
  final _edits = <String, (String, String, String)>{};
  final _receipts = <String, (String, CommunityMemberRemovalOutcome)>{};
  int _sequence = 0;
  Future<CommunityMemberRemoval> read(
    ExampleWorkspaceReader workspace, {
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) async {
    if (editRef != null) {
      final edit = _edits[editRef];
      if (edit == null) throw const CommunityFailure('refreshRequired');
      targetRef = edit.$1;
      memberRef = edit.$2;
    }
    if (targetRef == null || memberRef == null) {
      throw const CommunityFailure('dataInvalid');
    }
    final (page, member) = await findExampleCommunityMember(
      workspace,
      targetRef,
      memberRef,
    );
    if (page.access['isOwner'] != true &&
        page.access['canRemoveMembers'] != true) {
      throw const CommunityFailure('notAllowed');
    }
    final reference = (++_sequence).toRadixString(16).padLeft(32, '0');
    _edits[reference] = (targetRef, memberRef, member.roleTitle);
    return CommunityMemberRemoval.example(
      targetRef: targetRef,
      memberRef: memberRef,
      editRef: reference,
      gameName: member.gameName,
      callsign: member.callsign,
      roleTitle: member.roleTitle,
      canRemove:
          !member.isSelf &&
          !member.isOwner &&
          (page.access['isOwner'] == true || member.roleTitle == '成员'),
    );
  }

  Future<CommunityMemberRemovalOutcome> remove(
    ExampleWorkspaceReader workspace,
    String requestId,
    String editRef,
  ) async {
    final previous = _receipts[requestId];
    if (previous != null) {
      return previous.$1 == editRef
          ? previous.$2
          : const CommunityMemberRemovalOutcome(
              'rejected',
              error: 'requestChanged',
            );
    }
    final edit = _edits[editRef];
    if (edit == null) {
      return const CommunityMemberRemovalOutcome(
        'rejected',
        error: 'refreshRequired',
      );
    }
    try {
      final current = await read(workspace, editRef: editRef);
      if (!current.canRemove) {
        return const CommunityMemberRemovalOutcome(
          'rejected',
          error: 'notAllowed',
        );
      }
      if (current.roleTitle != edit.$3) {
        return const CommunityMemberRemovalOutcome(
          'rejected',
          error: 'conflict',
        );
      }
      (removed[edit.$1] ??= {}).add(edit.$2);
      const result = CommunityMemberRemovalOutcome('accepted');
      _receipts[requestId] = (editRef, result);
      return result;
    } on CommunityFailure catch (e) {
      return CommunityMemberRemovalOutcome('rejected', error: e.code);
    }
  }

  void clear() {
    removed.clear();
    _edits.clear();
    _receipts.clear();
  }
}
