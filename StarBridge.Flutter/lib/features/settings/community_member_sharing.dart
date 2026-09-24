import 'community_sharing.dart';
import 'community_member_override.dart';

final class CommunitySharingMember {
  CommunitySharingMember.fromJson(Map<String, Object?> value)
    : identity = CommunityMemberOverride(
        accountId: value['accountId'] as String,
        joinedAt: value['joinedAt'] as String,
        fields: value['legacyGroupFields'] as int,
      ),
      name = value['name'] as String,
      handle = value['handle'] as String,
      defaultCanView = value['defaultCanView'] as bool,
      isSelf = value['isSelf'] as bool {
    if (value.length != 7 ||
        name.length > 256 ||
        handle.length > 256 ||
        '$name$handle'.runes.any((c) => c < 32 || c >= 127 && c <= 159)) {
      throw const FormatException('Invalid member directory row.');
    }
  }
  final CommunityMemberOverride identity;
  final String name, handle;
  final bool defaultCanView, isSelf;
  String get accountId => identity.accountId;
  String get joinedAt => identity.joinedAt;
  int get legacyGroupFields => identity.fields;
  CommunityMemberOverride? overrideIn(CommunitySharingScope scope) => scope
      .memberOverrides
      ?.where(
        (r) =>
            r.accountId.toLowerCase() == accountId.toLowerCase() &&
            r.joinedAt == joinedAt,
      )
      .firstOrNull;
  int effectiveFields(CommunitySharingScope scope) =>
      scope.fields & (overrideIn(scope)?.fields ?? (defaultCanView ? 15 : 0));
}

final class CommunityMemberPage {
  CommunityMemberPage.fromJson(
    Map<String, Object?> value,
    CommunitySharingScope scope,
    int requestedOffset,
    String? expectedRevision,
  ) : revision = value['revision'] as String,
      offset = value['offset'] as int,
      total = value['total'] as int,
      members = List.unmodifiable(
        (value['members'] as List).map(
          (raw) => CommunitySharingMember.fromJson(
            (raw as Map).cast<String, Object?>(),
          ),
        ),
      ) {
    if (value.length != 7 ||
        value['schemaVersion'] != 3 ||
        value['code'] != scope.code ||
        value['joinedAt'] != scope.joinedAt ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(revision) ||
        offset != requestedOffset ||
        offset > 0 && revision != expectedRevision ||
        total < offset ||
        total > 100000 ||
        members.length != (total - offset).clamp(0, 100) ||
        members.map((r) => r.accountId.toLowerCase()).toSet().length !=
            members.length) {
      throw const FormatException('Incomplete or changed member directory.');
    }
  }
  final String revision;
  final int offset, total;
  final List<CommunitySharingMember> members;
}

abstract interface class CommunityMemberSharingPort {
  bool get communityMemberSharingSupported;
  Future<CommunityMemberPage> readCommunityMembers(
    CommunitySharingScope scope, {
    int offset = 0,
    String? revision,
  });
}
