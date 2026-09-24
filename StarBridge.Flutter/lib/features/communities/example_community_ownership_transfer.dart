import 'communities_module.dart';
import 'community_ownership_transfer_port.dart';
import 'example_community_member_removal.dart';

/// Session-only demonstration. Production ownership never depends on this state.
final class ExampleCommunityOwnershipTransfer {
  final owners = <String, String>{};
  final departed = <String>{};
  final _edits = <String, (String, String, String, bool)>{};
  final _receipts =
      <String, (String, CommunityOwnershipTransferOutcome, bool)>{};
  int _sequence = 0;

  Future<CommunityOwnershipTransfer> read(
    ExampleWorkspaceReader workspace, {
    String? targetRef,
    String? memberRef,
    String? editRef,
    bool leaveAfterTransfer = false,
  }) async {
    if (editRef != null) {
      final old = _edits[editRef];
      if (old == null || old.$4 != leaveAfterTransfer) {
        throw const CommunityFailure('refreshRequired');
      }
      targetRef = old.$1;
      memberRef = old.$2;
    }
    if (targetRef == null || memberRef == null) {
      throw const CommunityFailure('dataInvalid');
    }
    final (page, member) = await findExampleCommunityMember(
      workspace,
      targetRef,
      memberRef,
    );
    if (page.access['isOwner'] != true) {
      throw const CommunityFailure('notAllowed');
    }
    final ref = (++_sequence).toRadixString(16).padLeft(32, '0');
    _edits[ref] = (targetRef, memberRef, member.roleTitle, leaveAfterTransfer);
    return CommunityOwnershipTransfer.example(
      targetRef: targetRef,
      memberRef: memberRef,
      editRef: ref,
      gameName: member.gameName,
      callsign: member.callsign,
      roleTitle: member.roleTitle,
      formerOwnerRoleTitle: '副负责人',
      canTransfer: !member.isSelf && !member.isOwner,
      leaveAfterTransfer: leaveAfterTransfer,
    );
  }

  Future<CommunityOwnershipTransferOutcome> transfer(
    ExampleWorkspaceReader workspace,
    String requestId,
    String editRef, {
    bool leaveAfterTransfer = false,
  }) async {
    final prior = _receipts[requestId];
    if (prior != null) {
      return prior.$1 == editRef && prior.$3 == leaveAfterTransfer
          ? prior.$2
          : const CommunityOwnershipTransferOutcome(
              'rejected',
              error: 'requestChanged',
            );
    }
    final edit = _edits[editRef];
    if (edit == null || edit.$4 != leaveAfterTransfer) {
      return const CommunityOwnershipTransferOutcome(
        'rejected',
        error: 'refreshRequired',
      );
    }
    try {
      final (page, member) = await findExampleCommunityMember(
        workspace,
        edit.$1,
        edit.$2,
      );
      if (page.access['isOwner'] != true ||
          member.isSelf ||
          member.isOwner ||
          owners.containsKey(edit.$1)) {
        return const CommunityOwnershipTransferOutcome(
          'rejected',
          error: 'notAllowed',
        );
      }
      if (member.roleTitle != edit.$3) {
        return const CommunityOwnershipTransferOutcome(
          'rejected',
          error: 'conflict',
        );
      }
      owners[edit.$1] = edit.$2;
      if (leaveAfterTransfer) departed.add(edit.$1);
      const result = CommunityOwnershipTransferOutcome('accepted');
      _receipts[requestId] = (editRef, result, leaveAfterTransfer);
      return result;
    } on CommunityFailure catch (e) {
      return CommunityOwnershipTransferOutcome(
        'rejected',
        error: e.code == 'notFound' ? 'refreshRequired' : e.code,
      );
    }
  }

  void clear() {
    owners.clear();
    departed.clear();
    _edits.clear();
    _receipts.clear();
  }
}
