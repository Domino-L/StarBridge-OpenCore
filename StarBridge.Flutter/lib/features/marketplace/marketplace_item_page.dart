import 'dart:async';
import 'marketplace_hall_helpers.dart';

import '../../design_system/icons/marketplace_icon.dart';
import 'marketplace_item_components.dart';
import '../../design_system/styles/marketplace_palette.dart';
import 'marketplace_trade_copy.dart';
import 'marketplace_prefetch.dart';
import 'marketplace_trade_confirm.dart';
import 'marketplace_order_sheet.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_unified.dart';
import 'marketplace_details.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_choice_navigation.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/favorite_icon.dart';
import 'bridge_marketplace_listings_port.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_hall_mine.dart';
import 'marketplace_item_quality.dart';
import 'marketplace_quality_copy.dart';
import 'marketplace_publish_entry.dart';
import 'marketplace_port.dart';
import 'marketplace_trend.dart';
import 'marketplace_widgets.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

class MarketplaceItemPage extends StatelessWidget {
  const MarketplaceItemPage(this.c, {super.key});
  final MarketplaceController c;

  Widget _section(BuildContext context) {
    final key = ['sell', 'buy', 'trend', 'acquisition'][c.itemTab];
    final read = c.blocks[key];
    void retry() => c.load(
      key,
      key == 'sell' || key == 'buy' ? 'offers' : key,
      id: c.itemId!,
      side: key == 'buy' ? 0 : 1,
    );
    if (c.failures.contains(key) && read == null) {
      return MarketNotice(
        marketText(context, key == 'trend' ? 'trendFailed' : 'unavailable'),
        retry: retry,
      );
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
    final sorted = c.sortedOffers(read.rows);
    // Every quality at once, in price order: grouped by tier (2026-10-23).
    final entries = marketOfferEntries(
      sorted,
      group:
          key == 'sell' &&
          qualityColumn &&
          c.offerTier == null &&
          c.offerSortField == 'price',
    );
    final bestValue = qualityColumn
        ? marketBestValueOrders(read.rows)
        : const <Object?>{};

    return MarketPrefetch(
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
                action: c.trades.supported,
                cells: [
                  ItemTraderCell(row),
                  MarketTrader(row),
                  Text(
                    marketLocation(context, row),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  Text(
                    marketTradeTime(context, row),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.tokens.colors.textSecondary,
                    ),
                  ),
                  MarketQualityBadge(row),
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
                      if (qualityColumn)
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

  @override
  Widget build(BuildContext context) {
    final item = c.blocks['item']?.data;
    final sell = c.blocks['sell']?.rows;
    final buy = c.blocks['buy']?.rows;
    final lowest = sell?.isNotEmpty == true
        ? marketNumber(sell!.first['unitPrice'])
        : null;
    final highest = buy?.isNotEmpty == true
        ? marketNumber(buy!.first['unitPrice'])
        : null;
    final change = marketSevenDaySellChange(
      c.blocks['trend']?.rows ?? const [],
    );
    final following = c.favorites.contains(c.itemId);
    // A followed item reads in red (user 2026-10-20); following confirms with
    // a way to the 关注 tab, unfollowing with an undo (G3, 0.7.2).
    Widget favorite() => OutlinedButton.icon(
      key: const Key('market-item-follow'),
      style: OutlinedButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        foregroundColor: following
            ? MarketplacePalette.heart
            : context.tokens.colors.textPrimary,
        side: BorderSide(
          color: following
              ? MarketplacePalette.heart
              : context.tokens.surfaces.panel.border,
        ),
        shape: const RoundedRectangleBorder(),
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      icon: FavoriteIcon(
        selected: following,
        size: 16,
        color: following ? MarketplacePalette.heart : null,
      ),
      onPressed: c.savingPreferences || c.preferencesFailed
          ? null
          : () async {
              final id = c.itemId!;
              final name = item == null
                  ? marketText(context, 'thisItem')
                  : marketName(item, marketLocale(context));
              final snapshot = c.watchSnapshot(id);
              final messenger = ScaffoldMessenger.of(context);
              final added = marketTextN(context, 'watchAdded', name);
              final removed = marketTextN(context, 'watchRemoved', name);
              final view = marketText(context, 'watchView');
              final undo = marketText(context, 'watchUndo');
              final limit = marketText(context, 'watchLimit');
              await c.toggleFavorite(id);
              if (!context.mounted) return;
              if (c.favoriteLimitReached) {
                messenger.showOnly(starBridgeTimedSnackBar(content: Text(limit)));
                return;
              }
              final now = c.favorites.contains(id);
              messenger.showOnly(
                // QualityPass ②: 2.5 s, paused while pointed at so 撤销 stays reachable.
                starBridgeTimedSnackBar(
                  content: Text(now ? added : removed),
                  action: SnackBarAction(
                    label: now ? view : undo,
                    onPressed: now
                        ? () => c.tab(5)
                        : () => unawaited(
                            c.toggleFavorite(id, snapshot: snapshot),
                          ),
                  ),
                ),
              );
            },
      label: Text(
        marketText(
          context,
          c.savingPreferences
              ? 'saving'
              : following
              ? 'unfollow'
              : 'follow',
        ),
      ),
    );
    // 我也要卖 / 我也要收: the publish wizard opens on step 3 with this item and
    // side filled in, carrying the live best prices as its reference.
    Widget alsoPublish(MarketRow item, String side) {
      final color = marketSideColor(context, side);
      return marketButtonAction(
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: .55)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          onPressed: () => openMarketPublish(
            context,
            c,
            item: listingPickable({
              ...item,
              'id': c.itemId,
              'best': lowest,
              'highestBuy': highest,
              'average': c.blocks['trend']?.data['overallPrice'],
            }),
            side: side,
          ),
          child: Text(
            marketText(context, side == 'buy' ? 'alsoBuy' : 'alsoSell'),
          ),
        ),
        key: Key('item-also-$side'),
      );
    }

    List<Widget> publishHere(MarketRow item) => c.myListingsSupported
        ? [alsoPublish(item, 'sell'), alsoPublish(item, 'buy')]
        : const [];
    List<(MarketplaceGlyph, String, VoidCallback?)> related(MarketRow item) => [
      for (final row in marketRows(item['variants']))
        (
          MarketplaceGlyph.material,
          '${marketText(context, 'sameSeries')} · ${marketName(row, marketLocale(context))}',
          marketItemId(row) == null
              ? null
              : () => c.openItem(marketItemId(row)!),
        ),
      (
        MarketplaceGlyph.attachment,
        marketText(context, 'attachments'),
        () => c.related('attachments', c.itemId!),
      ),
      (
        MarketplaceGlyph.blueprint,
        marketText(context, 'blueprints'),
        () => c.related('blueprints', c.itemId!),
      ),
      if (item['categoryId'] is int)
        (
          MarketplaceGlyph.similar,
          marketText(context, 'sameCategory'),
          () => c.browse(category: item['categoryId'] as int),
        ),
    ];
    Widget identity() => SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.failures.contains('item') && item == null)
            MarketNotice(
              marketText(context, 'unavailable'),
              retry: () => c.load('item', 'item', id: c.itemId!),
            )
          else if (item == null)
            MarketNotice(marketText(context, 'loading'))
          else ...[
            AspectRatio(
              aspectRatio: 4 / 3,
              child: MarketArt(
                item['thumbnailUrlHd'] as String? ?? marketThumbnail(item),
                category: marketCategoryOf(item),
                large: true,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              marketName(item, marketLocale(context)),
              style: TextStyle(
                fontSize: context.tokens.typography.headline,
                fontWeight: context.tokens.typography.titleWeight,
              ),
            ),
            const SizedBox(height: 12),
            itemKv(
              context,
              marketText(context, 'historyAverage'),
              c.blocks['trend']?.data['overallPrice'] == null
                  ? marketText(context, 'unavailable')
                  : '${marketMoney(c.blocks['trend']!.data['overallPrice'])} UEC',
              tooltip: marketText(context, 'historyNote'),
            ),
            itemKv(
              context,
              marketText(context, 'sellBuy'),
              '${c.blocks['sell']?.total ?? '—'} / ${c.blocks['buy']?.total ?? '—'}',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [favorite(), ...publishHere(item)],
              ),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: marketLine(context)),
            const SizedBox(height: 12),
            Text(
              marketText(context, 'related'),
              style: TextStyle(
                fontSize: 12,
                color: context.tokens.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            for (final (icon, label, onTap) in related(item))
              ItemRelatedRow(icon: icon, label: label, onTap: onTap),
            const SizedBox(height: 12),
            Text(
              marketText(context, 'source'),
              style: TextStyle(
                fontSize: context.tokens.typography.label,
                color: context.tokens.colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
    Widget quotes() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarketSurface(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The banner's stat language (2026-10-20): money in gold, the
              // best bid in the buyer colour, slanted dividers.
              Expanded(
                child: MarketStatStrip([
                  MarketStat(
                    marketText(context, 'lowest'),
                    lowest == null
                        ? marketText(
                            context,
                            sell?.isEmpty == true ? 'noSell' : 'unavailable',
                          )
                        : '¤ ${marketPrice(context, lowest)}',
                    color: lowest == null ? null : MarketplacePalette.gold,
                    mono: lowest != null,
                  ),
                  MarketStat(
                    marketText(context, 'highest'),
                    highest == null
                        ? marketText(
                            context,
                            buy?.isEmpty == true ? 'noBuy' : 'unavailable',
                          )
                        : '¤ ${marketPrice(context, highest)}',
                    color: highest == null ? null : MarketplacePalette.buyer,
                    mono: highest != null,
                  ),
                  if (lowest != null && highest != null)
                    MarketStat(
                      marketText(context, 'spread'),
                      '¤ ${marketPrice(context, lowest - highest)}',
                    ),
                  MarketStat(
                    marketText(context, 'sevenDays'),
                    change == null
                        ? '—'
                        : change == 0
                        ? marketText(context, 'flat')
                        : '${change > 0 ? '▲ +' : '▼ −'}${change.abs().toStringAsFixed(2)}%',
                    color: change == null || change == 0
                        ? context.tokens.colors.textSecondary
                        : change > 0
                        ? context.tokens.colors.success
                        : context.tokens.colors.danger,
                  ),
                ]),
              ),
              MarketStamp(c.blocks['sell']?.readAt),
              const SizedBox(width: 6),
              StarBridgeNativeIconAction(
                controlKey: const Key('market-item-refresh'),
                label: marketText(context, 'refresh'),
                style: IconButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: context.tokens.surfaces.panel.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onActivate: c.loading.isNotEmpty
                    ? null
                    : (_) => c.refreshItem(),
                icon: const MarketplaceIcon(MarketplaceGlyph.refresh, size: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MarketTabs(
          selected: c.itemTab.toString(),
          onSelected: (id) => c.selectItemTab(int.parse(id)),
          choices: [
            for (var i = 0; i < 4; i++)
              StarBridgeNavigationChoice(
                id: i.toString(),
                label: marketText(
                  context,
                  ['sell', 'buy', 'trend', 'acquisition'][i],
                ),
                child: Text(
                  '${marketText(context, ['sell', 'buy', 'trend', 'acquisition'][i])}${i < 2 && c.blocks[i == 0 ? 'sell' : 'buy']?.total != null ? ' ${c.blocks[i == 0 ? 'sell' : 'buy']!.total}' : ''}',
                ),
              ),
          ],
        ),
        if (c.itemTab < 2) ItemOfferFilters(c),
        if (c.itemTab == 0) MarketItemTierSection(c),
        if (c.itemTab < 2 &&
            (c.blocks[c.itemTab == 0 ? 'sell' : 'buy']?.rows.isNotEmpty ??
                false))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .4,
                  color: context.tokens.colors.textSecondary,
                ),
                child: ItemOfferColumns(
                  quality:
                      (c.blocks[c.itemTab == 0 ? 'sell' : 'buy']?.rows ?? [])
                          .any((row) => marketQuality(row) != null),
                  action: c.trades.supported,
                  cells: [
                    const SizedBox(),
                    Text(marketText(context, 'seller')),
                    Text(marketText(context, 'location')),
                    Text(marketText(context, 'tradeHours')),
                    for (final (field, label, right) in [
                      ('quality', 'quality', false),
                      ('quantity', 'quantity', true),
                      ('price', 'price', true),
                    ])
                      if (field == 'price' &&
                          (c.blocks[c.itemTab == 0 ? 'sell' : 'buy']?.rows ??
                                  [])
                              .any((row) => marketQuality(row) != null))
                        // Quality offers also sort by price per point.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ItemSortHeader(
                              label: qualityText(context, 'perPointSort'),
                              right: true,
                              active: c.offerSortField == 'perPoint',
                              desc: c.offerSortIsDesc('perPoint', c.itemTab == 1),
                              onTap: () =>
                                  c.setOfferSort('perPoint', buy: c.itemTab == 1),
                            ),
                            const SizedBox(width: 10),
                            ItemSortHeader(
                              label: marketText(context, label),
                              right: right,
                              active: c.offerSortField == field,
                              desc: c.offerSortIsDesc(field, c.itemTab == 1),
                              onTap: () =>
                                  c.setOfferSort(field, buy: c.itemTab == 1),
                            ),
                          ],
                        )
                      else
                      Align(
                        alignment: right
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ItemSortHeader(
                          label: marketText(context, label),
                          right: right,
                          active: c.offerSortField == field,
                          desc: c.offerSortIsDesc(field, c.itemTab == 1),
                          onTap: () =>
                              c.setOfferSort(field, buy: c.itemTab == 1),
                        ),
                      ),
                    const SizedBox(),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (c.failures.contains(
              ['sell', 'buy', 'trend', 'acquisition'][c.itemTab],
            ) &&
            c.blocks[['sell', 'buy', 'trend', 'acquisition'][c.itemTab]] !=
                null)
          MarketStale(
            c
                .blocks[['sell', 'buy', 'trend', 'acquisition'][c.itemTab]]!
                .readAt,
            retry: () {
              final key = ['sell', 'buy', 'trend', 'acquisition'][c.itemTab];
              c.load(
                key,
                c.itemTab < 2 ? 'offers' : key,
                id: c.itemId!,
                side: c.itemTab == 1 ? 0 : 1,
              );
            },
          ),
        Expanded(
          child: MarketSurface(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MarketRefilter(
                active: c.itemTab < 2 && c.refiltering.contains(c.itemTab == 1 ? 'buy' : 'sell'),
                onCancel: () => c.cancelRefilter(c.itemTab == 1 ? 'buy' : 'sell'),
                child: _section(context),
              ),
            ),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            marketTextAction(
              key: const Key('marketplace-back'),
              onPressed: c.back,
              child: Text(marketBackText(context, c)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 850
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 150,
                            height: 112,
                            child: MarketArt(
                              item == null
                                  ? null
                                  : item['thumbnailUrlHd'] as String? ??
                                        marketThumbnail(item),
                              category: item == null
                                  ? 0
                                  : marketCategoryOf(item),
                              large: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  item == null
                                      ? marketText(context, 'loading')
                                      : marketName(item, marketLocale(context)),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: context.tokens.typography.title,
                                    fontWeight:
                                        context.tokens.typography.titleWeight,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                itemKv(
                                  context,
                                  marketText(context, 'historyAverage'),
                                  c.blocks['trend']?.data['overallPrice'] ==
                                          null
                                      ? marketText(context, 'unavailable')
                                      : '${marketMoney(c.blocks['trend']!.data['overallPrice'])} UEC',
                                  tooltip: marketText(context, 'historyNote'),
                                ),
                                itemKv(
                                  context,
                                  marketText(context, 'sellBuy'),
                                  '${c.blocks['sell']?.total ?? '—'} / ${c.blocks['buy']?.total ?? '—'}',
                                ),
                                const SizedBox(height: 8),
                                if (item != null)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      favorite(),
                                      ...publishHere(item),
                                      for (final (icon, label, onTap)
                                          in related(item))
                                        ItemRelatedChip(
                                          icon: icon,
                                          label: label,
                                          onTap: onTap,
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(child: quotes()),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth >= 1000 ? 280 : 220,
                        child: identity(),
                      ),
                      const SizedBox(width: 20),
                      Expanded(child: quotes()),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
