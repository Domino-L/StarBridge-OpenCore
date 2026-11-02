import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'marketplace_category_roots.dart';
import 'marketplace_port.dart';
import 'marketplace_prefetch.dart';

/// Market-only state. Item navigation does not own or reset this query.
class MarketplaceBrowser extends ChangeNotifier {
  MarketplaceBrowser(this.port);
  final MarketplacePort port;
  String kind = 'items',
      itemLayout = 'cards',
      orderLayout = 'cards',
      keyword = '';
  String language = 'CN';
  MarketRow? location;
  int category = 0;
  bool listed = true, loading = false, failed = false;
  final options = <String, String>{};
  List<MarketRow> _categories = [];
  List<MarketRow> get categories => _categories;
  set categories(List<MarketRow> rows) {
    _categories = rows;
    marketRememberCategories(rows);
  }

  MarketRead? result;
  final overview = <String, int>{};
  bool overviewFailed = false, _overviewLoaded = false;
  int _overviewEpoch = 0;
  double offset = 0;
  int _epoch = 0, _page = 1;
  bool _disposed = false;
  String get layout => kind == 'items' ? itemLayout : orderLayout;
  List<MarketRow> get path {
    final rows = <MarketRow>[];
    var id = category;
    final seen = <int>{};
    while (id > 0 && seen.add(id)) {
      final row = categories.where((r) => r['id'] == id).firstOrNull;
      if (row == null) break;
      rows.insert(0, row);
      id = marketNumber(row['parentId'])?.toInt() ?? 0;
    }
    return rows;
  }

  MarketRow get config {
    for (final row in path.reversed) {
      try {
        final raw = row['filterConfig'];
        final parsed = raw is String ? jsonDecode(raw) : raw;
        if (parsed is Map) return Map<String, Object?>.from(parsed);
      } on FormatException {
        /* Invalid child config inherits its parent. */
      }
    }
    return const {};
  }

  Future<void> initialize(List<MarketRow> rows) async {
    categories = rows;
    if (result == null && !loading) await reload();
  }

  Future<void> choose({int? category, String? keyword, String? kind}) async {
    if (category != null) {
      this.category = category;
      listed = true;
      this.keyword = '';
    }
    if (keyword != null) {
      this.keyword = keyword;
      listed = false;
    }
    if (kind != null) {
      this.kind = kind;
      if (kind == 'orders') this.category = 0;
    }
    options.clear();
    location = null;
    await reload(reset: true);
  }

  Future<void> filter(String key, String? value) async {
    if (key == 'locationId' && (value == null || value.isEmpty)) {
      location = null;
    }
    if (value == null || value.isEmpty) {
      options.remove(key);
    } else {
      options[key] = value;
    }
    await reload(reset: true);
  }

  Future<void> toggleListed(bool value) async {
    listed = value;
    await reload(reset: true);
  }

  void setLayout(String value) {
    if (kind == 'items') {
      itemLayout = value;
    } else {
      orderLayout = value;
    }
    notifyListeners();
  }

  Future<void> clear() async {
    options.clear();
    location = null;
    listed = false;
    keyword = '';
    await reload(reset: true);
  }

  /// Aggregate totals come from SCM page totals, never from a partial loaded page.
  Future<void> refreshOverview() async {
    final version = ++_overviewEpoch;
    var failure = false;
    await Future.wait([
      for (final entry in [('all', -1), ('sell', 1), ('buy', 0), ('barter', 2)])
        () async {
          try {
            final read = await port.read(
              entry.$2 < 0 ? 'marketOrders' : 'latest',
              side: entry.$2 < 0 ? 1 : entry.$2,
              language: language,
            );
            if (!_disposed && version == _overviewEpoch && read.total != null) {
              overview[entry.$1] = read.total!;
            }
            if (read.total == null) failure = true;
          } on Object {
            failure = true;
          }
        }(),
    ]);
    if (!_disposed && version == _overviewEpoch) {
      _overviewLoaded = true;
      overviewFailed = failure;
      notifyListeners();
    }
  }

  Future<void> reload({bool reset = false, bool more = false}) async {
    if (_disposed || more && (loading || !marketHasMore(result))) return;
    final overviewWork = !more && (!_overviewLoaded || !reset)
        ? refreshOverview()
        : Future<void>.value();
    final epoch = ++_epoch;
    final page = more ? _page + 1 : 1;
    if (reset) {
      offset = 0;
      result = null;
    }
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final next = await port.read(
        kind == 'items' ? 'marketItems' : 'marketOrders',
        keyword: keyword,
        category: category,
        page: page,
        language: language,
        options: {
          if (kind == 'items') 'sortKey': 'totalOrderCount',
          if (kind == 'orders') 'sortType': 'time',
          'sortOrder': 'desc',
          ...options,
          if (kind == 'items' && listed) 'minOrderCount': '1',
        },
      );
      if (_disposed || epoch != _epoch) return;
      result = more && result != null
          ? MarketRead({
              ...next.data,
              if (next.rows.isEmpty) ...result!.data,
              if (next.rows.isEmpty) 'pageEnd': true,
              'rows': [...result!.rows, ...next.rows],
            }, next.readAt)
          : next;
      _page = page;
    } on Object {
      if (!_disposed && epoch == _epoch) failed = true;
    } finally {
      await overviewWork;
      if (!_disposed && epoch == _epoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void reset() {
    _overviewEpoch++;
    _overviewLoaded = false;
    overviewFailed = false;
    overview.clear();
    _epoch++;
    result = null;
    options.clear();
    category = 0;
    kind = 'items';
    listed = true;
    location = null;
    keyword = '';
    offset = 0;
    loading = false;
    failed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
