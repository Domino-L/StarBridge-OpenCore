import '../../features/communities/community_member_runtime.dart';
import '../../features/communities/community_workspace_copy.dart';
import '../../features/communities/community_workspace_port.dart';
import 'menu_organization_view.dart';

({Map<String, Object?> row, Map<String, Object?> presentation})
organizationMemberPresentation(
  CommunityWorkspaceMember member,
  String? avatar,
  String profileKey,
) {
  final runtime = communityMemberRuntime(
    member,
    text: (key) => communityWorkspaceCopy[key]?.$1 ?? '—',
    regionText: (value) => value,
  );
  final presence = organizationPresence(member.online, member.liveStatus);
  return (
    row: {
      'title': member.displayName,
      'detail':
          '${member.roleTitle} · ${organizationPresenceText(presence)}\n${runtime.server} · ${runtime.ship} · ${runtime.location}',
    },
    presentation: {
      'handle': member.gameName,
      'role': member.roleTitle,
      'roleColor': member.roleColor,
      'presence': presence,
      'isSelf': member.isSelf,
      'avatar': avatar,
      'profileKey': profileKey,
      'ship': runtime.ship,
      'location': runtime.location,
      'server': runtime.server,
    },
  );
}
