import 'community_member_override.dart';

/// Keep the server's exact timestamp text: Dart cannot round-trip .NET's
/// seventh fractional digit. This identifies a membership, not a display date.
final class CommunitySharingScope {
  CommunitySharingScope({
    required this.code,
    required this.joinedAt,
    required this.fields,
    required this.administratorsCanView,
    required this.allMembersCanView,
    List<String> visibilityGroupIds = const [],
    List<CommunityMemberOverride>? memberOverrides,
  }) : memberOverrides = memberOverrides == null
           ? null
           : CommunityMemberOverride.validate(memberOverrides),
       visibilityGroupIds = List.unmodifiable(visibilityGroupIds) {
    if (!_key(code, 256) ||
        !_timestamp(joinedAt) ||
        fields < 0 ||
        fields > 15 ||
        visibilityGroupIds.length > 12 ||
        visibilityGroupIds.any((id) => !_key(id, 128)) ||
        visibilityGroupIds.map((id) => id.toLowerCase()).toSet().length !=
            visibilityGroupIds.length) {
      throw const FormatException('Invalid organization sharing scope.');
    }
  }
  final String code, joinedAt;
  final int fields;
  final bool administratorsCanView, allMembersCanView;
  final List<String> visibilityGroupIds;
  final List<CommunityMemberOverride>? memberOverrides;
  CommunitySharingScope copyWith({
    int? fields,
    bool? administratorsCanView,
    bool? allMembersCanView,
    List<CommunityMemberOverride>? memberOverrides,
    bool retireGroups = false,
  }) => CommunitySharingScope(
    code: code,
    joinedAt: joinedAt,
    fields: fields ?? this.fields,
    administratorsCanView: administratorsCanView ?? this.administratorsCanView,
    allMembersCanView: allMembersCanView ?? this.allMembersCanView,
    visibilityGroupIds: retireGroups ? const [] : visibilityGroupIds,
    memberOverrides: memberOverrides ?? this.memberOverrides,
  );
  Map<String, Object?> toJson() => {
    'code': code,
    'joinedAt': joinedAt,
    'fields': fields,
    'administratorsCanView': administratorsCanView,
    'allMembersCanView': allMembersCanView,
    'visibilityGroupIds': visibilityGroupIds,
    if (memberOverrides != null)
      'memberOverrides': memberOverrides!.map((row) => row.toJson()).toList(),
  };
  factory CommunitySharingScope.fromJson(Map<String, Object?> value) {
    if (value.length != 6 &&
        !(value.length == 7 && value.containsKey('memberOverrides'))) {
      throw const FormatException('Unknown sharing scope.');
    }
    return CommunitySharingScope(
      code: value['code'] as String,
      joinedAt: value['joinedAt'] as String,
      fields: value['fields'] as int,
      administratorsCanView: value['administratorsCanView'] as bool,
      allMembersCanView: value['allMembersCanView'] as bool,
      visibilityGroupIds: (value['visibilityGroupIds'] as List).cast<String>(),
      memberOverrides: value['memberOverrides'] == null
          ? null
          : (value['memberOverrides'] as List)
                .map(
                  (raw) => CommunityMemberOverride.fromJson(
                    (raw as Map).cast<String, Object?>(),
                  ),
                )
                .toList(),
    );
  }
  static List<CommunitySharingScope> validate(
    List<CommunitySharingScope> rows,
  ) {
    if (rows.length > 64 ||
        rows.map((r) => r.code.toLowerCase()).toSet().length != rows.length) {
      throw const FormatException(
        'Duplicate or excessive organization scopes.',
      );
    }
    return List.unmodifiable(rows);
  }
}

final class CommunitySharingTarget {
  CommunitySharingTarget({
    required this.code,
    required this.name,
    required this.joinedAt,
    this.logoImageData,
  }) {
    if (!_key(code, 256) || !_key(name, 256) || !_timestamp(joinedAt)) {
      throw const FormatException('Invalid membership target.');
    }
  }
  final String code, name, joinedAt;
  final String? logoImageData;
  bool matches(CommunitySharingScope scope) =>
      scope.code.toLowerCase() == code.toLowerCase() &&
      scope.joinedAt == joinedAt;
  CommunitySharingScope choice({int fields = 0}) => CommunitySharingScope(
    code: code,
    joinedAt: joinedAt,
    fields: fields,
    administratorsCanView: false,
    allMembersCanView: true,
  );
}

final class CommunitySharingTargets {
  CommunitySharingTargets({
    required List<CommunitySharingTarget> communities,
    this.primaryFleetCode,
  }) : communities = List.unmodifiable(communities) {
    CommunitySharingScope.validate(communities.map((t) => t.choice()).toList());
    if (primaryFleetCode != null &&
        !communities.any((t) => t.code == primaryFleetCode)) {
      throw const FormatException('Unknown primary organization.');
    }
  }
  final String? primaryFleetCode;
  final List<CommunitySharingTarget> communities;
  CommunitySharingTargets renamed(String code, String name) =>
      CommunitySharingTargets(
        primaryFleetCode: primaryFleetCode,
        communities: communities
            .map(
              (row) => row.code == code
                  ? CommunitySharingTarget(
                      code: row.code,
                      name: name,
                      joinedAt: row.joinedAt,
                      logoImageData: row.logoImageData,
                    )
                  : row,
            )
            .toList(),
      );
  factory CommunitySharingTargets.fromJson(Map<String, Object?> value) {
    if (value['schemaVersion'] != 2 ||
        value.keys.any(
          (k) => !const {
            'schemaVersion',
            'primaryFleetCode',
            'communities',
          }.contains(k),
        )) {
      throw const FormatException('Unsupported organization sharing contract.');
    }
    return CommunitySharingTargets(
      primaryFleetCode: value['primaryFleetCode'] as String?,
      communities: (value['communities'] as List).map((raw) {
        final row = (raw as Map).cast<String, Object?>();
        if (row.length != 3 &&
            !(row.length == 4 && row.containsKey('logoImageData'))) {
          throw const FormatException('Unknown membership shape.');
        }
        return CommunitySharingTarget(
          code: row['code'] as String,
          name: row['name'] as String,
          joinedAt: row['joinedAt'] as String,
          logoImageData: row['logoImageData'] as String?,
        );
      }).toList(),
    );
  }
}

abstract interface class CommunitySharingPort {
  bool get communitySharingSupported;
  Future<CommunitySharingTargets> readCommunityTargets();
}

bool _key(String value, int max) =>
    value.isNotEmpty &&
    value.length <= max &&
    value.trim() == value &&
    !value.runes.any((c) => c < 32 || c >= 127 && c <= 159);
bool _timestamp(String value) =>
    value.length <= 40 &&
    RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value) &&
    (DateTime.tryParse(value)?.isAfter(DateTime.utc(1970)) ?? false);
