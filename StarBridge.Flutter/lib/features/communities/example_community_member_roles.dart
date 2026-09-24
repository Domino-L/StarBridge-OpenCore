import 'community_member_role_port.dart';
import 'community_workspace_port.dart';
import 'communities_module.dart';
import 'example_community_member_removal.dart';

/// Isolated example state. Never used for a production read or write fallback.
final class ExampleCommunityMemberRoles {
  final assignments = <String, Map<String, String>>{};
  final _edits = <String, (String, String, String)>{};
  final _receipts = <String, (String, String, CommunityMemberRoleOutcome)>{};
  int _sequence = 0;
  static const roles = [
    CommunityMemberRoleOption('custom_navigation', '领航员', '#9B7CFA'),
    CommunityMemberRoleOption('custom_logistics', '后勤', '#35C58C'),
  ];
  static String name(String key) =>
      roles.where((r) => r.key == key).firstOrNull?.name ?? '成员';
  static String color(String key) =>
      roles.where((r) => r.key == key).firstOrNull?.color ?? '#45AEF5';
  Future<CommunityWorkspaceMember> _member(
    Future<CommunityWorkspace> Function(String, String, int) read,
    String targetRef,
    String memberRef,
  ) async {
    final index = int.tryParse(memberRef, radix: 16);
    if (index == null || index < 0 || index > 1000000) {
      throw const CommunityFailure('refreshRequired');
    }
    final (workspace, member) = await findExampleCommunityMember(
      read,
      targetRef,
      memberRef,
    );
    if (workspace.access['isOwner'] != true) {
      throw const CommunityFailure('notAllowed');
    }
    return member;
  }

  Future<CommunityMemberRole> read(
    Future<CommunityWorkspace> Function(String, String, int) workspace, {
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) async {
    if (editRef != null) {
      final previous = _edits[editRef];
      if (previous == null) throw const CommunityFailure('refreshRequired');
      targetRef = previous.$1;
      memberRef = previous.$2;
    }
    if (targetRef == null || memberRef == null) {
      throw const CommunityFailure('dataInvalid');
    }
    final member = await _member(workspace, targetRef, memberRef);
    final roleKey = assignments[targetRef]?[memberRef] ?? '';
    final reference = (++_sequence).toRadixString(16).padLeft(32, '0');
    _edits[reference] = (targetRef, memberRef, roleKey);
    return CommunityMemberRole.example(
      targetRef: targetRef,
      memberRef: memberRef,
      editRef: reference,
      name: member.displayName,
      roleKey: roleKey,
      roleTitle: member.roleTitle,
      canAssign: !member.isOwner && !member.isSelf,
      roles: roles,
    );
  }

  Future<CommunityMemberRoleOutcome> save(
    Future<CommunityWorkspace> Function(String, String, int) workspace,
    String requestId,
    String editRef,
    String roleKey,
  ) async {
    final prior = _receipts[requestId];
    if (prior != null) {
      return prior.$1 == editRef && prior.$2 == roleKey
          ? prior.$3
          : const CommunityMemberRoleOutcome(
              'rejected',
              error: 'requestChanged',
            );
    }
    final edit = _edits[editRef];
    if (edit == null) {
      return const CommunityMemberRoleOutcome(
        'rejected',
        error: 'refreshRequired',
      );
    }
    final member = await _member(workspace, edit.$1, edit.$2);
    if (member.isOwner || member.isSelf) {
      return const CommunityMemberRoleOutcome('rejected', error: 'notAllowed');
    }
    if ((assignments[edit.$1]?[edit.$2] ?? '') != edit.$3) {
      return const CommunityMemberRoleOutcome('rejected', error: 'conflict');
    }
    if (roleKey != '' && !roles.any((r) => r.key == roleKey)) {
      return const CommunityMemberRoleOutcome(
        'rejected',
        error: 'invalidDraft',
      );
    }
    (assignments[edit.$1] ??= {})[edit.$2] = roleKey;
    const result = CommunityMemberRoleOutcome('accepted');
    _receipts[requestId] = (editRef, roleKey, result);
    return result;
  }

  void clear() {
    assignments.clear();
    _edits.clear();
    _receipts.clear();
  }
}
