import 'menu_overlay_text.dart';
import '../../features/communities/communities_module.dart';
import '../../features/communities/community_announcements_port.dart';
import '../../features/communities/community_chat_port.dart';
import '../../features/communities/community_ships_port.dart';

/// Same connected-feature gates as the client. Commands still check authority.
Map<String, Object> organizationSections(CommunitiesPort port) => {
  'members': MenuOverlayText('menu.overlay.organizations.members'),
  if (port is CommunityChatPort && (port as CommunityChatPort).chatAvailable)
    'chat': MenuOverlayText('socialWindow.chatTitle'),
  if (port is CommunityShipsPort && (port as CommunityShipsPort).shipsAvailable)
    'ships': MenuOverlayText('menu.overlay.organizations.ships'),
  if (port is CommunityAnnouncementsPort &&
      (port as CommunityAnnouncementsPort).announcementsAvailable)
    'announcements': MenuOverlayText(
      'menu.overlay.organizations.announcements',
    ),
};
