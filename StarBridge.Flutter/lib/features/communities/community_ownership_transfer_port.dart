import 'dart:convert';

abstract interface class CommunityOwnershipTransferPort {
  Stream<void> get invalidations;
  bool get ownershipTransferAvailable;
  Future<CommunityOwnershipTransfer> readOwnershipTransfer({
    String? targetRef,
    String? memberRef,
    String? editRef,
  });
  Future<CommunityOwnershipTransferOutcome> transferOwnership(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  });
}

final class CommunityOwnershipTransfer {
  const CommunityOwnershipTransfer.example({
    required this.targetRef,
    required this.memberRef,
    required this.editRef,
    required this.gameName,
    required this.callsign,
    required this.roleTitle,
    required this.formerOwnerRoleTitle,
    required this.canTransfer,
    this.leaveAfterTransfer = false,
  });
  final String targetRef,
      memberRef,
      editRef,
      gameName,
      callsign,
      roleTitle,
      formerOwnerRoleTitle;
  final bool canTransfer;
  final bool leaveAfterTransfer;
  String get displayName => callsign.isNotEmpty ? callsign : gameName;
  factory CommunityOwnershipTransfer.parse(
    Map<String, Object?> value, {
    bool expectedLeaveAfterTransfer = false,
  }) {
    if (value['schemaVersion'] != 1 ||
        utf8.encode(jsonEncode(value)).length > 16 * 1024 ||
        value['canTransfer'] is! bool ||
        (value.containsKey('leaveAfterTransfer')
                ? value['leaveAfterTransfer']
                : false) !=
            expectedLeaveAfterTransfer) {
      throw const FormatException();
    }
    String text(String key, int max) {
      final field = value[key];
      if (field is! String ||
          field.length > max ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(field)) {
        throw const FormatException();
      }
      return field;
    }

    String reference(String key) {
      final field = text(key, 32);
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(field)) {
        throw const FormatException();
      }
      return field;
    }

    return CommunityOwnershipTransfer.example(
      targetRef: reference('targetRef'),
      memberRef: reference('memberRef'),
      editRef: reference('editRef'),
      gameName: text('gameName', 512),
      callsign: text('callsign', 512),
      roleTitle: text('roleTitle', 512),
      formerOwnerRoleTitle: text('formerOwnerRoleTitle', 512),
      canTransfer: value['canTransfer'] as bool,
      leaveAfterTransfer: expectedLeaveAfterTransfer,
    );
  }
}

final class CommunityOwnershipTransferOutcome {
  const CommunityOwnershipTransferOutcome(this.status, {this.error});
  final String status;
  final String? error;
  factory CommunityOwnershipTransferOutcome.parse(Map<String, Object?> value) {
    final status = value['status'], error = value['error'];
    if (value['schemaVersion'] != 1 ||
        !const {'accepted', 'rejected', 'unknown'}.contains(status) ||
        status == 'accepted' && error != null ||
        status == 'unknown' && error != 'outcomeUnknown' ||
        status == 'rejected' &&
            !const {
              'busy',
              'refreshRequired',
              'requestChanged',
              'identityUnavailable',
              'notAllowed',
              'unavailable',
              'invalidDraft',
              'conflict',
            }.contains(error)) {
      throw const FormatException();
    }
    return CommunityOwnershipTransferOutcome(
      status as String,
      error: error as String?,
    );
  }
}
