import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_details.dart' show marketQualityRequired;
import 'marketplace_port.dart';
import 'marketplace_quality.dart';
import 'marketplace_quality_copy.dart';
import 'marketplace_widgets.dart' show marketItemId, marketMoney;
import '../../design_system/surfaces/light_visual_text.dart';

// A buy order seen from the seller's side (user 2026-11-07: "求购应该算怎么卖
// 能赚更多钱 才是划算"): the higher the bid, the better. It is compared with
// what the same goods cost to list today, the lowest ask that meets the
// order's quality requirement.

enum MarketBidVerdict { high, near, low }

/// Bids at or above this share of the reference read as near it.
const marketBidNearShare = 0.85;

/// The reference ask for a bid and how the bid compares; null when there is
/// nothing to compare with (no asks, read failed or still loading).
({num reference, bool tiered, MarketBidVerdict verdict})? marketBidValue(
  MarketQualityTiers? tiers, {
  required num price,
  num? minQuality,
}) {
  if (tiers == null) return null;
  num? reference;
  final tiered = minQuality != null && tiers.hasQuality;
  if (tiered) {
    final needed = MarketQualityTier.of(minQuality);
    for (final quote in tiers.tiers) {
      final lowest = quote.lowest;
      if (!quote.known || lowest == null) continue;
      // Every ask in a higher tier meets the requirement; in its own tier
      // only when the cheapest ask itself is good enough.
      final meets =
          quote.tier.min > minQuality ||
          quote.tier == needed && (quote.quality ?? -1) >= minQuality;
      if (meets && (reference == null || lowest < reference)) {
        reference = lowest;
      }
    }
  } else {
    reference = tiers.sellLowest;
  }
  if (reference == null || reference <= 0) return null;
  return (
    reference: reference,
    tiered: tiered,
    verdict: price >= reference
        ? MarketBidVerdict.high
        : price >= reference * marketBidNearShare
        ? MarketBidVerdict.near
        : MarketBidVerdict.low,
  );
}

/// The verdict line under a buy order's price: "卖给他：出价高" and how far
/// from the reference ask. Reads the item's tiers when they are stale.
class MarketBidValueLine extends StatelessWidget {
  const MarketBidValueLine(this.c, this.row, {this.detail = true, super.key});
  final MarketplaceController c;
  final MarketRow row;

  /// Adds the gap to the reference ask as a second line.
  final bool detail;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // The tier read lands later; follow it wherever this line sits.
    listenable: c,
    builder: (context, _) => _line(context),
  );

  Widget _line(BuildContext context) {
    final t = context.tokens;
    // An item page's offers belong to the open item.
    final id = marketItemId(row) ?? c.itemId;
    final price = marketNumber(row['unitPrice']);
    if (id == null || price == null) return const SizedBox.shrink();
    if (c.qualityTiers.stale(id)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(c.qualityTiers.ensure(id)),
      );
    }
    final tiers = c.qualityTiers.of(id);
    if (tiers == null) return const SizedBox.shrink();
    final value = marketBidValue(
      tiers,
      price: price,
      minQuality: marketQualityRequired(row) ? marketQualityValue(row) : null,
    );
    final style = TextStyle(fontSize: 10.5, color: t.colors.textSecondary);
    if (value == null) {
      return Text(
        qualityText(context, 'bidNoRef'),
        key: ValueKey(('market-bid-value', row['orderNumber'])),
        style: style.copyWith(color: t.colors.textDisabled),
      );
    }
    final color = switch (value.verdict) {
      MarketBidVerdict.high => t.colors.success,
      MarketBidVerdict.near => t.colors.textSecondary,
      MarketBidVerdict.low => t.colors.warning,
    };
    final ref = qualityText(context, value.tiered ? 'bidRefTier' : 'bidRefAny');
    final gap = (price - value.reference).abs();
    final pct = (gap / value.reference * 100).toStringAsFixed(1);
    final share = (price / value.reference * 100).toStringAsFixed(0);
    final line =
        switch (value.verdict) {
              MarketBidVerdict.high => qualityText(context, 'bidMore'),
              MarketBidVerdict.near => qualityText(context, 'bidShare'),
              MarketBidVerdict.low => qualityText(context, 'bidLess'),
            }
            .replaceAll('{ref}', ref)
            .replaceAll('{p}', marketMoney(value.reference))
            .replaceAll('{n}', marketMoney(gap))
            .replaceAll(
              '{pct}',
              value.verdict == MarketBidVerdict.near ? share : pct,
            );
    return Column(
      key: ValueKey(('market-bid-value', row['orderNumber'])),
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          qualityText(context, switch (value.verdict) {
            MarketBidVerdict.high => 'bidHigh',
            MarketBidVerdict.near => 'bidNear',
            MarketBidVerdict.low => 'bidLow',
          }),
          style: style.copyWith(
            color: color,
            fontWeight: t.typography.emphasisWeight,
          ),
        ),
        if (detail)
          Text(
            line,
            maxLines: 1,
            overflow: fadeOverflow(context),
            softWrap: false,
            style: style.copyWith(color: color),
          ),
      ],
    );
  }
}
