import 'marketplace_port.dart';
import 'package:flutter/foundation.dart';

/// Only explicit detail/confirmation entry points call this cache.
/// Both successes and failures live for five minutes; retries are user driven.
final class MarketOrderFull extends ChangeNotifier {
  MarketOrderFull(this.port, {required this.language, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  final MarketplacePort port;
  final String Function() language;
  final DateTime Function() clock;
  final _cache = <String, (MarketRow?, DateTime)>{};
  final _inflight = <String, Future<MarketRow?>>{};
  final _recent = <String, MarketRow>{};
  int _revision = 0;

  List<MarketRow> get recentOrders =>
      _generation == port.generation ? _recent.values.toList().reversed.toList() : [];

  void rememberOpened(MarketRow row) {
    if (_generation != port.generation) {
      clear(forgetRecent: true);
      _generation = port.generation;
    }
    final number = row['orderNumber'];
    if (number is! String || number.isEmpty) return;
    _recent.remove(number);
    _recent[number] = Map.of(row);
    if (_recent.length > 8) _recent.remove(_recent.keys.first);
  }
  int? _generation;
  static const _window = Duration(minutes: 5);

  static bool needs(MarketRow row) =>
      (row['chatSnapshot'] == true || row['displayType'] == 2 || row['displayType'] == 3) &&
      row['itemsComplete'] != true;

  void clear({bool forgetRecent = false}) {
    _revision++;
    _cache.clear();
    if (forgetRecent) _recent.clear();
    _inflight.clear();
  }

  @override
  void dispose() {
    clear(forgetRecent: true);
    super.dispose();
  }

  /// Read-only cache inspection for copy eligibility; never triggers an order read.
  MarketRow? cachedOrder(String number) {
    if (_generation != port.generation) return null;
    final cached = _cache[number];
    return cached != null && clock().difference(cached.$2) < _window ? cached.$1 : null;
  }

  Future<MarketRow?> fullOrder(MarketRow row,
      {bool retry = false, bool quantity = false}) async {
    if (!quantity && !needs(row)) return row;
    final number = row['orderNumber'];
    if (number is! String || number.isEmpty) return null;
    // Entries belong to one account session: a new generation must never see
    // another session's cached or in-flight answer, even before
    // contextChanged() runs.
    if (_generation != port.generation) {
      clear(forgetRecent: true);
      _generation = port.generation;
    }
    final revision = _revision, generation = port.generation;
    final pending = _inflight[number];
    MarketRow? data;
    if (pending != null) {
      data = await pending;
    } else {
      final cached = _cache[number];
      if (!retry && cached != null &&
          clock().difference(cached.$2) < _window) {
        data = cached.$1;
      } else {
        final work = Future<MarketRow?>.microtask(() => _read(number, revision, generation));
        _inflight[number] = work;
        data = await work;
      }
    }
    if (revision != _revision || generation != port.generation) return null;
    return data == null ? null : {...row, ...data};
  }

  Future<MarketRow?> _read(String number, int revision, int generation) async {
    MarketRow? data;
    if (revision != _revision || generation != port.generation) return null;
    try {
      final result = await port.read('order',
          keyword: number, language: language());
      // A barter answer without a wanted list is not a known-empty list:
      // treat it as unread so the detail never says "未填写" for it.
      if (result.data['itemsComplete'] != true ||
          result.data['orderNumber'] != number ||
          result.data['items'] is! List ||
          result.data['displayType'] == 3 &&
              result.data['wantedItems'] is! List) {
        throw const FormatException('Incomplete order');
      }
      data = {...result.data};
    } on Object {
      data = null;
    } finally {
      if (revision == _revision && generation == port.generation) {
        _cache[number] = (data, clock());
        _inflight.remove(number);
        notifyListeners();
      }
    }
    return data;
  }
}
