import '../common/user_avatar_menu.dart';
import '../communities/community_ship_avatar_access.dart';
import '../communities/community_ships_port.dart';

/// Display references and profile targets are different Host-issued scopes.
/// This interface never derives a profile target from a name or a ship ID.
abstract interface class OfficialFleetShipOwnerAccess {
  UserTarget? ownerTarget(String targetRef, CommunitySharedShip ship);
  CommunityShipAvatarAccess get avatarAccess;
}
