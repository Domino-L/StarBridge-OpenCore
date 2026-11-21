import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/ship_catalog_display.dart';
import '../../shared/ships/ship_category_colors.dart';
import '../../shared/ships/ship_classification_tag.dart';
import '../common/organization_ship_owner.dart';
import 'community_catalog_ship_image.dart';
import 'community_image_decoder.dart';
import 'community_ship_card_mark.dart';
import 'community_ship_loaners.dart';
import 'community_ship_owner_avatar.dart';
import 'community_ship_row_surface.dart';
import 'community_ships_copy.dart';
import 'community_ships_port.dart';
import '../../design_system/surfaces/light_visual_text.dart';

/// The ship card of the redone page (user decision 2026-10-29, option D, "按
/// 照预览来，不要小图标"): the catalog art with the name over it, then the
/// size, role and status tags, the owner, and the price with the replacement
/// count. The whole card opens the details (user 2026-10-30); the owner's
/// avatar keeps its own menu. The maker's Fan Kit logo sits in the art's
/// lower-right corner beside the name and the ship's silhouette in the card's
/// lower-right corner beside the price (user 11-05 option C; 11-14 "还是在右下
/// 角吧" / "我是说图片的右下角"); neither changes a card's height.
class CommunityShipCard extends StatelessWidget {
  const CommunityShipCard({
    required this.ship,
    required this.targetRef,
    required this.avatarBytes,
    required this.avatarLoading,
    required this.imageDecoder,
    required this.onDetails,
    required this.ownerTargetFactory,
    required this.includeSocialActions,
    this.selected = false,
    super.key,
  });

  final CommunitySharedShip ship;
  final String targetRef;
  final Uint8List? avatarBytes;
  final bool avatarLoading;
  final CommunityImageDecoder imageDecoder;
  final VoidCallback onDetails;
  final OrganizationShipOwnerTargetFactory? ownerTargetFactory;
  final bool includeSocialActions, selected;

  @override
  Widget build(BuildContext context) {
    String t(String key) => communityShipsText(context, key);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final text = Theme.of(context).textTheme;
    final owner = ship.ownerCallsign.isNotEmpty
        ? ship.ownerCallsign
        : ship.ownerGameName.isNotEmpty
        ? ship.ownerGameName
        : t('owner');
    final status = ship.catalogStatus?.toLowerCase() ?? '';
    final statusColor = const {'flyable', '可飞', '可飛'}.contains(status)
        ? colors.success
        : status.contains('concept') || status.contains('概念')
        ? colors.warning
        : colors.textSecondary;
    final subtitle = ship.subtitleFor(
      Localizations.localeOf(context).languageCode,
    );
    final priced = ShipCatalogDisplay.usdCents(ship.catalogPriceUsd) != null;
    final name = ship.displayName.isEmpty ? ship.code : ship.displayName;
    return CommunityShipRowSurface(
      key: ValueKey('community-ship-card-${ship.shipRef}'),
      card: true,
      selected: selected,
      child: StarBridgeActionRow(
        controlKey: ValueKey('community-ship-details-${ship.shipRef}'),
        semanticLabel: '$name · ${t('view')}',
        semanticSelected: selected,
        baseRadius: 0,
        hoverFace: false,
        inheritContentStyle: true,
        onActivate: (_, _) => onDetails(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: ValueKey('community-ship-card-image-${ship.shipRef}'),
              height: 124,
              color: tokens.surfaces.raised.fill,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Edge to edge, as the approved preview (user 2026-10-29:
                  // 严格按预览来); the list keeps the uncropped art.
                  CommunityCatalogShipImage(
                    model: ship.code,
                    asset: ship.catalogImageAsset ?? ship.catalogThumbnailAsset,
                    compact: true,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            tokens.surfaces.panel.fill.withValues(alpha: 0),
                            tokens.surfaces.panel.fill.withValues(alpha: .92),
                          ],
                        ),
                      ),
                      child: Row(
                        key: ValueKey(
                          'community-ship-name-strip-${ship.shipRef}',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: fadeOverflow(context),
                                  softWrap: false,
                                  style: text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    shadows: [
                                      Shadow(
                                        color: tokens.surfaces.ground.fill,
                                        blurRadius: 3,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                                if (subtitle != null)
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: fadeOverflow(context),
                                    softWrap: false,
                                    style: text.labelSmall?.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          CommunityShipMakerLogo(ship: ship),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    key: ValueKey('community-ship-tags-${ship.shipRef}'),
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ShipClassificationTag(
                        label: communityShipDisplayText(
                          context,
                          ship.displaySpec,
                        ),
                        color: shipSizeColor(context, ship.displaySpec),
                      ),
                      ShipClassificationTag(
                        label: communityShipDisplayText(
                          context,
                          ship.displayRole,
                        ),
                        color: shipCategoryColor(
                          context,
                          ship.displayCategory?.toLowerCase() ?? 'unknown',
                        ),
                      ),
                      ShipClassificationTag(
                        label:
                            ship.catalogStatus == null ||
                                ship.catalogStatus!.isEmpty
                            ? t('unknown')
                            : ship.catalogStatus!,
                        color: statusColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CommunityShipSilhouetteFooter(
                    ship: ship,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            OrganizationShipOwner(
                              targetRef: targetRef,
                              ship: ship,
                              name: owner,
                              avatarBytes: avatarBytes,
                              targetFactory: ownerTargetFactory,
                              includeSocialActions: includeSocialActions,
                              child: CommunityShipOwnerAvatar(
                                ship: ship,
                                bytes: avatarBytes,
                                decoder: imageDecoder,
                                loading: avatarLoading,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$owner${ship.ownerIsSelf ? ' · ${t('self')}' : ''}',
                                maxLines: 1,
                                overflow: fadeOverflow(context),
                                softWrap: false,
                                style: text.bodySmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                ShipCatalogDisplay.usdText(
                                      ship.catalogPriceUsd,
                                    ) ??
                                    t('unpublished'),
                                maxLines: 1,
                                overflow: fadeOverflow(context),
                                softWrap: false,
                                style: text.bodySmall?.copyWith(
                                  color: priced
                                      ? colors.info
                                      : colors.textSecondary,
                                ),
                              ),
                            ),
                            CommunityShipLoanerCount(ship: ship),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
