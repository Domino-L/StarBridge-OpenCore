import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_port.dart';
import 'marketplace_quality.dart';
import 'marketplace_quality_copy.dart';
import 'marketplace_quality_widgets.dart';
import 'marketplace_widgets.dart' show marketMoney;

// Tier pricing on the item page (user 2026-10-23): the tier strip above the
// sell offers, tier groups when every quality is shown, and the price per
// quality point with the best value in each tier marked.

/// The tier strip for the open item's sell offers, once SCM says the item
/// has quality. Reads the item's tiers on first build.
class MarketItemTierSection extends StatelessWidget {
  const MarketItemTierSection(this.c, {super.key});
  final MarketplaceController c;

  @override
  Widget build(BuildContext context) {
    final id = c.itemId;
    if (id == null) return const SizedBox.shrink();
    if (c.qualityTiers.stale(id)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(c.qualityTiers.ensure(id)),
      );
    }
    final tiers = c.qualityTiers.of(id);
    if (tiers == null) return const SizedBox.shrink();
    if (!tiers.hasQuality) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarketTierStrip(
            tiers,
            selected: c.offerTier,
            select: (tier) => unawaited(c.setOfferTier(tier)),
          ),
          const SizedBox(height: 6),
          Text(
            qualityText(context, 'perPointHint'),
            style: TextStyle(
              fontSize: 11,
              color: context.tokens.colors.textDisabled,
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry of the offer list: a tier header or an offer row.
typedef MarketOfferEntry = ({MarketQualityTier? header, MarketRow? row});

/// The offers as displayed: grouped by tier (highest first, each group in
/// the given order) when [group], else as given.
List<MarketOfferEntry> marketOfferEntries(
  List<MarketRow> rows, {
  required bool group,
}) {
  if (!group) return [for (final row in rows) (header: null, row: row)];
  final byTier = <MarketQualityTier, List<MarketRow>>{};
  final plain = <MarketRow>[];
  for (final row in rows) {
    final q = marketQualityValue(row);
    if (q == null) {
      plain.add(row);
    } else {
      byTier.putIfAbsent(MarketQualityTier.of(q), () => []).add(row);
    }
  }
  return [
    for (final tier in MarketQualityTier.values)
      if (byTier[tier] case final list?) ...[
        (header: tier, row: null),
        for (final row in list) (header: null, row: row),
      ],
    for (final row in plain) (header: null, row: row),
  ];
}

/// Per tier, the loaded offer with the lowest price per point (ties: the
/// higher quality), by order number.
Set<Object?> marketBestValueOrders(List<MarketRow> rows) {
  final best = <MarketQualityTier, (MarketRow, num, num)>{};
  for (final row in rows) {
    final q = marketQualityValue(row);
    final point = marketPerPoint(row['unitPrice'], q);
    if (q == null || point == null) continue;
    final tier = MarketQualityTier.of(q);
    final current = best[tier];
    if (current == null ||
        point < current.$2 ||
        (point == current.$2 && q > current.$3)) {
      best[tier] = (row, point, q);
    }
  }
  return {for (final entry in best.values) entry.$1['orderNumber']};
}

/// A tier group's header: the tier, its listing count, lowest ask and best
/// price per point, from the tier read when present.
class MarketTierGroupHeader extends StatelessWidget {
  const MarketTierGroupHeader(this.tier, {this.quote, super.key});
  final MarketQualityTier tier;
  final MarketTierQuote? quote;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final q = quote;
    return Container(
      key: ValueKey(('market-tier-group', tier.name)),
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.surfaces.panel.border)),
      ),
      child: Row(
        children: [
          marketTierTag(context, tier, range: true),
          const SizedBox(width: 8),
          if (q != null && q.known && q.lowest != null)
            Flexible(
              child: Text(
                qualityText(
                      context,
                      q.bestComplete ? 'tierHeader' : 'tierHeaderPartial',
                      n: q.count,
                    )
                    .replaceAll('{low}', marketMoney(q.lowest))
                    .replaceAll('{s}', '${q.bestScanned ?? '—'}')
                    .replaceAll(
                      '{pp}',
                      q.bestPerPoint == null
                          ? '—'
                          : marketPerPointFigure(q.bestPerPoint!),
                    ),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(fontSize: 11.5, color: t.colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// The price per point under an offer's price; the tier's best value is
/// marked. Nothing for offers without quality.
class MarketOfferPerPoint extends StatelessWidget {
  const MarketOfferPerPoint(this.row, {required this.best, super.key});
  final MarketRow row;
  final bool best;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final point = marketPerPoint(row['unitPrice'], marketQualityValue(row));
    if (point == null) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(
        children: [
          if (best)
            TextSpan(
              text: '${qualityText(context, 'bestLoaded')} ',
              style: TextStyle(
                color: t.colors.success,
                fontWeight: t.typography.emphasisWeight,
              ),
            ),
          TextSpan(
            text: qualityText(
              context,
              'perPoint',
              n: marketPerPointFigure(point),
            ),
          ),
        ],
      ),
      key: ValueKey(('market-offer-per-point', row['orderNumber'])),
      style: TextStyle(
        fontFamily: t.typography.monoFamily,
        fontSize: 10.5,
        color: best ? t.colors.success : t.colors.textSecondary,
      ),
    );
  }
}
