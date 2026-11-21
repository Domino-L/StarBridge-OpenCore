import 'marketplace_port.dart';

/// Run-local choices, owned by the market session and reset on account changes.
final class MarketTradeLocations {
  MarketTradeLocations(this.port);
  final MarketplacePort port;
  List<MarketRow>? _rows;
  int? _selected, _generation;
  int _revision = 0;
  Future<List<MarketRow>?>? _pending;

  void clear() {
    _revision++;
    _rows = null;
    _selected = null;
    _pending = null;
  }

  void _sync() {
    if (_generation == port.generation) return;
    clear();
    _generation = port.generation;
  }

  int? get selected {
    _sync();
    return _selected;
  }

  void choose(int value) {
    _sync();
    if (_rows?.any((r) => marketNumber(r['id']) == value) == true) {
      _selected = value;
    }
  }

  Future<List<MarketRow>?> load() {
    _sync();
    if (_rows != null) return Future.value(_rows);
    return _pending ??= _read(_revision, port.generation);
  }

  Future<List<MarketRow>?> _read(int revision, int generation) async {
    try {
      final rows = <Object?, MarketRow>{};
      // Bounded like every other hall read: at most 10 pages (500 places).
      for (var page = 1; page <= 10; page++) {
        final result = await port.read('locations', page: page);
        if (revision != _revision || generation != port.generation) return null;
        final before = rows.length;
        for (final row in result.rows) {
          if (marketNumber(row['id']) != null) rows[row['id']] = row;
        }
        if (result.total != null ? rows.length >= result.total! : result.rows.length < 50) {
          return _rows = rows.values.toList();
        }
        // An incomplete or repeating page is a failed load, never a partial picker.
        if (rows.length == before) return null;
      }
      return rows.isEmpty ? null : _rows = rows.values.toList();
    } on Object {
      return null;
    } finally {
      if (revision == _revision && generation == port.generation) _pending = null;
    }
  }
}

List<(String, Object)> tradeLocationRows(MarketRow row) => [
  if (row['locationName'] case final String name when name.trim().isNotEmpty)
    (row['creatorType'] == 1 ? '卖家发货位置' : '买家收货位置', name),
  if (row['transactionLocationName'] case final String name when name.trim().isNotEmpty)
    (row['creatorType'] == 1 ? '买家收货位置' : '卖家发货位置', name),
];
