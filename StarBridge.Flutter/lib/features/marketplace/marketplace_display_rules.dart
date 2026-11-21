import 'dart:convert';

import 'marketplace_port.dart';
import 'marketplace_quality.dart';

num? _quality(MarketRow row) {
  final raw = marketRows(row['items']).firstOrNull?['qualityData'] ?? row['qualityData'];
  try {
    final data = raw is String ? jsonDecode(raw) : raw;
    return data is Map && data['type'] == 'material'
        ? marketNumber(data['qualityMin'] ?? data['quality']) : null;
  } on FormatException {
    return null;
  }
}

/// Buy requirements are compared locally; SCM only filters stored `quality`.
Map<String, String> marketReadFilters(Map<String, String> filters,
    {required bool buy}) => {
  for (final entry in filters.entries)
    if (!buy || (entry.key != 'minQuality' && entry.key != 'maxQuality'))
      entry.key: entry.value,
};

List<MarketRow> marketBuyQualityRows(List<MarketRow> rows,
    Map<String, String> filters) {
  final ceiling = num.tryParse(filters['minQuality'] ?? '');
  if (ceiling == null) return rows;
  return rows.where((row) {
    // No stated requirement accepts any quality. A tier means its lower bound:
    // every item in that tier can satisfy these buy orders.
    final requirement = _quality(row);
    return requirement == null || requirement <= ceiling;
  }).toList();
}

bool marketBundleType(Map<String, String> filters) =>
    filters['displayType'] == '2' || filters['displayType'] == '3';

/// Only sort the rows already loaded; never fetch extra pages for this sort.
List<MarketRow> marketBundlePriceRows(List<MarketRow> rows, {required bool buy}) =>
    [...rows]..sort((a, b) {
      final x = marketNumber(a['unitPrice']), y = marketNumber(b['unitPrice']);
      if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
      return buy ? y.compareTo(x) : x.compareTo(y);
    });

num? marketTierLowest(MarketRow row, MarketQualityTiers? tiers) {
  final quality = _quality(row);
  if (quality == null) return null;
  final quote = tiers?.of(MarketQualityTier.of(quality));
  return quote?.known == true ? quote?.lowest : null;
}

bool marketSameQualityTier(MarketRow order, MarketRow other) {
  final q = _quality(order), candidate = _quality(other);
  return q == null || candidate != null &&
      MarketQualityTier.of(q) == MarketQualityTier.of(candidate);
}

num? marketItemOrderCount(MarketRow? item, {required bool buy}) {
  final singles = marketNumber(item?[buy ? 'buyOrderCount' : 'sellOrderCount']);
  final bundles = marketNumber(item?[buy ? 'checklistBuyCount' : 'checklistSellCount']);
  return singles == null || bundles == null ? null : singles + bundles;
}

/// LS11 (SCM bug, tested 11-15): SCM adds checklist line prices without
/// multiplying by quantity in lists, details and trades, while its publish
/// form and editor multiply. Only a line above 1 makes the two differ.
bool marketChecklistHasMultiples(Object? items) => marketRows(items)
    .any((item) => (marketNumber(item['quantity']) ?? 1) > 1);
