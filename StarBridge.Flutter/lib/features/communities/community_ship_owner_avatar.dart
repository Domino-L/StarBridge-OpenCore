import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/presence_color.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_image_decoder.dart';
import 'community_ships_port.dart';
import 'community_workspace_image.dart';

/// The copy key of the owner's presence, null when the source has none.
String? communityShipPresenceKey(CommunitySharedShip ship) =>
    !ship.ownerPresenceKnown
    ? null
    : !ship.ownerOnline
    ? 'presence.offline'
    : ship.ownerLiveStatus.toLowerCase() == 'ingame'
    ? 'presence.inGame'
    : ship.ownerLiveStatus.toLowerCase() == 'away'
    ? 'presence.away'
    : 'presence.online';

/// An owner's avatar with the presence dot on its lower right corner (user
/// 2026-10-30: the dot belongs to the person, never far from them). The box
/// is two pixels larger than the avatar so the dot stays inside it and a
/// wrapping control can't clip it.
class CommunityShipOwnerAvatar extends StatelessWidget {
  const CommunityShipOwnerAvatar({
    required this.ship,
    required this.bytes,
    required this.decoder,
    required this.size,
    this.loading = false,
    this.maxWidth = 64,
    super.key,
  });

  final CommunitySharedShip ship;
  final Uint8List? bytes;
  final CommunityImageDecoder decoder;
  final double size;
  final bool loading;
  final int maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final presence = communityShipPresenceKey(ship);
    final avatar = SizedBox(
      width: size + 2,
      height: size + 2,
      child: Stack(
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CommunityWorkspaceImage(
              bytes: bytes,
              decoder: decoder,
              maxWidth: maxWidth,
              loading: loading,
              icon: StandardIconSemantic.person,
            ),
          ),
          if (presence != null)
            PositionedDirectional(
              end: 0,
              bottom: 0,
              child: Container(
                key: ValueKey('community-ship-presence-${ship.shipRef}'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: presenceColor(tokens.colors, presence),
                  border: Border.all(
                    color: tokens.surfaces.ground.fill,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return presence == null
        ? avatar
        : StarBridgeTooltip(
            message: AppStrings.of(context).text(presence),
            child: avatar,
          );
  }
}
