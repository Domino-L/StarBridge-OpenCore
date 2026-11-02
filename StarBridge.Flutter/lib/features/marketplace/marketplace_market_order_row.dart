import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_action_row.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_copy.dart';
import 'marketplace_details.dart';
import 'marketplace_diagonal.dart' show MarketSlantTag;
import 'marketplace_hall_mine.dart' show MarketVerbPrice, marketSideColor;
import 'marketplace_port.dart';
import 'marketplace_widgets.dart';

String _orderName(BuildContext context, MarketRow row) =>
    marketName(row, marketLocale(context)).isNotEmpty
    ? marketName(row, marketLocale(context))
    : marketName(
        marketRows(row['items']).firstOrNull ?? {},
        marketLocale(context),
      );
String _side(MarketRow row) => row['displayType'] == 3
    ? 'barter'
    : row['creatorType'] == 0
    ? 'buy'
    : 'sell';

Widget marketOrderIdentity(
  BuildContext context,
  MarketRow row, {
  bool side = true,
}) => Row(
  children: [
    SizedBox.square(dimension: 38, child: MarketArt.of(row)),
    const SizedBox(width: 10),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _orderName(context, row),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              // Rows show the side on their price line; cards keep it here.
              if (side)
                MarketSlantTag(
                  marketText(context, _side(row)),
                  color: marketSideColor(context, _side(row)),
                ),
              MarketQualityBadge(row),
            ],
          ),
        ],
      ),
    ),
  ],
);

class MarketplaceMarketOrderRow extends StatelessWidget {
  const MarketplaceMarketOrderRow(
    this.row, {
    required this.narrow,
    required this.open,
    super.key,
  });
  final MarketRow row;
  final bool narrow;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 1),
    child: Material(
      color: context.tokens.surfaces.panel.fill,
      borderRadius: BorderRadius.zero,
      clipBehavior: Clip.antiAlias,
      child: StarBridgeActionRow(
        inheritContentStyle: true,
        controlKey: ValueKey(('market-order-row', row['orderNumber'])),
        baseRadius: 0,
        onActivate: (_, _) => open(),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          // Side colour on the left edge, as on every hall listing.
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: marketSideColor(context, _side(row)),
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: marketOrderIdentity(context, row, side: false),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: MarketTrader(row)),
              if (!narrow) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        marketLocation(context, row),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      Text(
                        marketTradeTime(context, row),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: context.tokens.colors.textSecondary,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(
                width: 44,
                child: Text(
                  '${row['remainingQuantity'] ?? row['availableQuantity'] ?? marketText(context, 'unavailable')}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: context.tokens.typography.monoFamily,
                    fontSize: 12.5,
                    color: context.tokens.colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: narrow ? 150 : 190,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: row['displayType'] == 3
                      ? Text(
                          marketText(context, 'barter'),
                          style: TextStyle(
                            color: context.tokens.colors.textSecondary,
                          ),
                        )
                      : MarketVerbPrice(
                          side: _side(row),
                          price: row['unitPrice'],
                          compact: true,
                        ),
                ),
              ),
              if (!narrow) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 60,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: MarketPublished(row['createTime']),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
