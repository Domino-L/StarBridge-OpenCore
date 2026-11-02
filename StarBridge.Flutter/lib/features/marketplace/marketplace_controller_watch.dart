import 'package:flutter/foundation.dart';

import 'marketplace_port.dart';
import 'marketplace_widgets.dart' show marketItemId;

/// One followed item on the 关注 tab (G3, 0.7.2): what it costs now against
/// what it cost when followed. Everything here is local; "changed" is only
/// ever computed from two real readings, never guessed.
@immutable
class MarketWatchEntry {
  const MarketWatchEntry({
    required this.id,
    required this.loaded,
    this.failed = false,
    this.item,
    this.lowest,
    this.count,
    this.highest,
    this.thenPrice,
    this.thenCount,
    this.since,
  });
  final int id;
  final bool loaded, failed;
  final MarketRow? item;
  final num? lowest, highest, thenPrice;
  final int? count, thenCount;
  final DateTime? since;

  /// Lowest ask now against when followed, in percent; null when either is unknown.
  double? get changePercent {
    final now = lowest, then = thenPrice;
    if (now == null || then == null || then <= 0) return null;
    return (now - then) / then * 100;
  }

  /// Sell listings that appeared since following (never negative).
  int get newListings {
    final now = count, then = thenCount;
    if (now == null || then == null || now <= then) return 0;
    return now - then;
  }

  bool get changed =>
      (changePercent?.abs() ?? 0) >= .05 || newListings > 0;
}

/// The 关注 tab's reads and comparisons. Snapshots live in the local
/// preferences (`watched`), next to `favorites`.
mixin MarketplaceWatch on ChangeNotifier {
  Map<String, MarketRead> get blocks;
  Set<String> get failures;
  List<int> get favorites;
  int? get itemId;
  num? bestPrice(int itemId, int side);
  List<MarketRow> get watchedSnapshots;
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
  @protected
  Future<void> saveWatchSnapshots(List<MarketRow> snapshots);

  /// How many favourites the tab reads at once; more on request.
  int watchLimit = 24;

  MarketRow? watchSnapshot(int id) {
    for (final row in watchedSnapshots) {
      if (marketNumber(row['id'])?.toInt() == id) return row;
    }
    return null;
  }

  /// What the item looks like right now, for a snapshot taken on follow.
  MarketRow currentWatchSnapshot(int id) {
    final watch = blocks['watch-price:$id'];
    final sell = itemId == id ? blocks['sell'] ?? watch : watch;
    final price = sell == null
        ? bestPrice(id, 1)
        : marketNumber(sell.rows.firstOrNull?['unitPrice']);
    return {
      'id': id,
      'price': price?.toString(),
      'count': sell?.total,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  MarketWatchEntry watchEntry(int id) {
    final sell = blocks['watch-price:$id'];
    final buy = blocks['watch-buy:$id'];
    final item = blocks['watch:$id']?.data;
    final snapshot = watchSnapshot(id);
    final at = marketNumber(snapshot?['at'])?.toInt();
    return MarketWatchEntry(
      id: id,
      loaded: sell != null,
      failed: failures.contains('watch-price:$id'),
      item: item ?? sell?.rows.firstOrNull,
      lowest: marketNumber(sell?.rows.firstOrNull?['unitPrice']),
      count: sell?.total,
      highest: marketNumber(buy?.rows.firstOrNull?['unitPrice']),
      thenPrice: marketNumber(snapshot?['price']),
      thenCount: marketNumber(snapshot?['count'])?.toInt(),
      since: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  List<MarketWatchEntry> get watchEntries => [
    for (final id in favorites.take(watchLimit)) watchEntry(id),
  ];

  /// Changed items among those read so far (the tab badge and hall summary).
  int get watchChanged => watchEntries.where((e) => e.changed).length;

  Future<void> loadWatch({bool more = false}) async {
    if (more) watchLimit += 24;
    final ids = favorites.take(watchLimit).toList();
    await Future.wait([
      for (final id in ids) ...[
        if (blocks['watch:$id'] == null) load('watch:$id', 'item', id: id),
        load('watch-price:$id', 'offers', id: id),
        load('watch-buy:$id', 'offers', id: id, side: 0),
      ],
    ]);
    await _fillMissingSnapshots(ids);
  }

  // A favourite followed before snapshots existed (or while prices were
  // unknown) takes its first real reading as "when followed", once.
  Future<void> _fillMissingSnapshots(List<int> ids) async {
    final missing = [
      for (final id in ids)
        if (watchSnapshot(id) == null && blocks['watch-price:$id'] != null) id,
    ];
    if (missing.isEmpty) return;
    await saveWatchSnapshots([
      ...watchedSnapshots,
      for (final id in missing) currentWatchSnapshot(id),
    ]);
  }

  /// Ids the hall and cards mark with a red heart.
  bool isWatched(MarketRow row) {
    final id = marketItemId(row) ?? marketNumber(row['id'])?.toInt();
    return id != null && favorites.contains(id);
  }
}
