import 'marketplace_port.dart';

/// Best live price per item and side (lowest sell, highest buy), read lazily
/// for the cards on screen only: one batched Host request, 5 minute cache.
/// Unknown stays unknown, and a failed or unanswered item is remembered for
/// the same window so a failing source is not asked every frame.
final class MarketBestPrices {
  MarketBestPrices({
    required this.read,
    required this.isCurrent,
    required this.changed,
  });

  /// Reads `bestPrices` for the `id:side,...` keyword.
  final Future<MarketRead> Function(String keyword) read;

  /// Whether a reply that started under [revision] still belongs on screen.
  final bool Function(int revision) isCurrent;
  final void Function() changed;

  static const _window = Duration(minutes: 5);
  final _best = <String, (num?, DateTime)>{};
  final _loading = <String>{};
  final _failed = <String, DateTime>{};

  num? price(int itemId, int side) => _best['$itemId:$side']?.$1;
  bool has(int itemId, int side) => _best.containsKey('$itemId:$side');

  void clear() {
    _best.clear();
    _loading.clear();
    _failed.clear();
  }

  Future<void> ensure(Iterable<(int, int)> wanted, int revision) async {
    final now = DateTime.now();
    bool fresh(DateTime? at) => at != null && now.difference(at) <= _window;
    final todo = [
      for (final (id, s) in wanted.toSet())
        if (!_loading.contains('$id:$s') &&
            !fresh(_failed['$id:$s']) &&
            !fresh(_best['$id:$s']?.$2))
          (id, s),
    ].take(10).toList();
    if (todo.isEmpty) return;
    for (final (id, s) in todo) {
      _loading.add('$id:$s');
    }
    try {
      // One bridge call; the Host reads one sorted row per item from SCM.
      final result = await read(todo.map((p) => '${p.$1}:${p.$2}').join(','));
      if (!isCurrent(revision)) return;
      final at = DateTime.now();
      for (final row in result.rows) {
        final id = marketNumber(row['id'])?.toInt(), s = marketNumber(row['side'])?.toInt();
        if (id != null && s != null) _best['$id:$s'] = (marketNumber(row['price']), at);
      }
      for (final (id, s) in todo) {
        if (!_best.containsKey('$id:$s')) _failed['$id:$s'] = at;
      }
      changed();
    } on Object {
      if (isCurrent(revision)) {
        final at = DateTime.now();
        for (final (id, s) in todo) {
          _failed['$id:$s'] = at;
        }
      }
    } finally {
      for (final (id, s) in todo) {
        _loading.remove('$id:$s');
      }
    }
  }
}
