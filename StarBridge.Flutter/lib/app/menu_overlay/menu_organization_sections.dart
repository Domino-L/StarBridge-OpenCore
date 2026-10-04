import '../../features/communities/communities_module.dart';
import '../../features/communities/community_announcements_port.dart';
import '../../features/communities/community_chat_port.dart';
import '../../features/communities/community_ships_port.dart';

/// Same connected-feature gates as the client. Commands still check authority.
Map<String, String> organizationSections(CommunitiesPort port) => {
  'members': '成员',
  if (port is CommunityChatPort && (port as CommunityChatPort).chatAvailable)
    'chat': '聊天',
  if (port is CommunityShipsPort && (port as CommunityShipsPort).shipsAvailable)
    'ships': '舰船',
  if (port is CommunityAnnouncementsPort &&
      (port as CommunityAnnouncementsPort).announcementsAvailable)
    'announcements': '公告',
};
