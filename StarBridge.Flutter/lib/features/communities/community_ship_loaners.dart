import '../../design_system/icons/standard_icon.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_expansion_tile.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'community_catalog_ship_image.dart';
import 'community_ships_copy.dart';
import 'community_ships_port.dart';

/// How many replacements a ship has, beside its price (user 2026-10-30); the
/// details list them. Nothing when there are none.
class CommunityShipLoanerCount extends StatelessWidget {
  const CommunityShipLoanerCount({required this.ship, super.key});
  final CommunitySharedShip ship;

  @override
  Widget build(BuildContext context) {
    final count = ship.loaners?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    String t(String key) => communityShipsText(context, key);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 10),
      child: StarBridgeTooltip(
        message: t('loanerHint'),
        child: Text(
          '${t('loaners')} $count',
          key: ValueKey('community-ship-loaner-count-${ship.shipRef}'),
          maxLines: 1,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.tokens.colors.textSecondary),
        ),
      ),
    );
  }
}

/// Loaners belong to a source asset. They never expose independent ownership actions.
class CommunityShipLoaners extends StatelessWidget {
  const CommunityShipLoaners({required this.ship, super.key});
  final CommunitySharedShip ship;
  @override
  Widget build(BuildContext context) {
    final rows = ship.loaners;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();
    String t(String key) => communityShipsText(context, key);
    final title = '${t('loaners')} · ${rows.length}';
    Widget header(BuildContext context, double open) {
      final theme = Theme.of(context);
      final expansionTheme = ExpansionTileTheme.of(context);
      final colors = theme.colorScheme;
      final progress = Curves.easeIn.transform(open);
      return ListTileTheme.merge(
        textColor: Color.lerp(
          expansionTheme.collapsedTextColor ??
              (theme.useMaterial3
                  ? colors.onSurface
                  : theme.textTheme.titleMedium!.color),
          expansionTheme.textColor ??
              (theme.useMaterial3 ? colors.onSurface : colors.primary),
          progress,
        ),
        iconColor: Color.lerp(
          expansionTheme.collapsedIconColor ??
              (theme.useMaterial3
                  ? colors.onSurfaceVariant
                  : theme.unselectedWidgetColor),
          expansionTheme.iconColor ?? colors.primary,
          progress,
        ),
        child: ListTile(
          contentPadding: expansionTheme.tilePadding,
          title: Text(title),
          subtitle: Text(t('loanerHint'), style: theme.textTheme.bodySmall),
          trailing: Transform.rotate(
            angle: math.pi * open,
            child: const StandardIcon(StandardIconSemantic.expandMore),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      // Native ExpansionTile reserves its two transparent border pixels even
      // when closed. Keep that geometry around the shared disclosure.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: StarBridgeExpansionTile(
          key: ValueKey('ship-loaners-${ship.shipRef}'),
          title: title,
          useNativePageStorage: true,
          headerBuilder: (context, _, open) => header(context, open),
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
      ),
    );
  }
}
