/// Stable recipient account and membership instance; never use a display name.
final class CommunityMemberOverride {
  CommunityMemberOverride({
    required this.accountId,
    required this.joinedAt,
    required this.fields,
  }) {
    if (accountId.isEmpty ||
        accountId.length > 128 ||
        accountId.trim() != accountId ||
        accountId.runes.any((c) => c < 32 || c >= 127 && c <= 159) ||
        joinedAt.length > 40 ||
        !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(joinedAt) ||
        !(DateTime.tryParse(joinedAt)?.isAfter(DateTime.utc(1970)) ?? false) ||
        fields < 0 ||
        fields > 15) {
      throw const FormatException('Invalid member visibility.');
    }
  }
  final String accountId, joinedAt;
  final int fields;
  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'joinedAt': joinedAt,
    'fields': fields,
  };
  factory CommunityMemberOverride.fromJson(Map<String, Object?> value) {
    if (value.length != 3) {
      throw const FormatException('Unknown member visibility.');
    }
    return CommunityMemberOverride(
      accountId: value['accountId'] as String,
      joinedAt: value['joinedAt'] as String,
      fields: value['fields'] as int,
    );
  }
  static List<CommunityMemberOverride> validate(
    List<CommunityMemberOverride> rows,
  ) {
    if (rows.length > 1000 ||
        rows.map((r) => r.accountId.toLowerCase()).toSet().length !=
            rows.length) {
      throw const FormatException('Duplicate or excessive member overrides.');
    }
    return List.unmodifiable(rows);
  }
}
