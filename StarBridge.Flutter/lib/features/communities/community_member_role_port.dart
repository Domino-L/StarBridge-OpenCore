import 'dart:convert';

abstract interface class CommunityMemberRolePort {
  Stream<void> get invalidations;
  bool get memberRoleAvailable;
  Future<CommunityMemberRole> readMemberRole({
    String? targetRef,
    String? memberRef,
    String? editRef,
  });
  Future<CommunityMemberRoleOutcome> saveMemberRole(
    String requestId,
    String editRef,
    String roleKey, {
    bool confirmUncertainRetry = false,
  });
}

final class CommunityMemberRoleOption {
  const CommunityMemberRoleOption(this.key, this.name, this.color);
  final String key, name, color;
}

final class CommunityMemberRole {
  const CommunityMemberRole._(
    this.targetRef,
    this.memberRef,
    this.editRef,
    this.gameName,
    this.callsign,
    this.roleTitle,
    this.roleKey,
    this.canAssign,
    this.roles,
  );
  final String targetRef,
      memberRef,
      editRef,
      gameName,
      callsign,
      roleTitle,
      roleKey;
  final bool canAssign;
  final List<CommunityMemberRoleOption> roles;
  factory CommunityMemberRole.example({
    required String targetRef,
    required String memberRef,
    required String editRef,
    required String name,
    required String roleKey,
    required String roleTitle,
    required bool canAssign,
    required List<CommunityMemberRoleOption> roles,
  }) => CommunityMemberRole._(
    targetRef,
    memberRef,
    editRef,
    '',
    name,
    roleTitle,
    roleKey,
    canAssign,
    List.unmodifiable(roles),
  );
  String get displayName => callsign.isNotEmpty ? callsign : gameName;
  factory CommunityMemberRole.parse(Map<String, Object?> value) {
    if (value['schemaVersion'] != 1 ||
        utf8.encode(jsonEncode(value)).length > 256 * 1024 ||
        value['canAssign'] is! bool) {
      throw const FormatException();
    }
    String text(Map<String, Object?> row, String key, int max) {
      final value = row[key];
      if (value is! String ||
          value.length > max ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw const FormatException();
      }
      return value;
    }

    String reference(String key) {
      final result = text(value, key, 32);
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(result)) {
        throw const FormatException();
      }
      return result;
    }

    final source = value['roles'];
    if (source is! List || source.length > 512) throw const FormatException();
    final seen = <String>{};
    final roles = source.map((raw) {
      if (raw is! Map<String, Object?>) throw const FormatException();
      final key = text(raw, 'key', 128),
          name = text(raw, 'displayName', 512),
          color = text(raw, 'color', 7);
      if (key.trim().isEmpty ||
          key.trim() != key ||
          key.toLowerCase() == 'fleet_commander' ||
          !seen.add(key.toLowerCase()) ||
          name.trim().isEmpty ||
          !RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(color)) {
        throw const FormatException();
      }
      return CommunityMemberRoleOption(key, name, color);
    }).toList();
    return CommunityMemberRole._(
      reference('targetRef'),
      reference('memberRef'),
      reference('editRef'),
      text(value, 'gameName', 512),
      text(value, 'callsign', 512),
      text(value, 'roleTitle', 512),
      text(value, 'roleKey', 128),
      value['canAssign'] as bool,
      List.unmodifiable(roles),
    );
  }
}

final class CommunityMemberRoleOutcome {
  const CommunityMemberRoleOutcome(this.status, {this.error});
  final String status;
  final String? error;
  factory CommunityMemberRoleOutcome.parse(Map<String, Object?> value) {
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
    return CommunityMemberRoleOutcome(
      status as String,
      error: error as String?,
    );
  }
}
