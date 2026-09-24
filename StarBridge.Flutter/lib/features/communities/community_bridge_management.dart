import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import 'communities_module.dart';
import 'community_profile_port.dart';
import 'community_admissions_port.dart';
import 'community_roles_port.dart';
import 'community_member_role_port.dart';
import 'community_member_removal_port.dart';
import 'community_ownership_transfer_port.dart';
import 'community_ownership_exit_port.dart';
import 'community_logs_port.dart';
import 'community_disband_port.dart';

import 'community_bridge_transport.dart';

mixin CommunityBridgeManagement on CommunityBridgeTransport
    implements
        CommunityAdmissionsPort,
        CommunityRolesPort,
        CommunityLogsPort,
        CommunityDisbandPort,
        CommunityMemberRolePort,
        CommunityMemberRemovalPort,
        CommunityOwnershipTransferPort,
        CommunityOwnershipExitPort,
        CommunityProfilePort {
  @override
  Future<CommunityAdmissionsPage> readAdmissions(
    String targetRef,
    String section,
    int offset,
  ) => workspaceRead(
    () async => CommunityAdmissionsPage.parse(
      await sendRequest('communities.admissions', {
        'targetRef': targetRef,
        'section': section,
        'offset': offset,
      }),
      targetRef,
      section,
      offset,
    ),
  );

  @override
  Future<CommunityAdmissionOutcome> manageAdmissions(
    CommunityAdmissionIntent intent,
  ) async {
    final Map<String, Object?> payload;
    try {
      payload = intent.toPayload();
    } on FormatException {
      return const CommunityAdmissionOutcome('rejected', error: 'dataInvalid');
    }
    try {
      return CommunityAdmissionOutcome.parse(
        await sendRequest('communities.manageAdmissions', payload),
      );
    } on CommunityFailure catch (e) {
      return e.code == 'unavailable'
          ? const CommunityAdmissionOutcome('rejected', error: 'unavailable')
          : const CommunityAdmissionOutcome('unknown', error: 'outcomeUnknown');
    } on BridgeClientException catch (e) {
      if (e.code == 'communities.dataInvalid') {
        return const CommunityAdmissionOutcome(
          'rejected',
          error: 'dataInvalid',
        );
      }
      return const CommunityAdmissionOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    } catch (_) {
      // A lost/malformed reply is not evidence that the write was rejected.
      return const CommunityAdmissionOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
  }

  @override
  bool get rolesAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.roles') &&
      session.hostCapabilities.contains('communities.saveRoles');

  @override
  bool get logsAvailable =>
      !isClosed && session.hostCapabilities.contains('communities.logs');
  @override
  bool get disbandAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.disbandPreview') &&
      session.hostCapabilities.contains('communities.disband');
  @override
  Future<CommunityDisbandPreview> readDisband(String targetRef) =>
      workspaceRead(() async {
        final result = CommunityDisbandPreview.parse(
          await sendRequest('communities.disbandPreview', {
            'targetRef': targetRef,
          }),
        );
        if (result.targetRef != targetRef) throw const FormatException();
        return result;
      });
  @override
  Future<CommunityDisbandOutcome> disband(
    String targetRef,
    String confirmationRef,
    String password,
  ) async {
    if (!disbandAvailable) {
      return const CommunityDisbandOutcome('rejected', error: 'unavailable');
    }
    if (password.trim().isEmpty || password.length > 4096) {
      return const CommunityDisbandOutcome(
        'rejected',
        error: 'passwordInvalid',
      );
    }
    try {
      return CommunityDisbandOutcome.parse(
        await sendRequest('communities.disband', {
          'targetRef': targetRef,
          'confirmationRef': confirmationRef,
          'password': password,
        }),
      );
    } catch (_) {
      return const CommunityDisbandOutcome('unknown', error: 'outcomeUnknown');
    }
  }

  @override
  bool get logDeletionAvailable =>
      logsAvailable &&
      session.hostCapabilities.contains('communities.deleteLog');
  @override
  Future<CommunityLogPage> readLogs(
    String targetRef,
    String type,
    String query,
    int offset,
  ) => workspaceRead(
    () async => CommunityLogPage.parse(
      await sendRequest('communities.logs', {
        'targetRef': targetRef,
        'type': type,
        'query': query,
        'offset': offset,
      }),
    ),
  );
  @override
  Future<CommunityLogOutcome> deleteLog(String targetRef, String logRef) async {
    if (!logDeletionAvailable) {
      return const CommunityLogOutcome('rejected', error: 'unavailable');
    }
    try {
      return CommunityLogOutcome.parse(
        await sendRequest('communities.deleteLog', {
          'targetRef': targetRef,
          'logRef': logRef,
        }),
      );
    } catch (_) {
      return const CommunityLogOutcome('unknown', error: 'outcomeUnknown');
    }
  }

  @override
  bool get memberRoleAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.memberRole') &&
      session.hostCapabilities.contains('communities.saveMemberRole');
  @override
  bool get ownershipTransferAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.ownershipTransfer') &&
      session.hostCapabilities.contains('communities.transferOwnership');
  @override
  bool get ownershipExitAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.ownershipExit') &&
      session.hostCapabilities.contains('communities.leaveWithSuccessor');
  @override
  Future<CommunityOwnershipExit> readOwnershipExit({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) => workspaceRead(() async {
    if (editRef == null
        ? targetRef == null || memberRef == null
        : targetRef != null || memberRef != null) {
      throw const FormatException();
    }
    final result = CommunityOwnershipExit.parse(
      await sendRequest('communities.ownershipExit', {
        'targetRef': ?targetRef,
        'memberRef': ?memberRef,
        'editRef': ?editRef,
      }),
    );
    if (targetRef != null && result.targetRef != targetRef ||
        memberRef != null && result.memberRef != memberRef) {
      throw const FormatException();
    }
    return result;
  });
  @override
  Future<CommunityOwnershipTransferOutcome> leaveWithSuccessor(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  }) => _writeOwnership(
    'communities.leaveWithSuccessor',
    requestId,
    editRef,
    confirmUncertainRetry,
  );
  @override
  Future<CommunityOwnershipTransfer> readOwnershipTransfer({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) => workspaceRead(() async {
    if (editRef == null
        ? targetRef == null || memberRef == null
        : targetRef != null || memberRef != null) {
      throw const FormatException();
    }
    final result = CommunityOwnershipTransfer.parse(
      await sendRequest('communities.ownershipTransfer', {
        'targetRef': ?targetRef,
        'memberRef': ?memberRef,
        'editRef': ?editRef,
      }),
    );
    if (targetRef != null && result.targetRef != targetRef ||
        memberRef != null && result.memberRef != memberRef) {
      throw const FormatException();
    }
    return result;
  });
  @override
  Future<CommunityOwnershipTransferOutcome> transferOwnership(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  }) => _writeOwnership(
    'communities.transferOwnership',
    requestId,
    editRef,
    confirmUncertainRetry,
  );

  Future<CommunityOwnershipTransferOutcome> _writeOwnership(
    String request,
    String requestId,
    String editRef,
    bool confirmUncertainRetry,
  ) async {
    try {
      return CommunityOwnershipTransferOutcome.parse(
        await sendRequest(request, {
          'requestId': requestId,
          'editRef': editRef,
          'confirmUncertainRetry': confirmUncertainRetry,
        }),
      );
    } on BridgeClientException catch (e) {
      return e.code == 'communities.dataInvalid'
          ? const CommunityOwnershipTransferOutcome(
              'rejected',
              error: 'invalidDraft',
            )
          : const CommunityOwnershipTransferOutcome(
              'unknown',
              error: 'outcomeUnknown',
            );
    } on CommunityFailure catch (e) {
      return e.code == 'unavailable'
          ? const CommunityOwnershipTransferOutcome(
              'rejected',
              error: 'unavailable',
            )
          : const CommunityOwnershipTransferOutcome(
              'unknown',
              error: 'outcomeUnknown',
            );
    } catch (_) {
      return const CommunityOwnershipTransferOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
  }

  @override
  bool get memberRemovalAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.memberRemoval') &&
      session.hostCapabilities.contains('communities.removeMember');
  @override
  Future<CommunityMemberRemoval> readMemberRemoval({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) => workspaceRead(() async {
    if (editRef == null
        ? targetRef == null || memberRef == null
        : targetRef != null || memberRef != null) {
      throw const FormatException();
    }
    final result = CommunityMemberRemoval.parse(
      await sendRequest('communities.memberRemoval', {
        'targetRef': ?targetRef,
        'memberRef': ?memberRef,
        'editRef': ?editRef,
      }),
    );
    if (targetRef != null && result.targetRef != targetRef ||
        memberRef != null && result.memberRef != memberRef) {
      throw const FormatException();
    }
    return result;
  });
  @override
  Future<CommunityMemberRemovalOutcome> removeMember(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  }) async {
    try {
      return CommunityMemberRemovalOutcome.parse(
        await sendRequest('communities.removeMember', {
          'requestId': requestId,
          'editRef': editRef,
          'confirmUncertainRetry': confirmUncertainRetry,
        }),
      );
    } on BridgeClientException catch (e) {
      return e.code == 'communities.dataInvalid'
          ? const CommunityMemberRemovalOutcome(
              'rejected',
              error: 'invalidDraft',
            )
          : const CommunityMemberRemovalOutcome(
              'unknown',
              error: 'outcomeUnknown',
            );
    } on CommunityFailure catch (e) {
      return e.code == 'unavailable'
          ? const CommunityMemberRemovalOutcome(
              'rejected',
              error: 'unavailable',
            )
          : const CommunityMemberRemovalOutcome(
              'unknown',
              error: 'outcomeUnknown',
            );
    } catch (_) {
      return const CommunityMemberRemovalOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
  }

  @override
  Future<CommunityMemberRole> readMemberRole({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) => workspaceRead(() async {
    if (editRef == null
        ? targetRef == null || memberRef == null
        : targetRef != null || memberRef != null) {
      throw const FormatException();
    }
    final result = CommunityMemberRole.parse(
      await sendRequest('communities.memberRole', {
        'targetRef': ?targetRef,
        'memberRef': ?memberRef,
        'editRef': ?editRef,
      }),
    );
    if (targetRef != null && result.targetRef != targetRef ||
        memberRef != null && result.memberRef != memberRef) {
      throw const FormatException();
    }
    return result;
  });
  @override
  Future<CommunityMemberRoleOutcome> saveMemberRole(
    String requestId,
    String editRef,
    String roleKey, {
    bool confirmUncertainRetry = false,
  }) async {
    try {
      return CommunityMemberRoleOutcome.parse(
        await sendRequest('communities.saveMemberRole', {
          'requestId': requestId,
          'editRef': editRef,
          'roleKey': roleKey,
          'confirmUncertainRetry': confirmUncertainRetry,
        }),
      );
    } on BridgeClientException catch (e) {
      return e.code == 'communities.dataInvalid'
          ? const CommunityMemberRoleOutcome('rejected', error: 'invalidDraft')
          : const CommunityMemberRoleOutcome(
              'unknown',
              error: 'outcomeUnknown',
            );
    } on CommunityFailure catch (e) {
      return e.code == 'unavailable'
          ? const CommunityMemberRoleOutcome('rejected', error: 'unavailable')
          : const CommunityMemberRoleOutcome(
              'unknown',
              error: 'outcomeUnknown',
            );
    } catch (_) {
      return const CommunityMemberRoleOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
  }

  @override
  Future<CommunityEditingRoles> readRoles({
    String? targetRef,
    String? editRef,
  }) => workspaceRead(() async {
    if ((targetRef == null) == (editRef == null)) throw const FormatException();
    final result = CommunityEditingRoles.parse(
      await sendRequest('communities.roles', {
        'targetRef': ?targetRef,
        'editRef': ?editRef,
      }),
    );
    if (targetRef != null && result.targetRef != targetRef) {
      throw const FormatException();
    }
    return result;
  });

  @override
  Future<CommunityProfileOutcome> saveRoles(
    String requestId,
    String editRef,
    List<CommunityRole> roles, {
    bool confirmUncertainRetry = false,
  }) async {
    try {
      return CommunityProfileOutcome.parse(
        await sendRequest('communities.saveRoles', {
          'requestId': requestId,
          'editRef': editRef,
          'roles': roles.map((role) => role.toDraft()).toList(),
          'confirmUncertainRetry': confirmUncertainRetry,
        }),
      );
    } on BridgeClientException catch (error) {
      return error.code == 'communities.dataInvalid'
          ? const CommunityProfileOutcome('rejected', error: 'invalidDraft')
          : const CommunityProfileOutcome('unknown', error: 'outcomeUnknown');
    } on CommunityFailure catch (error) {
      return error.code == 'unavailable'
          ? const CommunityProfileOutcome('rejected', error: 'unavailable')
          : const CommunityProfileOutcome('unknown', error: 'outcomeUnknown');
    } catch (_) {
      return const CommunityProfileOutcome('unknown', error: 'outcomeUnknown');
    }
  }

  @override
  Future<CommunityEditingProfile> readProfile({
    String? targetRef,
    String? editRef,
  }) => workspaceRead(() async {
    if ((targetRef == null) == (editRef == null)) throw const FormatException();
    final result = CommunityEditingProfile.parse(
      await sendRequest('communities.profile', {
        'targetRef': ?targetRef,
        'editRef': ?editRef,
      }),
    );
    if (targetRef != null && result.targetRef != targetRef) {
      throw const FormatException();
    }
    return result;
  });

  @override
  Future<CommunityProfileOutcome> saveProfile(
    String requestId,
    String editRef,
    Map<String, Object?> changes,
  ) async {
    try {
      return CommunityProfileOutcome.parse(
        await sendRequest('communities.saveProfile', {
          'requestId': requestId,
          'editRef': editRef,
          'changes': changes,
        }),
      );
    } on BridgeClientException catch (e) {
      if (e.code == 'communities.dataInvalid') {
        return const CommunityProfileOutcome('rejected', error: 'invalidDraft');
      }
      return const CommunityProfileOutcome('unknown', error: 'outcomeUnknown');
    } on CommunityFailure catch (e) {
      // Missing capability is a pre-dispatch failure. Identity invalidation may
      // also occur after dispatch, so it must never encourage a second POST.
      return e.code == 'unavailable'
          ? const CommunityProfileOutcome('rejected', error: 'unavailable')
          : const CommunityProfileOutcome('unknown', error: 'outcomeUnknown');
    } catch (_) {
      return const CommunityProfileOutcome('unknown', error: 'outcomeUnknown');
    }
  }
}
