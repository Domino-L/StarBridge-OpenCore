import 'marketplace_details.dart' show marketQuality;
import 'marketplace_port.dart';

/// SCM material quality tiers (user 2026-10-23, preview quality-tiers.html):
/// 极品 is new; the others keep the hall's existing names. Prices are only
/// compared inside one tier, and inside a tier by price per quality point.
enum MarketQualityTier {
  legendary(950, 1000),
  excellent(800, 949),
  good(600, 799),
  normal(400, 599),
  poor(200, 399),
  inferior(0, 199);

  const MarketQualityTier(this.min, this.max);
  final int min, max;

  static MarketQualityTier of(num quality) =>
      values.firstWhere((tier) => quality >= tier.min, orElse: () => inferior);

  static MarketQualityTier? byKey(Object? key) =>
      values.where((tier) => tier.name == key).firstOrNull;
}

/// The listing's quality as a number ("≥812" reads as 812), or null.
num? marketQualityValue(MarketRow row) =>
    num.tryParse(marketQuality(row)?.replaceAll('≥', '') ?? '');

/// Price per quality point, the in-tier value measure; null without quality.
num? marketPerPoint(Object? price, Object? quality) {
  final p = marketNumber(price), q = marketNumber(quality);
  return p == null || q == null || q <= 0 ? null : p / q;
}

/// One tier's live market: its lowest ask (with that listing's quality), the
/// listing with the lowest price per point, and how many listings it holds.
final class MarketTierQuote {
  const MarketTierQuote({
    required this.tier,
    required this.known,
    this.lowest,
    this.quality,
    this.bestPrice,
    this.bestQuality,
    this.perPoint,
    this.count = 0,
    this.bestComplete = true,
    this.bestScanned,
  });
  final MarketQualityTier tier;
  final bool known;
  final num? lowest, quality, bestPrice, bestQuality, perPoint;
  final int count;

  /// False when the Host could not read the whole tier (CX-T12): [perPoint]
  /// is then only the best of the [bestScanned] listings it compared.
  final bool bestComplete;
  final int? bestScanned;

  /// The best listing's exact price per point, for comparing; the Host's
  /// [perPoint] is a display figure and may be rounded (CX-56).
  num? get bestPerPoint => marketPerPoint(bestPrice, bestQuality) ?? perPoint;

  /// The best-value listing is a different one from the cheapest.
  bool get bestDiffers =>
      bestPrice != null && (bestPrice != lowest || bestQuality != quality);
}

/// The Host's `qualityTiers` read for one item (CX-T02). Every figure is a
/// live read of SCM's order book, unlike the trending averages.
final class MarketQualityTiers {
  const MarketQualityTiers({
    required this.hasQuality,
    this.sellLowest,
    this.sellQuality,
    this.sellCount,
    this.buyHighest,
    this.buyCount,
    this.tiers = const [],
  });

  factory MarketQualityTiers.from(MarketRow data) {
    MarketRow part(String key) =>
        data[key] is Map ? Map<String, Object?>.from(data[key] as Map) : {};
    int? count(MarketRow row) =>
        row['known'] == false ? null : marketNumber(row['count'])?.toInt();
    final sell = part('sell'), buy = part('buy');
    return MarketQualityTiers(
      hasQuality: data['hasQuality'] == true,
      sellLowest: marketNumber(sell['lowest']),
      sellQuality: marketNumber(sell['quality']),
      sellCount: count(sell),
      buyHighest: marketNumber(buy['highest']),
      buyCount: count(buy),
      tiers: [
        for (final row in marketRows(data['tiers']))
          if (MarketQualityTier.byKey(row['key']) case final tier?)
            _quote(tier, row),
      ],
    );
  }

  static MarketTierQuote _quote(MarketQualityTier tier, MarketRow row) {
    final best = row['best'] is Map
        ? Map<String, Object?>.from(row['best'] as Map)
        : const <String, Object?>{};
    return MarketTierQuote(
      tier: tier,
      known: row['known'] != false,
      lowest: marketNumber(row['lowest']),
      quality: marketNumber(row['quality']),
      bestPrice: marketNumber(best['price']),
      bestQuality: marketNumber(best['quality']),
      perPoint: marketNumber(best['perPoint']),
      count: marketNumber(row['count'])?.toInt() ?? 0,
      bestComplete: row['bestComplete'] != false,
      bestScanned: marketNumber(row['bestScanned'])?.toInt(),
    );
  }

  final bool hasQuality;
  final num? sellLowest, sellQuality, buyHighest;
  final int? sellCount, buyCount;
  final List<MarketTierQuote> tiers;

  MarketTierQuote? of(MarketQualityTier tier) =>
      tiers.where((quote) => quote.tier == tier).firstOrNull;
}

/// Per-item tier reads, asked for only when a hover box, an item page or the
/// publish dialog shows them; one minute fresh, like the Host's cache. A
/// failed read is not retried for the same minute.
final class MarketQualityTiersStore {
  MarketQualityTiersStore({
    required this.read,
    required this.changed,
    this.now = DateTime.now,
  });

  final Future<MarketRead> Function(int itemId) read;
  final void Function() changed;
  final DateTime Function() now;

  static const _window = Duration(minutes: 1);
  final _tiers = <int, (MarketQualityTiers, DateTime)>{};
  final _failed = <int, DateTime>{};
  final _loading = <int>{};
  int _revision = 0;

  MarketQualityTiers? of(int itemId) => _tiers[itemId]?.$1;
  bool loading(int itemId) => _loading.contains(itemId);

  /// True when [ensure] would read again. A shown figure calls [ensure]
  /// whenever this is true, so a cached value is never shown as live for
  /// longer than the one-minute window (CX-55).
  bool stale(int itemId) =>
      !_loading.contains(itemId) &&
      !_fresh(_tiers[itemId]?.$2) &&
      !_fresh(_failed[itemId]);

  bool _fresh(DateTime? at) => at != null && now().difference(at) <= _window;

  void clear() {
    _revision++;
    _tiers.clear();
    _failed.clear();
    _loading.clear();
  }

  Future<void> ensure(int itemId) async {
    if (!stale(itemId)) return;
    final revision = _revision;
    _loading.add(itemId);
    try {
      final result = await read(itemId);
      if (revision != _revision) return;
      _tiers[itemId] = (MarketQualityTiers.from(result.data), now());
    } on Object {
      if (revision != _revision) return;
      _failed[itemId] = now();
    } finally {
      if (revision == _revision) {
        _loading.remove(itemId);
        changed();
      }
    }
  }
}
