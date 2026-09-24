import 'communities_module.dart';
import 'community_workspace_port.dart';
import 'example_community_member_roles.dart';

/// Explicit example-only rows. Never used as a production read fallback.
CommunityWorkspace exampleCommunityWorkspace(
  CommunityCard card,
  String query,
  int offset, {
  Map<String, String> assignments = const {},
  Set<String> removed = const {},
  String? ownerRef,
  bool formerOwnerLeft = false,
  Map<String, Object?> profile = const {},
  bool hasLogo = false,
}) {
  final transferred = ownerRef != null;
  bool isOwner(int index) =>
      index.toRadixString(16).padLeft(32, '0') == (ownerRef ?? '0' * 32);
  final total = (card.memberCount ?? 1) + removed.length;
  final rows = List.generate(
    total,
    (index) => <String, Object?>{
      'memberRef': index.toRadixString(16).padLeft(32, '0'),
      'gameName': index == 0 ? 'Example_Owner' : 'Example_Member_$index',
      'callsign': index == 0 ? '示例组织所有者' : '示例成员 $index',
      'roleTitle': isOwner(index)
          ? '负责人'
          : transferred && !formerOwnerLeft && index == 0
          ? '副负责人'
          : ExampleCommunityMemberRoles.name(
              assignments[index.toRadixString(16).padLeft(32, '0')] ?? '',
            ),
      'roleColor': isOwner(index)
          ? '#F2B84B'
          : ExampleCommunityMemberRoles.color(
              assignments[index.toRadixString(16).padLeft(32, '0')] ?? '',
            ),
      'isOwner': isOwner(index),
      'isSelf': card.relationship == 'owner' || transferred
          ? index == 0
          : index == 1,
      'online': index < 5,
      'hasAvatar': false,
      'liveStatus': switch (index) {
        0 => 'InGame',
        1 => 'AppOnline',
        2 => 'Away',
        3 => 'Paused',
        _ => 'Offline',
      },
      'ship': index == 0 ? 'C2 Hercules' : null,
      'location': index == 0 ? '奥里森' : null,
      'locationConfidence': null,
      'serverRegion': index == 0 ? 'US' : null,
      'arrivalPendingConfirmation': false,
      'arrivalTargetCode': null,
      'joinedAt': '2026-09-01T12:00:00Z',
      'lastUpdated': '2026-09-07T12:00:00Z',
    },
  );
  final filtered = rows
      .where((row) => !removed.contains(row['memberRef']))
      .where(
        (row) => '${row['gameName']} ${row['callsign']} ${row['roleTitle']}'
            .toLowerCase()
            .contains(query.trim().toLowerCase()),
      )
      .toList();
  if (offset < 0 || offset > filtered.length) {
    throw const CommunityFailure('refreshRequired');
  }
  final page = filtered.skip(offset).take(20).toList();
  return CommunityWorkspace.parse({
    'schemaVersion': 1,
    'targetRef': card.targetRef,
    'code': 'EXAMPLE',
    'name': card.name,
    'description': card.description,
    'tags': card.tags,
    'language': card.language,
    'activeTime': card.activeTime,
    'timeZoneId': profile['timeZoneId'] ?? 'UTC',
    'websiteUrl': profile['websiteUrl'],
    'activeSystemIds': card.systems,
    'activityWindows': profile['activityWindows'] ?? <Object?>[],
    'externalContacts': profile['externalContacts'] ?? <Object?>[],
    'hasLogo': hasLogo,
    'hasBanner': false,
    'fetchedAt': DateTime.now().toUtc().toIso8601String(),
    'access': {
      for (final key in const [
        'isOwner',
        'canEditProfile',
        'canEditLogo',
        'canEditBanner',
        'canReviewApplications',
        'canRemoveMembers',
        'canCreateInvite',
        'canManageAnnouncements',
        'canViewLogs',
      ])
        key:
            card.relationship == 'owner' ||
            transferred &&
                !formerOwnerLeft &&
                const {
                  'canEditProfile',
                  'canReviewApplications',
                  'canRemoveMembers',
                  'canManageAnnouncements',
                }.contains(key),
    },
    'query': query.trim(),
    'offset': offset,
    'totalCount': total - removed.length,
    'matchedCount': filtered.length,
    'next': offset + page.length < filtered.length
        ? offset + page.length
        : null,
    'members': page,
  });
}
