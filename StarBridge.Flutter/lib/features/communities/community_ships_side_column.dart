import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_ship_owner.dart';
import 'community_image_decoder.dart';
import 'community_ship_detail_pane.dart';
import 'community_ships_copy.dart';
import 'community_ships_port.dart';

/// The ships page's persistent right column: in every view, the selected
/// ship's details. The page keeps a ship selected; only an empty list has none.
class CommunityShipsSideColumn extends StatelessWidget {
  const CommunityShipsSideColumn({
    required this.port,
    required this.imageDecoder,
    this.detailPage,
    this.selectedRef,
    this.lookingUp = false,
    this.pageIsCurrent = false,
    this.reconcile = false,
    this.avatar,
    this.ownerTargetFactory = communityShipOwnerTarget,
    this.includeSocialActions = true,
    this.onRefreshLibrary,
    super.key,
  });

  final CommunityShipsPort port;
  final CommunityImageDecoder imageDecoder;

  /// The page that holds [selectedRef]; null while it is being located.
  final CommunityShipsPage? detailPage;
  final String? selectedRef;
  final bool lookingUp, pageIsCurrent, reconcile;
  final Uint8List? avatar;
  final OrganizationShipOwnerTargetFactory? ownerTargetFactory;
  final bool includeSocialActions;
  final VoidCallback? onRefreshLibrary;

  static const width = 340.0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final Widget body;
    if (selectedRef != null && detailPage != null) {
      body = CommunityShipDetailPane(
        key: ValueKey(
          'community-ships-side-detail-$selectedRef-$pageIsCurrent-${detailPage!.revision}',
        ),
        port: port,
        page: detailPage!,
        shipRef: selectedRef!,
        avatar: avatar,
        ownerTargetFactory: ownerTargetFactory,
        includeSocialActions: includeSocialActions,
        imageDecoder: imageDecoder,
        inline: true,
        pageIsCurrent: pageIsCurrent,
        reconcile: reconcile,
        onRefreshLibrary: onRefreshLibrary == null
            ? null
            : (_) => onRefreshLibrary!(),
      );
    } else if (selectedRef != null && lookingUp) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Text(
        communityShipsText(context, 'sidePick'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: tokens.colors.textSecondary,
          height: 1.6,
        ),
      );
    }
    return Container(
      key: const ValueKey('community-ships-side'),
      width: width,
      padding: const EdgeInsetsDirectional.only(start: 16),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: tokens.surfaces.panel.border),
        ),
      ),
      child: body,
    );
  }
}
