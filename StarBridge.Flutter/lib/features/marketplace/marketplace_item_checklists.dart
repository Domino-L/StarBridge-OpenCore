import 'package:flutter/material.dart';
import 'marketplace_display_rules.dart';

import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_details.dart';
import 'marketplace_hall_mine.dart' show marketSideColor;
import 'marketplace_order_sheet.dart';
import 'marketplace_prefetch.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_unified.dart';
import 'marketplace_widgets.dart';

/// The item page's 清单 view: checklist orders that contain this item (SCM
/// displayType 2, user 2026-11-11). Each row is a whole bundle, so it shows the
/// checklist's name, the bundle price and the sets left, never a quality, a
/// per-point price or a buy-order verdict. Opening a row shows every item.
class MarketItemChecklistOffers extends StatelessWidget {
  const MarketItemChecklistOffers(this.c, {required this.retry, super.key});
  final MarketplaceController c;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final buy = c.itemTab == 1;
    final side = buy ? 'buy' : 'sell';
    // Checklist rows have their own block; the single-item one stays as it is.
    final key = c.offerKey(buy);
    final read = c.blocks[key];
    if (read == null && c.failures.contains(key)) {
      return MarketNotice(marketText(context, 'unavailable'), retry: retry);
    }
    if (read == null) return const MarketSkeleton(kind: 'quotes');
    if (read.rows.isEmpty) {
      return MarketNotice(marketText(context, 'emptyChecklist'));
    }
    final t = context.tokens;
    final rows = marketBundlePriceRows(read.rows, buy: buy);
    return MarketPrefetch(
      read: read,
      loading: c.loading.contains(key),
      failed: c.failures.contains(key),
      load: () => c.moreOffers(buy),
      child: ListView.builder(
        key: PageStorageKey((c.itemId, key)),
        itemCount: read.rows.length + 1,
        itemBuilder: (context, index) {
          if (index == read.rows.length) {
            return MarketPageStatus(
              read: read,
              loading: c.loading.contains(key),
              failed: c.failures.contains(key),
              load: () => c.moreOffers(buy),
            );
          }
          final row = rows[index];
          return StarBridgeActionRow(
            inheritContentStyle: true,
            controlKey: ValueKey((
              'market-checklist-row',
              row['orderNumber'] ?? index,
            )),
            baseRadius: 0,
            onActivate: (_, _) => showMarketOrder(context, c, row),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: t.surfaces.panel.fill,
                border: Border(
                  bottom: BorderSide(color: marketLine(context)),
                  left: BorderSide(
                    color: marketSideColor(context, side),
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: MarketArt(marketChecklistArt),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          marketOrderTitle(context, row),
                          maxLines: 1,
                          overflow: fadeOverflow(context),
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        MarketTrader(row),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      marketLocation(context, row),
                      maxLines: 1,
                      overflow: fadeOverflow(context),
                      softWrap: false,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '×${row['availableQuantity'] ?? row['remainingQuantity'] ?? '—'}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: t.typography.monoFamily,
                        fontSize: 12.5,
                        color: t.colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MarketGoldPrice(row['unitPrice']),
                      MarketPublished(row['createTime']),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
