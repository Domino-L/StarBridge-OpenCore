import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_dialog.dart';
import '../common/organization_ship_owner.dart';
import 'community_image_decoder.dart';
import 'community_ship_detail_pane.dart';
import 'community_ships_port.dart';

/// The ship details as a dialog: narrow windows, and the dialog tests.
/// Wide ships pages show the same pane inline in their side column.
class CommunityShipDetailDialog extends StatelessWidget {
  const CommunityShipDetailDialog({
    required this.port,
    required this.page,
    required this.shipRef,
    this.avatar,
    this.ownerTargetFactory = communityShipOwnerTarget,
    this.includeSocialActions = true,
    this.imageDecoder = decodeCommunityImage,
    super.key,
  });
  final CommunityShipsPort port;
  final CommunityShipsPage page;
  final String shipRef;
  final Uint8List? avatar;
  final OrganizationShipOwnerTargetFactory? ownerTargetFactory;
  final bool includeSocialActions;
  final CommunityImageDecoder imageDecoder;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 960,
        height: (screen.height - 48).clamp(0, 760),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: CommunityShipDetailPane(
            port: port,
            page: page,
            shipRef: shipRef,
            avatar: avatar,
            ownerTargetFactory: ownerTargetFactory,
            includeSocialActions: includeSocialActions,
            imageDecoder: imageDecoder,
            onClose: (source) =>
                dismissStarBridgeDialog(context, source: source, result: false),
            onRefreshLibrary: (source) =>
                dismissStarBridgeDialog(context, source: source, result: true),
          ),
        ),
      ),
    );
  }
}
