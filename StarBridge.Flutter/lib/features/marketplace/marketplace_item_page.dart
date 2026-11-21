import 'marketplace_item_favorite.dart';
import 'marketplace_display_rules.dart';
import 'marketplace_display_copy.dart';
import 'dart:async';
import 'marketplace_hall_helpers.dart';
import '../../design_system/icons/marketplace_icon.dart';
import 'marketplace_item_components.dart';
import '../../design_system/styles/marketplace_palette.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_unified.dart';
import 'marketplace_details.dart';
import '../../design_system/interaction/starbridge_choice_navigation.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'bridge_marketplace_listings_port.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_hall_mine.dart';
import 'marketplace_item_quality.dart';
import 'marketplace_quality_copy.dart';
import 'marketplace_publish_entry.dart';
import 'marketplace_item_offers.dart';
import 'marketplace_port.dart';
import 'marketplace_widgets.dart';


class MarketplaceItemPage extends StatelessWidget {
  const MarketplaceItemPage(this.c, {super.key});
  final MarketplaceController c;

  @override
  Widget build(BuildContext context) {
    final item = c.blocks['item']?.data;
    final id = c.itemId!;
    // The page's own figures, not card decoration: no first-screen wait.
    unawaited(c.ensureBestPrices([(id, 1), (id, 0)], urgent: true));
    final lowest = c.bestPrice(id, 1), highest = c.bestPrice(id, 0);
    // An unfiltered single-item list that came back empty also says nobody
    // is selling (or buying), without waiting for the best-price read.
    bool emptyList(String key) =>
        c.offerFilters.isEmpty && c.blocks[key]?.rows.isEmpty == true;
    final noSell = c.bestPriceNone(id, 1) || emptyList('sell'),
        noBuy = c.bestPriceNone(id, 0) || emptyList('buy');
    final change = marketSevenDaySellChange(
      c.blocks['trend']?.rows ?? const [],
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
              '${marketItemOrderCount(item, buy: false) ?? '—'} / ${marketItemOrderCount(item, buy: true) ?? '—'}',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [marketItemFavorite(context, c, item), ...publishHere(item)],
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
                            noSell ? 'noSell'
                                : c.hasBestPrice(id, 1) ? 'unavailable' : 'priceLoading',
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
                            noBuy ? 'noBuy'
                                : c.hasBestPrice(id, 0) ? 'unavailable' : 'priceLoading',
                          )
                        : '¤ ${marketPrice(context, highest)}',
                    color: highest == null ? null : MarketplacePalette.buyer,
                    mono: highest != null,
                  ),
                  MarketStat(
                    marketText(context, 'spread'),
                    lowest != null && highest != null
                        ? '¤ ${marketPrice(context, lowest - highest)}'
                        : noSell || noBuy
                        ? '—'
                        : marketText(context,
                            c.hasBestPrice(id, 1) && c.hasBestPrice(id, 0)
                                ? 'unavailable' : 'priceLoading'),
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
                  '${marketText(context, ['sell', 'buy', 'trend', 'acquisition'][i])}${i < 2 && c.blocks[c.offerKey(i == 1)]?.total != null ? ' ${c.blocks[c.offerKey(i == 1)]!.total}' : ''}',
                ),
              ),
          ],
        ),
        if (c.itemTab < 2) ItemOfferFilters(c),
        if (c.itemTab < 2 && c.offerChecklist)
          Text(marketDisplayText(context, 'loadedBundleSort')),
        if (c.itemTab == 1 && c.offerFilters['minQuality'] != null)
          Text('${marketDisplayText(context, 'buyCeiling', n: c.offerFilters['minQuality'])} · ${marketDisplayText(context, 'loadedOnly')}'),
        if (c.itemTab < 2 && !c.offerChecklist) MarketItemTierSection(c),
        if (c.itemTab < 2 && !c.offerChecklist &&
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
                  buy: c.itemTab == 1,
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
                          c.itemTab == 0 &&
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
        // Offers retry with the current filters (single or checklist).
        if (c.failures.contains(c.itemTabKey) &&
            c.blocks[c.itemTabKey] != null)
          MarketStale(
            c.blocks[c.itemTabKey]!.readAt,
            retry: c.itemTab < 2
                ? () => c.reloadOffer(c.itemTab == 1)
                : () => c.load(c.itemTabKey, c.itemTabKey, id: c.itemId!, side: 1),
          ),
        Expanded(
          child: MarketSurface(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MarketRefilter(
                active: c.itemTab < 2 && c.refiltering.contains(c.offerKey(c.itemTab == 1)),
                onCancel: () => c.cancelRefilter(c.offerKey(c.itemTab == 1)),
                child: offerSection(context),
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
                                if (item == null && c.failures.contains('item'))
                                  MarketNotice(marketText(context, 'unavailable'), retry: () => c.load('item', 'item', id: c.itemId!))
                                else Text(
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
                                  '${marketItemOrderCount(item, buy: false) ?? '—'} / ${marketItemOrderCount(item, buy: true) ?? '—'}',
                                ),
                                const SizedBox(height: 8),
                                if (item != null)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      marketItemFavorite(context, c, item),
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
