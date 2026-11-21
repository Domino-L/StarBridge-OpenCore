import 'dart:async';

import 'package:flutter/widgets.dart';

import 'catalog_port.dart';

/// State belongs to this route. Pushed cross-links leave the previous route intact.
final class CatalogController extends ChangeNotifier {
  CatalogController(this.kind, this.port, {this.onViewed});
  final void Function(CatalogRow row)? onViewed;
  final CatalogKind kind;
  final CatalogPort port;
  CatalogRow filters = {}, options = {}, detail = {};
  List<CatalogRow> rows = [], sources = [];
  int page = 1, total = 0, _shownPage = 1;
  bool loading = false,
      detailLoading = false,
      sourcesLoading = false,
      sourcesKnown = false,
      _disposed = false,
      _visible = true;
  CatalogFailure? error;
  bool hasPageResult = false;
  int _hiddenEpoch = 0;
  int _pageEpoch = 0, _detailEpoch = 0, _filtersEpoch = 0, _refreshEpoch = 0;
  // Survives the narrow list/detail switch so the box always shows the active query.
  final searchText = TextEditingController();
  Timer? _search;
  String keyword = '';
  String get prefix => kind.name;
  int get pages => (total / 20).ceil().clamp(1, 10000);
  String get selectedKey =>
      detail[kind == CatalogKind.missions ? 'missionGuid' : 'id']?.toString() ??
      '';
  bool get hasDetail => detail.isNotEmpty;
  bool get hasPendingSearch => _search?.isActive == true;
  CatalogRow get query => {'keyword': keyword, ...options, 'pageNo': page};

  Future<void> start([Object? selection]) async {
    if (selection != null) {
      await select(selection);
      return;
    }
    await loadPage();
    // Both reads are demanded by the visible page; space initial calls to respect
    // the one-per-second Host budget. Never retry a rejected request.
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!_disposed && _visible) await loadFilters();
  }

  Future<void> loadPage({bool refresh = false}) async {
    if (_disposed || !_visible) return;
    final epoch = ++_pageEpoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await port.read('$prefix.page', query, refresh: refresh);
      if (_disposed || epoch != _pageEpoch) return;
      final nextRows = catalogRows(data['rows']);
      final nextTotal = data['total'];
      if (nextTotal is! int || nextTotal < 0) throw const CatalogFailure();
      rows = nextRows;
      hasPageResult = true;
      total = nextTotal;
      _shownPage = page;
    } catch (failure) {
      if (!_disposed && epoch == _pageEpoch) {
        error = _failure(failure);
        page = _shownPage;
      }
    } finally {
      if (!_disposed && epoch == _pageEpoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Returns the read's epoch when [deferLimited] is set and the read was
  /// rejected by the catalog rate limit while still current; the caller may
  /// try again. Otherwise returns null.
  Future<int?> loadFilters({
    bool refresh = false,
    bool deferLimited = false,
  }) async {
    if (_disposed || !_visible) return null;
    final epoch = ++_filtersEpoch;
    try {
      final data = await port.read('$prefix.filters', {
        if (kind == CatalogKind.blueprints)
          'categoryName': options['categoryName'] ?? '',
        if (kind == CatalogKind.blueprints && options['subcategory'] != null)
          'subcategory': options['subcategory'],
      }, refresh: refresh);
      if (!_disposed && epoch == _filtersEpoch) {
        filters = data;
        notifyListeners();
      }
    } catch (failure) {
      if (!_disposed && epoch == _filtersEpoch) {
        final value = _failure(failure);
        if (deferLimited && value.limited) return epoch;
        error = value;
        notifyListeners();
      }
    }
    return null;
  }

  void search(String value) {
    keyword = value.trim();
    _search?.cancel();
    _pageEpoch++; // a response for the old keyword cannot replace the visible query
    _search = Timer(const Duration(milliseconds: 400), () {
      page = 1;
      unawaited(loadPage());
    });
  }

  Future<void> filter(String name, Object? value) async {
    _search?.cancel();
    final scoped =
        kind == CatalogKind.blueprints &&
        (name == 'categoryName' || name == 'subcategory');
    if (scoped) {
      _filtersEpoch++; // Retire an older category's outstanding response now.
      filters = {};
      options.remove('manufacturer');
      options.remove('itemClass');
      if (name == 'categoryName') options.remove('subcategory');
      if (name == 'categoryName' && value == null) options.remove('isReward');
    }
    if (value == null) {
      options.remove(name);
    } else {
      options[name] = value;
    }
    page = 1;
    final filterEpoch = _filtersEpoch;
    await loadPage();
    if (scoped) await _loadScopedFilters(filterEpoch);
  }

  /// The page read for a new category just used this second's request, and
  /// another read (detail, refresh) may take the next one. Retry a
  /// rate-limited filter read a few times, one second apart, while the
  /// category is unchanged; the hourly budget still caps everything.
  Future<void> _loadScopedFilters(int filterEpoch) async {
    var current = filterEpoch;
    final hidden = _hiddenEpoch;
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_disposed || !_visible || hidden != _hiddenEpoch) return;
      if (current != _filtersEpoch) return;
      final limited = await loadFilters(deferLimited: attempt < 2);
      if (limited == null) return;
      current = limited;
    }
  }

  Future<void> sort(String value) async {
    options['sortField'] = value;
    options['sortOrder'] = value == 'title' ? 'asc' : 'desc';
    page = 1;
    await loadPage();
  }

  Future<void> go(int next) async {
    if (next < 1 || next > pages || loading) return;
    page = next;
    await loadPage();
  }

  Future<void> select(Object selection, {bool refresh = false}) async {
    if (_disposed || !_visible) return;
    final epoch = ++_detailEpoch;
    detailLoading = true;
    error = null;
    notifyListeners();
    try {
      final data = await port.read('$prefix.detail', {
        if (kind == CatalogKind.missions) 'guid': selection.toString(),
        if (kind == CatalogKind.blueprints) 'id': selection,
      }, refresh: refresh);
      if (_disposed || !_visible || epoch != _detailEpoch) return;
      if (selectedKey != selection.toString()) {
        sources = [];
        sourcesKnown = false;
      }
      detail = data;
      onViewed?.call(data);
      detailLoading = false;
      notifyListeners();
      if (kind == CatalogKind.blueprints) {
        sourcesLoading = true;
        notifyListeners();
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_disposed || !_visible || epoch != _detailEpoch) return;
        final data = await port.read('blueprints.missions', {
          'id': selection,
        }, refresh: refresh);
        if (!_disposed && epoch == _detailEpoch) {
          sources = catalogRows(data['rows']);
          sourcesKnown = true;
        }
      }
    } catch (failure) {
      if (!_disposed && epoch == _detailEpoch) error = _failure(failure);
    } finally {
      if (!_disposed && epoch == _detailEpoch) {
        detailLoading = false;
        sourcesLoading = false;
        notifyListeners();
      }
    }
  }

  /// A user-demanded record lookup already returned this complete detail.
  void showResolvedDetail(CatalogRow row) {
    if (_disposed || !_visible) return;
    _detailEpoch++;
    detail = row;
    onViewed?.call(row);
    error = null;
    detailLoading = sourcesLoading = sourcesKnown = false;
    sources = [];
    notifyListeners();
  }

  void closeDetail() {
    _detailEpoch++;
    detail = {};
    sources = [];
    sourcesLoading = false;
    sourcesKnown = false;
    detailLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    // A newer refresh, selection or closed detail retires this whole flow.
    final run = ++_refreshEpoch;
    final selection = kind == CatalogKind.missions
        ? detail['missionGuid']
        : detail['id'];
    // The detail epoch this flow expects; any user selection or close moves it.
    var expectedDetail = _detailEpoch;
    bool current() =>
        !_disposed &&
        _visible &&
        run == _refreshEpoch &&
        _detailEpoch == expectedDetail;
    await loadPage(refresh: true);
    if (error != null || !current()) return;
    if (selection != null) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!current() || selectedKey != selection.toString()) return;
      final reselect = select(selection, refresh: true);
      expectedDetail = _detailEpoch; // select() claims its epoch synchronously
      await reselect;
    }
    if (error != null || !current()) return;
    await Future<void>.delayed(const Duration(seconds: 1));
    if (current()) await loadFilters(refresh: true);
  }

  void setVisible(bool value) {
    _visible = value;
    if (!value) {
      _search?.cancel();
      _hiddenEpoch++; // A pending category filter retry ends when hidden.
    }
  }

  Future<void> openWebsite() async {
    try {
      await port.openWebsite(kind, detail);
    } catch (failure) {
      if (!_disposed) {
        error = _failure(failure);
        notifyListeners();
      }
    }
  }

  CatalogFailure _failure(Object? value) =>
      value is CatalogFailure ? value : const CatalogFailure();
  @override
  void dispose() {
    _disposed = true;
    _search?.cancel();
    searchText.dispose();
    super.dispose();
  }
}
