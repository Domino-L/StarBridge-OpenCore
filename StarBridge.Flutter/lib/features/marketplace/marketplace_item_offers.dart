import 'marketplace_buy_value.dart';
import 'marketplace_display_rules.dart';
import 'marketplace_item_checklists.dart';
import 'marketplace_item_components.dart';
import 'marketplace_trade_copy.dart';
import 'marketplace_prefetch.dart';
import 'marketplace_trade_confirm.dart';
import 'marketplace_order_sheet.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_unified.dart';
import 'marketplace_details.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import 'package:flutter/material.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_copy.dart';
import 'marketplace_hall_mine.dart';
import 'marketplace_item_quality.dart';
import 'marketplace_trend.dart';
import 'marketplace_widgets.dart';
import 'marketplace_item_page.dart';

extension MarketItemOffers on MarketplaceItemPage {
  Widget offerSection(BuildContext context) {
    final key = c.itemTabKey;
    final read = c.blocks[key];
    void retry() => c.itemTab < 2
        ? c.reloadOffer(c.itemTab == 1)
        : c.load(key, key, id: c.itemId!, side: 1);
    if (c.failures.contains(key) && read == null) {
      return MarketNotice(
        marketText(context, key == 'trend' ? 'trendFailed' : 'unavailable'),
        retry: retry,
      );
    }
    if (c.offerChecklist && c.itemTab < 2) {
      return MarketItemChecklistOffers(c, retry: retry);
    }
    if (read == null) return const MarketSkeleton(kind: 'quotes');
    if (key == 'trend') {
      return SingleChildScrollView(child: MarketplaceTrend(read.rows));
    }
    if (read.rows.isEmpty) {
      return MarketNotice(
        marketText(
          context,
          key == 'acquisition'
              ? 'noAcquisition'
              : key == 'sell'
              ? 'emptySell'
              : 'emptyBuy',
        ),
      );
    }
    if (key == 'acquisition') {
      return ListView.builder(
        key: ValueKey((c.itemId, key)),
        itemCount: read.rows.length,
        itemBuilder: (context, index) {
          final row = read.rows[index];
          final hant = marketLocale(context) == 'hant';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (row[hant ? 'titleHant' : 'title'] ?? '').toString(),
                  style: TextStyle(
                    fontWeight: context.tokens.typography.emphasisWeight,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  (row[hant ? 'descriptionHant' : 'description'] ?? '')
                      .toString(),
                ),
              ],
            ),
          );
        },
      );
    }
    final qualityColumn = read.rows.any((row) => marketQuality(row) != null);
    final localQualityFilter = key == 'buy' && c.offerFilters['minQuality'] != null;
    final sorted = c.sortedOffers(key == 'buy'
        ? marketBuyQualityRows(read.rows, c.offerFilters) : read.rows);
    // Every quality at once, in price order: grouped by tier (2026-10-23).
    final entries = marketOfferEntries(
      sorted,
      group:
          key == 'sell' &&
          qualityColumn &&
          c.offerTier == null &&
          c.offerSortField == 'price',
    );
    final bestValue = qualityColumn && key == 'sell'
        ? marketBestValueOrders(read.rows)
        : const <Object?>{};
    return MarketPrefetch(
      enabled: !localQualityFilter,
      read: read,
      loading: c.loading.contains(key),
      failed: c.failures.contains(key),
      load: () => c.moreOffers(key == 'buy'),
      child: ListView.builder(
        key: PageStorageKey((c.itemId, key)),
        itemCount: entries.length + 1,
        itemBuilder: (context, index) {
          if (index == entries.length) {
            return MarketPageStatus(
              visibleCount: localQualityFilter ? sorted.length : null,
              read: read,
              loading: c.loading.contains(key),
              failed: c.failures.contains(key),
              load: () => c.moreOffers(key == 'buy'),
            );
          }
          if (entries[index].header case final tier?) {
            return MarketTierGroupHeader(
              tier,
              quote: c.qualityTiers.of(c.itemId ?? 0)?.of(tier),
            );
          }
          final row = entries[index].row!;
          return StarBridgeActionRow(
            inheritContentStyle: true,
            controlKey: ValueKey((
              'market-offer-row',
              row['orderNumber'] ?? index,
            )),
            baseRadius: 0,
            onActivate: (_, _) => showMarketOrder(context, c, row),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.tokens.surfaces.panel.fill,
                border: Border(
                  bottom: BorderSide(color: marketLine(context)),
                  // Side colour on the left edge, as on every hall listing.
                  left: BorderSide(
                    color: marketSideColor(context, key == 'sell' ? 'sell' : 'buy'),
                    width: 3,
                  ),
                ),
              ),
              child: ItemOfferColumns(
                quality: qualityColumn,
                buy: key == 'buy',
                action: c.trades.supported,
                cells: [
                  ItemTraderCell(row),
                  MarketTrader(row),
                  Text(
                    marketLocation(context, row),
                    maxLines: 1,
                    overflow: fadeOverflow(context),
                    softWrap: false,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  Text(
                    marketTradeTime(context, row),
                    maxLines: 1,
                    overflow: fadeOverflow(context),
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.tokens.colors.textSecondary,
                    ),
                  ),
                  MarketQualityBadge(row, inColumn: true),
                  Text(
                    row['availableQuantity']?.toString() ??
                        row['remainingQuantity']?.toString() ??
                        '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: context.tokens.typography.monoFamily,
                      fontSize: 12.5,
                      color: context.tokens.colors.textSecondary,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MarketGoldPrice(row['unitPrice']),
                      if (key == 'buy')
                        MarketBidValueLine(c, row)
                      else if (qualityColumn)
                        MarketOfferPerPoint(
                          row,
                          best: bestValue.contains(row['orderNumber']),
                        ),
                      MarketPublished(row['createTime']),
                    ],
                  ),
                  marketButtonAction(
                    OutlinedButton(
                      // Your own listing is never offered for trade.
                      onPressed: marketIsMine(row)
                          ? null
                          : () => confirmMarketTrade(context, c, row),
                      style: OutlinedButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: context.tokens.colors.textPrimary,
                        side: BorderSide(
                          color: context.tokens.surfaces.panel.border,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      child: Text(
                        marketIsMine(row)
                            ? marketText(context, 'mineListing')
                            : key == 'sell'
                            ? tradeText(context, '购买')
                            : tradeText(context, '出售给他'),
                      ),
                    ),
                    key: ValueKey((
                      'market-quote-confirm',
                      row['orderNumber'] ?? index,
                    )),
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
