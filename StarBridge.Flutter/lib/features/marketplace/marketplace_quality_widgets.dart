import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_copy.dart';
import 'marketplace_details.dart' show MarketQualityBadge;
import 'marketplace_diagonal.dart';
import 'marketplace_port.dart';
import 'marketplace_quality.dart';
import 'marketplace_quality_copy.dart';
import 'marketplace_widgets.dart' show MarketPrice, marketMoney;

/// The hall's tier colours: 极品 is foil (this colour only outlines it),
/// 极佳 gold, 良好 cyan, the rest secondary text.
Color marketTierColor(BuildContext context, MarketQualityTier tier) {
  final t = context.tokens;
  return switch (tier) {
    MarketQualityTier.legendary ||
    MarketQualityTier.excellent => MarketplacePalette.gold,
    MarketQualityTier.good => t.domainColors.recon.foreground,
    MarketQualityTier.normal => t.colors.textSecondary,
    _ => t.colors.textDisabled,
  };
}

/// A tier as a hall tag; [range] adds its quality range ("极品 ≥950").
Widget marketTierTag(
  BuildContext context,
  MarketQualityTier tier, {
  bool range = false,
  String? mono,
}) => MarketSlantTag(
  range ? qualityTierRange(context, tier) : marketText(context, tier.name),
  color: marketTierColor(context, tier),
  mono: mono,
  foil: tier == MarketQualityTier.legendary,
);

MarketRow _qualityRow(num quality) => {
  'qualityData': {'type': 'material', 'quality': quality},
};

String _perPoint(BuildContext context, num value) =>
    qualityText(context, 'perPoint', n: marketPerPointFigure(value));

/// A price per point for display: whole aUEC from 100 up, decimals below, so
/// a cheap ore (100 aUEC at quality 600) never reads as 0.
String marketPerPointFigure(num value) => value >= 100
    ? marketMoney(value.round())
    : value.toStringAsFixed(value >= 10 ? 1 : 2);

/// A trending quality item: the lowest ask at any quality (with that
/// listing's quality) and the lowest in the best tier that has listings.
List<Widget> marketTrendingQualityLines(BuildContext context, MarketRow row) {
  final colors = context.tokens.colors;
  final any = Map<String, Object?>.from(row['qualityAny'] as Map);
  final top = row['qualityTop'] is Map
      ? Map<String, Object?>.from(row['qualityTop'] as Map)
      : null;
  final topTier = MarketQualityTier.byKey(top?['key']);
  final quality = marketNumber(any['quality']);
  return [
    Row(
      children: [
        Text(
          qualityText(context, 'anyQuality'),
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
        const Spacer(),
        if (quality != null) MarketQualityBadge(_qualityRow(quality)),
      ],
    ),
    MarketPrice(any['lowest']),
    if (topTier != null)
      Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            marketTierTag(context, topTier, range: true),
            const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: MarketPrice(top!['lowest'], size: 13),
              ),
            ),
          ],
        ),
      ),
  ];
}

/// The hover box's tier ladder: each tier's lowest ask with its quality and
/// listing count, plus the best-value listing when it is another one. The
/// cheapest tier overall is tinted; empty tiers stay listed as 暂无.
class MarketTierLadder extends StatelessWidget {
  const MarketTierLadder(this.tiers, {super.key});
  final MarketQualityTiers tiers;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mono = TextStyle(
      fontFamily: t.typography.monoFamily,
      fontSize: 12,
      fontWeight: t.typography.emphasisWeight,
    );
    final small = TextStyle(fontSize: 10.5, color: t.colors.textSecondary);
    final cheapest = [
      for (final q in tiers.tiers)
        if (q.lowest != null) q.lowest!,
    ].fold<num?>(null, (a, b) => a == null || b < a ? b : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final quote in tiers.tiers) ...[
          Container(
            key: ValueKey(('market-tier-ladder', quote.tier.name)),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            color: quote.lowest != null && quote.lowest == cheapest
                ? t.colors.accent.withValues(alpha: .1)
                : null,
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: marketTierTag(context, quote.tier, range: true),
                  ),
                ),
                Expanded(
                  // Two texts: the price is mono, the quality label is not
                  // (the mono face has no CJK glyphs).
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          quote.lowest == null
                              ? qualityText(context, 'tierEmpty')
                              : marketMoney(quote.lowest),
                          style: quote.lowest == null ? small : mono,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                        ),
                      ),
                      if (quote.quality != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${marketText(context, 'quality')} ${quote.quality!.round()}',
                          style: small,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    quote.known ? '×${quote.count}' : '—',
                    textAlign: TextAlign.right,
                    style: small,
                  ),
                ),
              ],
            ),
          ),
          if (quote.bestDiffers)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 40, 3),
              child: Row(
                children: [
                  Text(
                    '★ ${quote.bestComplete ? qualityText(context, 'bestValue') : qualityText(context, 'bestValuePartial', n: '${quote.bestScanned ?? '—'}')}',
                    style: TextStyle(fontSize: 10.5, color: t.colors.success),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${marketMoney(quote.bestPrice)} · ${quote.bestQuality?.round() ?? '—'}${quote.bestPerPoint == null ? '' : ' · ${_perPoint(context, quote.bestPerPoint!)}'}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: t.typography.monoFamily,
                        fontSize: 10.5,
                        color: t.colors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// The item page's tier strip: 全部档 plus one chip per tier with its lowest
/// ask and count. Choosing a tier filters the offers to its quality range.
class MarketTierStrip extends StatelessWidget {
  const MarketTierStrip(
    this.tiers, {
    required this.selected,
    required this.select,
    super.key,
  });
  final MarketQualityTiers tiers;
  final MarketQualityTier? selected;
  final void Function(MarketQualityTier? tier) select;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final total = tiers.sellCount;
    Widget chip({
      required Key key,
      required Widget title,
      required String range,
      required num? lowest,
      required int? count,
      required bool on,
      required VoidCallback onTap,
    }) => SizedBox(
      width: 128,
      child: StarBridgeActionRow(
        controlKey: key,
        inheritContentStyle: true,
        baseRadius: 4,
        onActivate: (_, _) => onTap(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
          decoration: BoxDecoration(
            color: on
                ? t.colors.accent.withValues(alpha: .12)
                : t.surfaces.raised.fill,
            border: Border.all(
              color: on ? t.colors.accent : t.surfaces.panel.border,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              title,
              const SizedBox(height: 3),
              Text(
                range,
                style: TextStyle(
                  fontFamily: t.typography.monoFamily,
                  fontSize: 10,
                  color: t.colors.textDisabled,
                ),
              ),
              Text(
                lowest == null
                    ? qualityText(context, 'tierEmpty')
                    : marketMoney(lowest),
                style: TextStyle(
                  fontFamily: lowest == null ? null : t.typography.monoFamily,
                  fontSize: 12.5,
                  fontWeight: lowest == null
                      ? null
                      : t.typography.emphasisWeight,
                  color: lowest == null ? t.colors.textDisabled : null,
                ),
              ),
              Text(
                count == null
                    ? '—'
                    : qualityText(context, 'tierCount', n: count),
                style: TextStyle(fontSize: 10, color: t.colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
    return SingleChildScrollView(
      key: const Key('market-tier-strip'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            key: const ValueKey(('market-tier', 'all')),
            title: Text(
              qualityText(context, 'allTiers'),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: t.typography.emphasisWeight,
              ),
            ),
            range: '0–1000',
            lowest: tiers.sellLowest,
            count: total,
            on: selected == null,
            onTap: () => select(null),
          ),
          for (final quote in tiers.tiers) ...[
            const SizedBox(width: 6),
            chip(
              key: ValueKey(('market-tier', quote.tier.name)),
              title: marketTierTag(context, quote.tier),
              range: switch (quote.tier) {
                MarketQualityTier.legendary => '≥${quote.tier.min}',
                MarketQualityTier.inferior => '<${quote.tier.max + 1}',
                _ => '${quote.tier.min}–${quote.tier.max}',
              },
              lowest: quote.lowest,
              count: quote.known ? quote.count : null,
              on: selected == quote.tier,
              onTap: () => select(quote.tier),
            ),
          ],
        ],
      ),
    );
  }
}

/// Publishing a quality sell listing: compared with its own tier only — the
/// tier's lowest ask, then the price per point against the tier's best value
/// (user 2026-10-23). Null until the tier read is in.
Widget? marketTierPriceDelta(
  BuildContext context, {
  required MarketQualityTiers? tiers,
  required num price,
  required num quality,
}) {
  if (tiers == null || !tiers.hasQuality || quality <= 0) return null;
  final t = context.tokens;
  final tier = MarketQualityTier.of(quality);
  final quote = tiers.of(tier);
  final name = marketText(context, tier.name);
  final range = qualityTierRange(context, tier);
  final lowest = quote?.lowest;
  final ok = lowest == null || price <= lowest;
  final mine = price / quality;
  final best = quote?.bestPerPoint;
  final partial = quote?.bestComplete == false;
  final style = TextStyle(fontSize: 12, color: t.colors.textSecondary);
  final good = TextStyle(fontSize: 12, color: t.colors.success);
  final warn = TextStyle(fontSize: 12, color: t.colors.warning);
  return Column(
    key: const Key('market-publish-tier-delta'),
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (lowest != null)
        Text(
          '${qualityText(context, 'sameTierLowest', tier: range)} ${marketMoney(lowest)}',
          style: style,
        ),
      Text(
        ok
            ? qualityText(context, 'becomesTierLowest', tier: name)
            : qualityText(
                context,
                'aboveTierLowest',
                // A free (0 aUEC) lowest has no percentage, only the gap (CX-58).
                n: lowest > 0
                    ? '${marketMoney(price - lowest)}（+${((price - lowest) / lowest * 100).toStringAsFixed(1)}%）'
                    : marketMoney(price - lowest),
              ),
        style: ok ? good : warn,
      ),
      Text.rich(
        TextSpan(
          text:
              '${qualityText(context, 'yourPerPoint')} ${_perPoint(context, mine)}',
          children: [
            if (best != null && best > 0) ...[
              TextSpan(
                text:
                    ' · ${qualityText(context, partial ? 'tierBestPerPointPartial' : 'tierBestPerPoint', n: marketPerPointFigure(best))} → ',
              ),
              mine <= best
                  ? TextSpan(
                      text: qualityText(
                        context,
                        partial ? 'alsoBestValuePartial' : 'alsoBestValue',
                      ),
                      style: good,
                    )
                  : TextSpan(
                      text: qualityText(
                        context,
                        'perPointAbove',
                        n: '${((mine - best) / best * 100).toStringAsFixed(0)}%',
                      ),
                      style: warn,
                    ),
            ],
          ],
        ),
        style: style,
      ),
    ],
  );
}
