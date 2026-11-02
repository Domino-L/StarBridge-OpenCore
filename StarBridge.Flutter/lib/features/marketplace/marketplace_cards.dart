import '../../design_system/icons/marketplace_icon.dart';

import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_action_row.dart';

import '../../design_system/styles/marketplace_palette.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/favorite_icon.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_details.dart';
import 'marketplace_copy.dart';
import 'marketplace_port.dart';
import 'marketplace_widgets.dart';
import 'marketplace_diagonal.dart';
import 'marketplace_hover.dart';
import 'marketplace_hall_mine.dart' show MarketVerbPrice, marketSideColor;
import 'marketplace_quality.dart';
import 'marketplace_quality_copy.dart';
import 'marketplace_quality_widgets.dart';

class MarketCard extends StatelessWidget {
  const MarketCard(
    this.row, {
    required this.open,
    this.trending = false,
    this.location,
    this.best,
    this.drawer,
    this.watched = false,
    super.key,
  });
  final MarketRow row;

  /// A followed item: a small red heart in the top-right corner (G3).
  final bool watched;
  final VoidCallback? open;
  final bool trending;

  /// Hover drawer content (方案 E); null keeps the hover line only.
  final WidgetBuilder? drawer;

  /// "微科星 · 新巴贝奇" when the hall knows SCM's location path.
  final String? location;

  /// Best live price for this item and side (lowest sell / highest buy) when
  /// known. Drives the 最低价 / 最高收购 tag; unknown shows no tag.
  final num? best;
  @override
  Widget build(BuildContext context) {
    final name = marketName(row, marketLocale(context));
    final price = row[trending ? 'price' : 'unitPrice'];
    final colors = context.tokens.colors;
    if (trending) {
      return MarketHoverCard(
        radius: 0,
        // Room for the tier ladder of a quality item.
        minDrawerWidth: row['qualityAny'] is Map ? 330 : 0,
        drawer: drawer,
        drawerKey: const ValueKey('market-drawer'),
        child: MarketSurface(
          corners: false,
          child: Material(
            color: Colors.transparent,
            child: StarBridgeActionRow(
              inheritContentStyle: true,
              hoverFace: false,
              baseRadius: 12,
              onActivate: open == null ? null : (_, _) => open!(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 120,
                    child: MarketArt.of(row),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 38,
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (row['qualityAny'] is Map)
                          ...marketTrendingQualityLines(context, row)
                        else ...[
                          // SCM's trending price is a 60-day average, not an
                          // ask: labelled as such (user 2026-10-23).
                          MarketPrice(price),
                          Text.rich(
                            TextSpan(
                              text: qualityText(context, 'recentAverage'),
                              children: [
                                if (marketNumber(row['changePercent'])
                                    case final num change)
                                  TextSpan(
                                    text:
                                        ' · ${change == 0 ? marketText(context, 'flat') : '${change > 0 ? '▲ +' : '▼ −'}${change.abs().toStringAsFixed(1)}%'}',
                                    style: TextStyle(
                                      color: change == 0
                                          ? colors.textSecondary
                                          : change > 0
                                          ? colors.success
                                          : colors.danger,
                                    ),
                                  ),
                              ],
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
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
    final listing = row.containsKey('seller');
    final side = row['displayType'] == 3
        ? 'barter'
        : row['creatorType'] == 0
        ? 'buy'
        : 'sell';
    final t = context.tokens;
    const gold = MarketplacePalette.gold;
    final tags = <MarketSlantTag>[];
    if (listing) {
      final q = marketQualityValue(row);
      if (q != null) {
        final tier = MarketQualityTier.of(q);
        tags.add(
          MarketSlantTag(
            marketText(context, tier.name),
            color: marketTierColor(context, tier),
            mono: q.toStringAsFixed(0),
            foil: tier == MarketQualityTier.legendary,
          ),
        );
      }
      final p = marketNumber(price);
      // A lowest ask across all qualities says nothing about a quality
      // listing: those are compared inside their tier, never here.
      final leading =
          q == null &&
          best != null &&
          p != null &&
          side != 'barter' &&
          (side == 'buy' ? p >= best! : p <= best!);
      if (leading) {
        tags.add(
          MarketSlantTag(
            marketText(context, side == 'buy' ? 'tagHighestBid' : 'tagLowest'),
            color: colors.success,
          ),
        );
      }
    }
    final wanted = marketRows(row['wantedItems']);
    // Absent location: omit the line rather than print a placeholder.
    final place = (location?.isNotEmpty ?? false)
        ? location!
        : (row['locationName'] as String?)?.isNotEmpty == true
        ? marketLocation(context, row)
        : '';
    return MarketHoverCard(
      color: listing ? marketSideColor(context, side) : null,
      drawer: drawer,
      drawerKey: const ValueKey('market-drawer'),
      child: Material(
        color: Colors.transparent,
        child: StarBridgeActionRow(
          inheritContentStyle: true,
          hoverFace: false,
          baseRadius: 0,
          onActivate: open == null ? null : (_, _) => open!(),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [t.surfaces.raised.fill, t.surfaces.panel.fill],
              ),
              border: Border(
                left: listing
                    ? BorderSide(
                        color: marketSideColor(context, side),
                        width: 3,
                      )
                    : BorderSide(color: t.surfaces.panel.border),
                top: BorderSide(color: t.surfaces.panel.border),
                right: BorderSide(color: t.surfaces.panel.border),
                bottom: BorderSide(color: t.surfaces.panel.border),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (listing)
                  Container(
                    height: 28,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Expanded(child: MarketFusedTags(tags)),
                        if (watched)
                          const FavoriteIcon(
                            key: Key('market-card-watched'),
                            selected: true,
                            size: 14,
                            color: MarketplacePalette.heart,
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(10, listing ? 6 : 10, 10, 0),
                  child: SizedBox(
                    height: listing ? 132 : 124,
                    child: MarketArt.of(row),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 4),
                  child: SizedBox(
                    height: 36,
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: t.typography.emphasisWeight,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (row['displayType'] == 3)
                        Text(
                          [
                            marketText(context, 'verbSwap'),
                            wanted.isEmpty
                                ? marketText(context, 'notFilled')
                                : wanted
                                      .map(
                                        (e) => marketName(
                                          e,
                                          marketLocale(context),
                                        ),
                                      )
                                      .join(', '),
                          ].join(' '),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: gold,
                          ),
                        )
                      else if (listing)
                        MarketVerbPrice(
                          side: side,
                          price: price,
                          quantity:
                              row['remainingQuantity'] ??
                              row['availableQuantity'],
                        )
                      else
                        MarketPrice(price),
                      const SizedBox(height: 4),
                      if (listing) ...[
                        if (place.isNotEmpty) ...[
                          Text(
                            place,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: t.typography.label,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Row(
                          children: [
                            Expanded(child: MarketTrader(row, compact: true)),
                            const SizedBox(width: 6),
                            MarketPublished(row['createTime']),
                          ],
                        ),
                      ] else if (!trending)
                        Text(
                          [
                            '${marketText(context, 'sell')} ${row['sellOrderCount'] ?? '—'}',
                            '${marketText(context, 'buy')} ${row['buyOrderCount'] ?? '—'}',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: t.typography.label,
                            color: colors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
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

int marketCompleteRowCount(int count, int columns) =>
    count < columns ? count : (count ~/ columns).clamp(0, 2) * columns;

class MarketListingCounts extends StatelessWidget {
  const MarketListingCounts(this.row, {super.key});
  final MarketRow row;
  @override
  Widget build(BuildContext context) {
    final sell = row['sellOrderCount'], buy = row['buyOrderCount'];
    if (sell == null && buy == null) return const SizedBox.shrink();
    if (sell == 0 && buy == 0) {
      return Text(
        marketLocale(context) == 'en'
            ? 'No listings'
            : marketLocale(context) == 'hant'
            ? '暫無掛單'
            : '暂无挂单',
        style: TextStyle(
          fontSize: 12,
          color: context.tokens.colors.textSecondary,
        ),
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final entry in [
          ('sell', sell, context.tokens.colors.accent),
          ('buy', buy, context.tokens.domainColors.logistics.foreground),
        ])
          if (entry.$2 != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 3, height: 11, color: entry.$3),
                const SizedBox(width: 5),
                Text(
                  marketText(context, entry.$1),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.tokens.colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  marketPrice(context, entry.$2),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: context.tokens.typography.monoFamily,
                  ),
                ),
              ],
            ),
      ],
    );
  }
}

class MarketCatalogCard extends StatelessWidget {
  const MarketCatalogCard(
    this.row, {
    required this.open,
    this.cards = true,
    this.category = 0,
    this.drawer,
    super.key,
  });
  final MarketRow row;
  final VoidCallback? open;
  final bool cards;
  final int category;

  /// Hover drawer content (方案 E), shown for the card layout only.
  final WidgetBuilder? drawer;
  @override
  Widget build(BuildContext context) => MarketHoverCard(
    radius: 0,
    lift: cards,
    drawer: cards ? drawer : null,
    drawerKey: const ValueKey('market-drawer'),
    child: MarketSurface(
      corners: false,
      child: Material(
        color: Colors.transparent,
        child: StarBridgeActionRow(
          inheritContentStyle: true,
          hoverFace: false,
          baseRadius: 12,
          onActivate: open == null ? null : (_, _) => open!(),
          child: cards
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 150,
                      child: MarketArt(
                        marketThumbnail(row),
                        category:
                            (row['categoryId'] as num?)?.toInt() ?? category,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 38,
                            child: Text(
                              marketName(row, marketLocale(context)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            (row['itemNameEn'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.tokens.colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          MarketListingCounts(row),
                        ],
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 36,
                        child: MarketArt(
                          marketThumbnail(row),
                          category:
                              (row['categoryId'] as num?)?.toInt() ?? category,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              marketName(row, marketLocale(context)),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (row['itemNameEn'] is String &&
                                row['itemNameEn'] !=
                                    marketName(row, marketLocale(context)))
                              Text(
                                row['itemNameEn'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.2,
                                  color: context.tokens.colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      MarketListingCounts(row),
                      const SizedBox(width: 10),
                      MarketplaceIcon(
                        MarketplaceGlyph.next,
                        size: 18,
                        color: context.tokens.colors.textSecondary,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    ),
  );
}
