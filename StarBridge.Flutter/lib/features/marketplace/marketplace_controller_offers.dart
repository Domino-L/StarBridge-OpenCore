import 'package:flutter/foundation.dart';

import 'marketplace_details.dart' show marketQuality;
import 'marketplace_port.dart';
import 'marketplace_quality.dart';

/// The open item's sell/buy offer lists: filters, sort and paging.
mixin MarketplaceOffers on ChangeNotifier {
  int? get itemId;
  Map<String, MarketRead> get blocks;
  Set<String> get failures;
  @protected
  bool get isDisposed;
  Set<String> get refiltering;
  void refilter(Iterable<String> keys, VoidCallback undo);

  /// Puts the current filters and sort back (cancelling a slow refilter).
  VoidCallback _offerUndo() {
    final filters = {...offerFilters};
    final location = offerLocation;
    final field = offerSortField, desc = offerSortDesc;
    return () {
      offerFilters
        ..clear()
        ..addAll(filters);
      offerLocation = location;
      offerSortField = field;
      offerSortDesc = desc;
    };
  }
  Future<void> load(
    String key,
    String operation, {
    int id,
    String query,
    int category,
    int side,
    int page,
    bool append,
    Map<String, String> options,
  });

  /// Per-item offer filters: creatorStatus, locationId, minQuality,
  /// maxQuality (a tier chosen on the tier strip), sortOrder.
  /// Cleared when a different item opens; applied to both sell and buy pages.
  final offerFilters = <String, String>{};
  MarketRow? offerLocation;

  @protected
  Future<void> loadOffers(int id) => Future.wait([
    load('sell', 'offers', id: id, side: 1, options: {...offerFilters}),
    load('buy', 'offers', id: id, side: 0, options: {...offerFilters}),
  ]);

  /// Effective price direction for a side: explicit choice, else SCM's default.
  String offerSortOrder(bool buy) =>
      offerFilters['sortOrder'] ?? (buy ? 'desc' : 'asc');

  /// Offer sort column: 'price' (SCM sorts it), or 'quality' / 'quantity' /
  /// 'perPoint' (SCM cannot, so every page is loaded and sorted here).
  String offerSortField = 'price';
  bool offerSortDesc = true;

  bool offerSortIsDesc(String field, bool buy) =>
      field == 'price' ? offerSortOrder(buy) == 'desc' : offerSortDesc;

  Future<void> setOfferSort(String field, {required bool buy}) async {
    final id = itemId;
    if (id == null) return;
    final undo = _offerUndo();
    if (field == 'price') {
      final desc = offerSortField == 'price'
          ? offerSortOrder(buy) != 'desc'
          : buy;
      offerSortField = 'price';
      await setOfferFilter('sortOrder', desc ? 'desc' : 'asc');
      return;
    }
    // Price per point reads best low-first; the others high-first.
    offerSortDesc = offerSortField == field
        ? !offerSortDesc
        : field != 'perPoint';
    final reload =
        offerSortField == 'price' && offerFilters.containsKey('sortOrder');
    offerSortField = field;
    if (reload) {
      offerFilters.remove('sortOrder');
      refilter(const ['sell', 'buy'], undo);
    }
    notifyListeners();
    if (reload) await loadOffers(id);
    await _loadAllOffers();
  }

  /// Local sorts need the whole list: read the remaining pages (at most 10).
  Future<void> _loadAllOffers() async {
    for (final buy in [false, true]) {
      for (var guard = 0; guard < 10; guard++) {
        final read = blocks[buy ? 'buy' : 'sell'];
        final total = read?.total;
        if (read == null ||
            total == null ||
            read.rows.length >= total ||
            isDisposed) {
          break;
        }
        final before = read.rows.length;
        await moreOffers(buy);
        if ((blocks[buy ? 'buy' : 'sell']?.rows.length ?? 0) <= before) break;
      }
    }
  }

  List<MarketRow> sortedOffers(List<MarketRow> rows) {
    if (offerSortField == 'price') return _qualityFirstAtSamePrice(rows);
    if (offerSortField == 'perPoint') {
      // No quality, no per-point price: those go last either way.
      num? point(MarketRow r) =>
          marketPerPoint(r['unitPrice'], marketQualityValue(r));
      return [...rows]..sort((a, b) {
        final x = point(a), y = point(b);
        if (x == null || y == null) {
          return x == null ? (y == null ? 0 : 1) : -1;
        }
        return offerSortDesc ? y.compareTo(x) : x.compareTo(y);
      });
    }
    num value(MarketRow r) => offerSortField == 'quality'
        ? num.tryParse(marketQuality(r)?.replaceAll('≥', '') ?? '') ?? -1
        : marketNumber(r['availableQuantity'] ?? r['remainingQuantity']) ?? -1;
    final sorted = [...rows]
      ..sort(
        (a, b) => offerSortDesc
            ? value(b).compareTo(value(a))
            : value(a).compareTo(value(b)),
      );
    return sorted;
  }

  /// SCM's price order, with equal prices showing the higher quality first:
  /// one tier spans 150 points, and at one price buyers want the better one
  /// (user 2026-10-23).
  List<MarketRow> _qualityFirstAtSamePrice(List<MarketRow> rows) {
    final out = <MarketRow>[];
    var run = <MarketRow>[];
    void flush() {
      // Stable: equal quality keeps SCM's order (List.sort is not stable).
      final order = {for (var i = 0; i < run.length; i++) run[i]: i};
      run.sort((a, b) {
        final byQuality = (marketQualityValue(b) ?? -1).compareTo(
          marketQualityValue(a) ?? -1,
        );
        return byQuality != 0 ? byQuality : order[a]!.compareTo(order[b]!);
      });
      out.addAll(run);
      run = [];
    }

    for (final row in rows) {
      final price = marketNumber(row['unitPrice']);
      // Only a known, equal price is a tie; unknown prices keep their place.
      if (run.isNotEmpty &&
          (price == null || marketNumber(run.first['unitPrice']) != price)) {
        flush();
      }
      run.add(row);
    }
    flush();
    return out;
  }

  /// The tier chosen on the tier strip, read back from the quality range.
  MarketQualityTier? get offerTier => MarketQualityTier.values
      .where(
        (tier) =>
            offerFilters['minQuality'] == '${tier.min}' &&
            offerFilters['maxQuality'] == '${tier.max}',
      )
      .firstOrNull;

  /// Shows one tier's offers (null: every quality), one reload for both.
  Future<void> setOfferTier(MarketQualityTier? tier) async {
    final id = itemId;
    final unchanged = tier == null
        ? !offerFilters.containsKey('minQuality') &&
              !offerFilters.containsKey('maxQuality')
        : tier == offerTier;
    if (id == null || unchanged) return;
    final undo = _offerUndo();
    if (tier == null) {
      offerFilters
        ..remove('minQuality')
        ..remove('maxQuality');
    } else {
      offerFilters['minQuality'] = '${tier.min}';
      offerFilters['maxQuality'] = '${tier.max}';
    }
    refilter(const ['sell', 'buy'], undo);
    notifyListeners();
    await loadOffers(id);
  }

  Future<void> setOfferFilter(
    String key,
    String? value, {
    MarketRow? location,
  }) async {
    final id = itemId;
    if (id == null) return;
    final undo = _offerUndo();
    if (value == null) {
      offerFilters.remove(key);
    } else {
      offerFilters[key] = value;
    }
    // The ≥ quality menu replaces a tier range rather than narrowing it.
    if (key == 'minQuality') offerFilters.remove('maxQuality');
    if (key == 'locationId') offerLocation = value == null ? null : location;
    refilter(const ['sell', 'buy'], undo);
    notifyListeners();
    await loadOffers(id);
  }

  Future<void> clearOfferFilters() async {
    final id = itemId;
    if (id == null || (offerFilters.isEmpty && offerSortField == 'price')) {
      return;
    }
    final undo = _offerUndo();
    offerSortField = 'price';
    offerSortDesc = true;
    offerFilters.clear();
    offerLocation = null;
    refilter(const ['sell', 'buy'], undo);
    notifyListeners();
    await loadOffers(id);
  }

  Future<void> moreOffers(bool buy) {
    final key = buy ? 'buy' : 'sell',
        count = blocks[buy ? 'buy' : 'sell']?.rows.length ?? 0;
    return load(
      key,
      'offers',
      id: itemId!,
      side: buy ? 0 : 1,
      page: count ~/ 20 + 1,
      append: true,
      options: {...offerFilters},
    );
  }
}
