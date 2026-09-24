import 'dart:convert';

import 'community_profile_port.dart' show CommunityProfileOutcome;

abstract interface class CommunityRolesPort {
  Stream<void> get invalidations;
  bool get rolesAvailable;
  Future<CommunityEditingRoles> readRoles({String? targetRef, String? editRef});
  Future<CommunityProfileOutcome> saveRoles(
    String requestId,
    String editRef,
    List<CommunityRole> roles, {
    bool confirmUncertainRetry = false,
  });
}

const communityRoleNameLimit = 12;
const communityRoleDescriptionLimit = 80;

const communityRolePermissions = <String, List<String>>{
  'profile': [
    'fleet.profile.edit',
    'announcements.manage',
    'broadcasts.publish',
    'fleet.avatar.edit',
  ],
  'members': ['members.review', 'members.remove'],
  'audit': ['audit.view', 'audit.delete'],
};

final class CommunityRole {
  CommunityRole({
    required this.key,
    required this.name,
    required this.description,
    required this.color,
    required this.sortOrder,
    required this.system,
    required this.enabled,
    required this.memberCount,
    required List<String> permissions,
  }) : permissions = List.unmodifiable(permissions);
  final String key, name, description, color;
  final int sortOrder, memberCount;
  final bool system, enabled;
  final List<String> permissions;
  bool get owner => key == 'fleet_commander';
  CommunityRole copy({
    String? key,
    String? name,
    String? description,
    String? color,
    int? sortOrder,
    bool? system,
    bool? enabled,
    int? memberCount,
    List<String>? permissions,
  }) => CommunityRole(
    key: key ?? this.key,
    name: name ?? this.name,
    description: description ?? this.description,
    color: color ?? this.color,
    sortOrder: sortOrder ?? this.sortOrder,
    system: system ?? this.system,
    enabled: enabled ?? this.enabled,
    memberCount: memberCount ?? this.memberCount,
    permissions: permissions ?? this.permissions,
  );
  Map<String, Object?> toDraft() => {
    'key': key,
    'displayName': name,
    'description': description,
    'color': color,
    'sortOrder': sortOrder,
    'isEnabled': enabled,
    'permissions': permissions,
  };
  factory CommunityRole.parse(Map<String, Object?> row) {
    final permissions = row['permissions'];
    if (permissions is! List ||
        permissions.length > 256 ||
        permissions.any(
          (value) =>
              value is! String ||
              value.trim().isEmpty ||
              value.length > 128 ||
              _controls.hasMatch(value),
        )) {
      throw const FormatException();
    }
    final key = _text(row, 'key', 128), name = _text(row, 'displayName', 512);
    if (key.trim().isEmpty || key.trim() != key || name.trim().isEmpty) {
      throw const FormatException();
    }
    final order = row['sortOrder'], count = row['memberCount'];
    if (order is! int ||
        order < -2147483648 ||
        order > 2147483647 ||
        count is! int ||
        count < 0 ||
        count > 2147483647) {
      throw const FormatException();
    }
    for (final key in ['createdAt', 'updatedAt']) {
      if (DateTime.tryParse(_text(row, key, 64)) == null) {
        throw const FormatException();
      }
    }
    return CommunityRole(
      key: key,
      name: name,
      description: _text(row, 'description', 4096, multiline: true),
      color: _text(row, 'color', 64),
      sortOrder: order,
      memberCount: count,
      system: _flag(row, 'isSystem'),
      enabled: _flag(row, 'isEnabled'),
      permissions: permissions.cast<String>(),
    );
  }
}

final class CommunityEditingRoles {
  CommunityEditingRoles._(
    this.targetRef,
    this.editRef,
    this.code,
    this.name,
    this.revision,
    this.canAssignMembers,
    List<CommunityRole> roles,
  ) : roles = List.unmodifiable(roles);
  final String targetRef, editRef, code, name;
  final int revision;
  final bool canAssignMembers;
  final List<CommunityRole> roles;
  factory CommunityEditingRoles.parse(Map<String, Object?> body) {
    if (body['schemaVersion'] != 1 ||
        utf8.encode(jsonEncode(body)).length > 256 * 1024) {
      throw const FormatException();
    }
    final target = _text(body, 'targetRef', 32),
        edit = _text(body, 'editRef', 32);
    if (!_reference.hasMatch(target) || !_reference.hasMatch(edit)) {
      throw const FormatException();
    }
    final revision = body['profileRevision'];
    if (revision is! int || revision < 0 || revision > 9007199254740991) {
      throw const FormatException();
    }
    final access = _map(body['access']);
    if (!_flag(access, 'canEditRoles')) throw const FormatException();
    final source = body['roles'];
    if (source is! List || source.length > 512) throw const FormatException();
    final roles = source.map((row) => CommunityRole.parse(_map(row))).toList();
    if (roles.map((r) => r.key.toLowerCase()).toSet().length != roles.length) {
      throw const FormatException();
    }
    final code = _text(body, 'code', 256), name = _text(body, 'name', 512);
    if (code.isEmpty || name.isEmpty) throw const FormatException();
    return CommunityEditingRoles._(
      target,
      edit,
      code,
      name,
      revision,
      _flag(access, 'canAssignMembers'),
      roles,
    );
  }
}

final _controls = RegExp(r'[\x00-\x1f\x7f]');
final _reference = RegExp(r'^[a-f0-9]{32}$');
String _text(
  Map<String, Object?> row,
  String key,
  int max, {
  bool multiline = false,
}) {
  final text = row[key];
  if (text is! String ||
      text.length > max ||
      _controls.hasMatch(
        multiline ? text.replaceAll(RegExp(r'[\r\n\t]'), '') : text,
      )) {
    throw const FormatException();
  }
  return text;
}

bool _flag(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! bool) throw const FormatException();
  return value;
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException();
  return Map<String, Object?>.from(value);
}
