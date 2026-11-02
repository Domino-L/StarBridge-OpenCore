import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../communities/community_ships_port.dart';
import 'user_avatar_menu.dart';

/// Return a target issued by the source's current authorization projection.
/// Null means no owner action; callers must not derive targets from labels.
typedef OrganizationShipOwnerTargetFactory = UserTarget? Function(
  String targetRef,
  CommunitySharedShip ship,
);

/// Existing community default; official callers explicitly replace or disable
/// this factory. Official references must never be padded into community refs.
UserTarget communityShipOwnerTarget(
  String targetRef,
  CommunitySharedShip ship,
) => UserTarget.community(
  targetRef,
  ship.ownerMemberRef,
  query: ship.ownerGameName,
);

/// The same owner action seam is used by the ship row and reauthorized detail.
/// Without a target the avatar is ordinary content, with no menu wrapper.
class OrganizationShipOwner extends StatelessWidget {
  const OrganizationShipOwner({
    required this.targetRef,
    required this.ship,
    required this.name,
    required this.child,
    this.avatarBytes,
    this.targetFactory = communityShipOwnerTarget,
    this.includeSocialActions = true,
    super.key,
  });

  final String targetRef, name;
  final CommunitySharedShip ship;
  final Widget child;
  final Uint8List? avatarBytes;
  final OrganizationShipOwnerTargetFactory? targetFactory;
  final bool includeSocialActions;

  @override
  Widget build(BuildContext context) {
    final target = targetFactory?.call(targetRef, ship);
    if (target == null) return child;
    return UserAvatarMenu(
      name: name,
      avatarBytes: avatarBytes,
      isSelf: ship.ownerIsSelf,
      target: target,
      includeSocialActions: includeSocialActions,
      child: child,
    );
  }
}
