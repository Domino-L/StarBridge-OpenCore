import 'dart:convert';

abstract interface class CommunityMemberRemovalPort {
  Stream<void> get invalidations;
  bool get memberRemovalAvailable;
  Future<CommunityMemberRemoval> readMemberRemoval({
    String? targetRef,
    String? memberRef,
    String? editRef,
  });
  Future<CommunityMemberRemovalOutcome> removeMember(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  });
}

final class CommunityMemberRemoval {
  const CommunityMemberRemoval.example({
    required this.targetRef,
    required this.memberRef,
    required this.editRef,
    required this.gameName,
    required this.callsign,
    required this.roleTitle,
    required this.canRemove,
  });
  final String targetRef, memberRef, editRef, gameName, callsign, roleTitle;
  final bool canRemove;
  String get displayName => callsign.isNotEmpty ? callsign : gameName;
  factory CommunityMemberRemoval.parse(Map<String, Object?> value) {
    if (value['schemaVersion'] != 1 ||
        utf8.encode(jsonEncode(value)).length > 16 * 1024 ||
        value['canRemove'] is! bool) {
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

    return CommunityMemberRemoval.example(
      targetRef: reference('targetRef'),
      memberRef: reference('memberRef'),
      editRef: reference('editRef'),
      gameName: text('gameName', 512),
      callsign: text('callsign', 512),
      roleTitle: text('roleTitle', 512),
      canRemove: value['canRemove'] as bool,
    );
  }
}

final class CommunityMemberRemovalOutcome {
  const CommunityMemberRemovalOutcome(this.status, {this.error});
  final String status;
  final String? error;
  factory CommunityMemberRemovalOutcome.parse(Map<String, Object?> value) {
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
    return CommunityMemberRemovalOutcome(
      status as String,
      error: error as String?,
    );
  }
}
