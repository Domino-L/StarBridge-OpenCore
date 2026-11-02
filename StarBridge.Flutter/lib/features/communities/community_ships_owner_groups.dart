import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo.dart';
import '../../shared/ships/ship_category_colors.dart';
import 'community_catalog_ship_image.dart';
import 'community_image_decoder.dart';
import 'community_ship_owner_avatar.dart';
import 'community_ship_row_surface.dart';
import 'community_ship_statistics.dart';
import 'community_ships_copy.dart';
import 'community_ships_port.dart';

/// 按持有人 (user decision 2026-10-29, option D): the whole shared
/// inventory grouped by owner, owners online first. Ships follow their
/// owner, which is how the operation model will occupy them later.
class CommunityShipsOwnerGroups extends StatelessWidget {
  const CommunityShipsOwnerGroups({
    required this.ships,
    required this.selectedRef,
    required this.onSelect,
    required this.decoder,
    this.avatarOf,
    this.avatarLoading,
    this.controller,
    super.key,
  });

  final List<CommunitySharedShip> ships;
  final String? selectedRef;
  final ValueChanged<CommunitySharedShip> onSelect;
  final CommunityImageDecoder decoder;
  final Uint8List? Function(String memberRef)? avatarOf;
  final bool Function(String memberRef)? avatarLoading;
  final ScrollController? controller;

  static const _tileMinWidth = 168.0, _tileGap = 8.0;

  static String presenceKey(CommunitySharedShip ship) =>
      communityShipPresenceKey(ship);

  static int _presenceRank(CommunitySharedShip ship) => const [
    'presence.inGame',
    'presence.online',
    'presence.away',
    'presence.offline',
  ].indexOf(presenceKey(ship));

  /// Owners online first, then by name; ships largest first, then by name.
  static List<List<CommunitySharedShip>> group(
    Iterable<CommunitySharedShip> ships,
  ) {
    final byOwner = <String, List<CommunitySharedShip>>{};
    for (final ship in ships) {
      byOwner.putIfAbsent(ship.ownerMemberRef, () => []).add(ship);
    }
    final groups = byOwner.values.toList();
    for (final list in groups) {
      list.sort((a, b) {
        final size = CommunityShipStatistics.sizeRank(b)
            .compareTo(CommunityShipStatistics.sizeRank(a));
        if (size != 0) return size;
        return a.displayName.compareTo(b.displayName);
      });
    }
    groups.sort((a, b) {
      final self =
          (b.first.ownerIsSelf ? 1 : 0) - (a.first.ownerIsSelf ? 1 : 0);
      if (self != 0) return self;
      final presence = _presenceRank(a.first).compareTo(_presenceRank(b.first));
      if (presence != 0) return presence;
      return CommunityShipStatistics.owner(a.first)
          .compareTo(CommunityShipStatistics.owner(b.first));
    });
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    String t(String key) => communityShipsText(context, key);
    final groups = group(ships);
    return ListView.separated(
      key: const ValueKey('community-ships-owner-groups'),
      controller: controller,
      padding: const EdgeInsetsDirectional.only(end: 16),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final list = groups[index];
        final first = list.first;
        final presence = presenceKey(first);
        final name = CommunityShipStatistics.owner(first);
        final bytes = avatarOf?.call(first.ownerMemberRef);
        return Container(
          key: ValueKey('community-ships-owner-${first.ownerMemberRef}'),
          decoration: BoxDecoration(
            color: tokens.surfaces.panel.fill,
            border: Border.all(color: OrganizationHoloColors(context).hair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: OrganizationHoloColors(context).hair,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    CommunityShipOwnerAvatar(
                      ship: first,
                      bytes: bytes,
                      decoder: decoder,
                      size: 26,
                      maxWidth: 96,
                      loading:
                          bytes == null &&
                          first.ownerHasAvatar &&
                          (avatarLoading?.call(first.ownerMemberRef) ?? false),
                    ),
                    const SizedBox(width: 10),
                    // Name and presence at the start, the count at the end.
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${name.isEmpty ? t('owner') : name}${first.ownerIsSelf ? ' · ${t('self')}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            AppStrings.of(context).text(presence),
                            style: text.bodySmall?.copyWith(
                              color: tokens.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      t('ownerShips').replaceAll('{count}', '${list.length}'),
                      style: text.bodySmall?.copyWith(
                        color: tokens.colors.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                // The tiles share the whole row, so the art fills the group
                // instead of leaving a gap at its end (user 2026-10-30).
                child: LayoutBuilder(
                  builder: (context, box) {
                    final columns =
                        ((box.maxWidth + _tileGap) / (_tileMinWidth + _tileGap))
                            .floor()
                            .clamp(1, 12);
                    final width =
                        (box.maxWidth - _tileGap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: _tileGap,
                      runSpacing: _tileGap,
                      children: [
                        for (final ship in list)
                          _OwnerShipTile(
                            ship: ship,
                            width: width,
                            selected: ship.shipRef == selectedRef,
                            onSelect: () => onSelect(ship),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OwnerShipTile extends StatelessWidget {
  const _OwnerShipTile({
    required this.ship,
    required this.width,
    required this.selected,
    required this.onSelect,
  });
  final CommunitySharedShip ship;
  final double width;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final name = ship.displayName.isEmpty ? ship.code : ship.displayName;
    final size = communityShipDisplayText(context, ship.displaySpec);
    final role = communityShipDisplayText(context, ship.displayRole);
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        selected: selected,
        label: name,
        child: GestureDetector(
          key: ValueKey('community-ships-owner-tile-${ship.shipRef}'),
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          child: CommunityShipRowSurface(
            card: true,
            selected: selected,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  // The art keeps its shape as the tile widens.
                  height: width * 78 / 168,
                  child: Container(
                    color: tokens.surfaces.raised.fill,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Edge to edge with the name over the art, as the
                        // approved preview (2026-10-29).
                        CommunityCatalogShipImage(
                          asset:
                              ship.catalogImageAsset ??
                              ship.catalogThumbnailAsset,
                          compact: true,
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  tokens.surfaces.ground.fill.withValues(
                                    alpha: 0,
                                  ),
                                  tokens.surfaces.ground.fill.withValues(
                                    alpha: .92,
                                  ),
                                ],
                              ),
                            ),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: text.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$size · '),
                            TextSpan(
                              text: role,
                              style: TextStyle(
                                color: shipCategoryColor(
                                  context,
                                  ship.displayCategory?.toLowerCase() ??
                                      'unknown',
                                ),
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: text.labelSmall?.copyWith(
                          color: tokens.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
