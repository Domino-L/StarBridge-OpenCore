import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'community_catalog_ship_image.dart';
import 'community_ships_copy.dart';
import 'community_ships_port.dart';

/// Loaners belong to a source asset. They never expose independent ownership actions.
class CommunityShipLoaners extends StatelessWidget {
  const CommunityShipLoaners({required this.ship, super.key});
  final CommunitySharedShip ship;
  @override
  Widget build(BuildContext context) {
    final rows = ship.loaners;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();
    String t(String key) => communityShipsText(context, key);
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        key: ValueKey('ship-loaners-${ship.shipRef}'),
        title: Text('${t('loaners')} · ${rows.length}'),
        subtitle: Text(
          t('loanerHint'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          for (final item in rows)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CommunityCatalogShipImage(
                      asset: item.catalogThumbnailAsset,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName.isEmpty
                              ? item.code
                              : item.displayName,
                        ),
                        Text(
                          item.code,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Wrap(
                          spacing: 16,
                          children: [
                            Text(
                              communityShipDisplayText(
                                context,
                                item.displaySpec,
                              ),
                            ),
                            Text(
                              item.catalogStatus == 'flyable'
                                  ? t('flyable')
                                  : item.catalogStatus == 'concept'
                                  ? t('concept')
                                  : t('unknown'),
                              style: TextStyle(
                                color: item.catalogStatus == 'flyable'
                                    ? context.tokens.colors.success
                                    : context.tokens.colors.textSecondary,
                              ),
                            ),
                            Text(
                              communityShipDisplayText(
                                context,
                                item.displayRole,
                              ),
                            ),
                            Text(
                              ShipCatalogDisplay.usdText(
                                    item.catalogPriceUsd,
                                  ) ??
                                  t('unpublished'),
                              style: TextStyle(
                                color:
                                    ShipCatalogDisplay.usdCents(
                                          item.catalogPriceUsd,
                                        ) ==
                                        null
                                    ? context.tokens.colors.textSecondary
                                    : context.tokens.colors.info,
                              ),
                            ),
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
    );
  }
}
