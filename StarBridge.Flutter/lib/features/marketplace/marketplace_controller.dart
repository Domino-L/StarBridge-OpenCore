import 'dart:async';

import 'package:flutter/widgets.dart';

import 'marketplace_category_recheck.dart';
import 'marketplace_best_prices.dart';
import 'marketplace_chat_controller.dart';
import 'marketplace_port.dart';
import 'marketplace_browser.dart';
import 'marketplace_quality.dart';
import 'marketplace_controller_account.dart';
import 'marketplace_controller_offers.dart';
import 'marketplace_controller_preferences.dart';
import 'marketplace_controller_watch.dart';
export 'marketplace_controller_watch.dart' show MarketWatchEntry;
import 'marketplace_details.dart' show marketRememberZones, marketMyOrders;
import 'marketplace_trades_controller.dart';

/// Page state and bounded snapshots only. SCM remains the authority for all market facts.
/// One step of the hall’s back history.
typedef MarketPlace = ({
  int mainTab,
  int? itemId,
  int itemTab,
  int? categoryId,
  String keyword,
  String relation,
  int relatedId,
});

final class MarketplaceController extends ChangeNotifier
    with
        MarketplacePreferences,
        MarketplaceOffers,
        MarketplaceAccount,
        MarketplaceWatch {
  MarketplaceController(this.port) {
    trades.addListener(notifyListeners);
  }
  @override
  final MarketplacePort port;
  Future<void> Function(BuildContext)? login;
  Future<void> Function(BuildContext)? openScm;

  /// The app-wide SCM trade chat (0.7.2 G9), for 私信对方 / 联系卖家.
  MarketplaceChatController? tradeChat;

  /// Opens another destination (e.g. /messages); set by the hall page, whose
  /// context reaches the shell's navigation actions.
  void Function(String route)? openDestination;
  late final browser = MarketplaceBrowser(port);
  @override
  late final trades = MarketplaceTradesController(port);
  int _itemOrigin = 0;

  /// Where 返回 goes (user 10-29: "返回永远是返回上一页"). Each in-hall step —
  /// opening an item, a related catalog or a search — remembers the page it
  /// left; switching the top tabs starts over. Scroll positions come back from
  /// the pages' PageStorageKeys; item tabs and catalog filters from here.
  final List<MarketPlace> _history = [];
  MarketPlace get _here => (
    mainTab: mainTab,
    itemId: itemId,
    itemTab: itemTab,
    categoryId: categoryId,
    keyword: keyword,
    relation: relation,
    relatedId: relatedId,
  );
  MarketPlace? get backTarget => _history.isEmpty ? null : _history.last;

  /// The tab an item page returns to when it has no history (opened from a tab).
  int get itemOrigin => _itemOrigin;

  void _remember() {
    final here = _here;
    if (_history.isNotEmpty && _history.last == here) return;
    _history.add(here);
    if (_history.length > 20) _history.removeAt(0);
  }

  @override
  final blocks = <String, MarketRead>{};
  @override
  final failures = <String>{};
  final loading = <String>{};
  final focusRequests = ValueNotifier(0);
  final _versions = <String, int>{};
  bool _disposed = false, _initialized = false;
  int _context = 0, side = 1, mainTab = 0, itemTab = 0;
  @override
  int? itemId;
  int? categoryId;
  String keyword = '', locale = 'cn';
  double hallOffset = 0;
  String relation = '', layout = 'cards';
  int relatedId = 0;
  bool get hasCatalog =>
      relation.isNotEmpty || categoryId != null || keyword.isNotEmpty;
  Future<void> saveView() {
    final view = <String, Object?>{
      'keyword': keyword,
      'category': categoryId,
      'relation': relation,
      'relatedId': relatedId,
      'layout': layout,
      // "All types" is not written: a build that only knows sides 0-2 fails on
      // it when reading this file back. After a restart the default side shows.
      'side': side == allSides ? 1 : side,
      'itemLayout': browser.itemLayout,
      'orderLayout': browser.orderLayout,
    };
    return savePreference('view', view);
  }

  @override
  @protected
  void restoreView(Map<Object?, Object?> raw) {
    keyword = raw['keyword'] as String? ?? '';
    categoryId = marketNumber(raw['category'])?.toInt();
    relation = raw['relation'] as String? ?? '';
    relatedId = marketNumber(raw['relatedId'])?.toInt() ?? 0;
    layout = raw['layout'] == 'rows' ? 'rows' : 'cards';
    final restoredSide = marketNumber(raw['side'])?.toInt() ?? 1;
    browser.itemLayout = raw['itemLayout'] == 'rows' ? 'rows' : 'cards';
    browser.orderLayout = raw['orderLayout'] == 'rows' ? 'rows' : 'cards';
    // The first screen already asked for the default side; only a
    // different remembered side needs its own read.
    if (restoredSide != side) {
      side = restoredSide;
      blocks.remove('latest');
      unawaited(loadLatest());
    }
    if (hasCatalog) unawaited(refreshCatalog());
  }

  Future<void> setLayout(String value) async {
    if (value != 'cards' && value != 'rows') return;
    layout = value;
    notifyListeners();
    await saveView();
  }

  Future<void> related(String kind, int id) async {
    _remember();
    // The chip names this item ("兼容：<name>"), so keep its row at hand.
    if (itemId == id && blocks['item'] != null) {
      blocks['recent:$id'] ??= blocks['item']!;
    }
    relation = kind;
    relatedId = id;
    keyword = '';
    categoryId = null;
    itemId = null;
    mainTab = 0;
    blocks.remove('catalog');
    notifyListeners();
    await Future.wait([refreshCatalog(), saveView()]);
  }

  Future<void> refreshCatalog() async {
    await Future.wait([
      load(
        'catalog',
        relation.isEmpty ? 'search' : relation,
        id: relatedId,
        query: keyword,
        category: categoryId ?? 0,
      ),
      // A catalog restored from the saved view has not read its item yet.
      if (relation.isNotEmpty &&
          relatedId > 0 &&
          blocks['recent:$relatedId'] == null &&
          !loading.contains('recent:$relatedId'))
        load('recent:$relatedId', 'item', id: relatedId),
    ]);
  }

  Future<void> refreshHall() => Future.wait([
    load('categories', 'categories'),
    load('trending', 'trending'),
    loadLatest(),
    loadFavorites(),
    load('reputation', 'reputation'),
    load('categoryListings', 'categoryListings'),
    refreshMyOrders(),
    loadTradeProfile(),
  ]);
  Future<void> refreshItem() async {
    final id = itemId;
    if (id == null) return;
    await Future.wait([
      load('item', 'item', id: id),
      loadOffers(id),
      load('trend', 'trend', id: id),
      load('acquisition', 'acquisition', id: id),
    ]);
  }

  int? get activeCategory => categoryId;
  bool get hasItem => itemId != null;
  bool get itemLoading => loading.contains('item');
  @override
  int get contextRevision => _context;
  @override
  @protected
  bool get isDisposed => _disposed;
  Future<void> changeLocale(String value) async {
    if (locale == value) return;
    locale = value;
    browser.language = value == 'en' ? 'EN' : 'CN';
    if (!_initialized) return;
    await Future.wait([
      loadLatest(),
      if (browser.result != null) browser.reload(),
      load('trending', 'trending'),
      if (itemId != null) load('sell', 'offers', id: itemId!, side: 1),
      if (itemId != null) load('buy', 'offers', id: itemId!, side: 0),
    ]);
  }

  Future<void> focusSearch() async {
    _focusPending = true;
    focusRequests.value++;
  }

  /// A search-focus request is used once: a page built later (an ordinary
  /// visit) must not re-open the search for an old shortcut press.
  bool _focusPending = false;
  bool takeFocusRequest() {
    final pending = _focusPending;
    _focusPending = false;
    return pending;
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    unawaited(trades.start());
    unawaited(refreshMyOrders());
    unawaited(loadTradeProfile());
    // The Host admits four public reads at a time, so what the first screen
    // shows goes first. The per-category counts fan out into ten reads and
    // only decorate the tiles; favourites (three reads each) sit below the
    // fold; recent items only feed the search panel. Each waits its turn.
    final firstScreen = [
      load('categories', 'categories'),
      loadLatest(),
      load('trending', 'trending'),
      readPreferences(),
    ];
    await Future.wait([
      ...firstScreen,
      Future.wait(firstScreen)
          .then((_) {
            if (!_firstScreenDone.isCompleted) _firstScreenDone.complete();
            return Future.wait([
              load('categoryListings', 'categoryListings'),
              load('locations', 'locations'),
              load('reputation', 'reputation'),
              load('timezones', 'timezones'),
              loadFavorites(),
            ]);
          })
          .then((_) => loadRecentItems()),
    ]);
  }

  /// Completes once the hall's first-screen reads have answered.
  final _firstScreenDone = Completer<void>();

  /// Details for the search panel's 最近浏览 (at most eight items).
  Future<void> loadRecentItems() => Future.wait(
    recentItems.take(8).map((id) => load('recent:$id', 'item', id: id)),
  );

  /// Best live prices for the cards on screen (see MarketBestPrices).
  late final _bestPrices = MarketBestPrices(
    read: (keyword) => port.read('bestPrices', keyword: keyword),
    isCurrent: (revision) => !_disposed && revision == _context,
    changed: notifyListeners,
  );
  @override
  num? bestPrice(int itemId, int side) => _bestPrices.price(itemId, side);

  /// Live tier pricing per item (hover box, item page, publish), on demand.
  late final qualityTiers = MarketQualityTiersStore(
    read: (itemId) => port.read('qualityTiers', keyword: '$itemId'),
    changed: () {
      if (!_disposed) notifyListeners();
    },
  );
  bool hasBestPrice(int itemId, int side) => _bestPrices.has(itemId, side);

  /// The price tags only decorate cards: they wait for the first screen so
  /// they never take a read slot from categories, latest or trending.
  Future<void> ensureBestPrices(Iterable<(int, int)> wanted) async {
    if (_initialized && !_firstScreenDone.isCompleted) {
      await _firstScreenDone.future;
    }
    if (_disposed) return;
    return _bestPrices.ensure(wanted, _context);
  }

  @override
  Future<void> load(
    String key,
    String operation, {
    int id = 0,
    String query = '',
    int category = 0,
    int side = 1,
    int page = 1,
    bool append = false,
    Map<String, String> options = const {},
  }) async {
    if (_disposed || append && loading.contains(key)) return;
    if (!append) {
      _rereads[key] = () => load(
        key,
        operation,
        id: id,
        query: query,
        category: category,
        side: side,
        page: page,
        options: options,
      );
    }
    final context = _context, version = (_versions[key] ?? 0) + 1;
    _versions[key] = version;
    loading.add(key);
    failures.remove(key);
    notifyListeners();
    try {
      var result = await port.read(
        operation,
        language: locale == 'en' ? 'EN' : 'CN',
        id: id,
        keyword: query,
        category: category,
        side: side,
        page: page,
        options: options,
      );
      if (_disposed || context != _context || _versions[key] != version) return;
      result = MarketRead({...result.data, 'loadedPage': page}, result.readAt);
      final previous = blocks[key];
      if (append && previous != null) {
        result = MarketRead({
          ...result.data,
          if (result.rows.isEmpty) 'pageEnd': true,
          'rows': [...previous.rows, ...result.rows],
        }, result.readAt);
      }
      blocks[key] = result;
      if (!append && (key == 'trending' || key == 'latest')) {
        _categoryRecheck.track(
          key,
          result,
          () => port.read(
            operation,
            language: locale == 'en' ? 'EN' : 'CN',
            side: side,
            page: page,
          ),
        );
      }
      _rereads.remove(key);
      if (failures.isEmpty) _rereadRound = 0;
      refiltering.remove(key);
      _refilterUndo.remove(key);
      if (key == 'categories') browser.categories = result.rows;
      if (key == 'timezones') marketRememberZones(result.rows);
    } on Object {
      if (!_disposed && context == _context && _versions[key] == version) {
        failures.add(key);
        // The previous filter's rows must not pass for the new filter's. Its
        // undo is gone too, so a reread could bring back a cancelled filter.
        if (refiltering.remove(key)) {
          blocks.remove(key);
          _rereads.remove(key);
        }
        // A failed next page keeps its rows; rereading page one would drop them.
        if (append) _rereads.remove(key);
        _scheduleReread();
        _refilterUndo.remove(key);
      }
    } finally {
      if (!_disposed && context == _context && _versions[key] == version) {
        loading.remove(key);
        notifyListeners();
      }
    }
  }

  // After a Host restart the first burst can time out at the back of the
  // queue, and nothing else asks again while the page stays open.
  static const _rereadDelays = [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];
  final _rereads = <String, Future<void> Function()>{};
  Timer? _rereadTimer;
  int _rereadRound = 0;
  bool _rereading = false;
  void _scheduleReread() {
    if (_rereading || _rereadTimer != null) return;
    if (_rereadRound >= _rereadDelays.length) return;
    _rereadTimer = Timer(_rereadDelays[_rereadRound++], () {
      _rereadTimer = null;
      unawaited(_rereadFailed());
    });
  }

  Future<void> _rereadFailed() async {
    final context = _context;
    _rereading = true;
    final due = failures.where(_rereads.containsKey).toList();
    // Four at a time, what the Host admits, so this does not repeat the burst.
    for (var i = 0; i < due.length; i += 4) {
      if (_disposed || context != _context) return;
      await Future.wait([
        for (final key in due.skip(i).take(4))
          // A key can leave while the batch before it runs.
          if (failures.contains(key) && _rereads.containsKey(key))
            _rereads[key]!(),
      ]);
    }
    if (_disposed || context != _context) return;
    _rereading = false;
    if (failures.any(_rereads.containsKey)) _scheduleReread();
  }

  late final _categoryRecheck = MarketCategoryRecheck(
    current: (key) => blocks[key],
    store: (key, read) {
      blocks[key] = read;
      notifyListeners();
    },
  );

  Future<void> loadLatest() => load('latest', 'latest', side: side);

  /// Keys whose rows still belong to the previous filter while the new
  /// filter's rows load; the page dims them instead of blanking.
  @override
  final refiltering = <String>{};
  final _refilterUndo = <String, VoidCallback>{};

  /// Keeps [keys]' current rows on screen until the new filter's rows arrive;
  /// [undo] puts the previous filter back if the wait is cancelled.
  @override
  void refilter(Iterable<String> keys, VoidCallback undo) {
    for (final key in keys) {
      failures.remove(key);
      if (blocks[key] == null) continue;
      refiltering.add(key);
      _refilterUndo[key] = undo;
    }
  }

  /// Stops waiting: the previous filter and its rows come back as they were.
  void cancelRefilter(String key) {
    final undo = _refilterUndo[key];
    if (undo == null) return;
    final keys = [
      for (final entry in _refilterUndo.entries)
        if (identical(entry.value, undo)) entry.key,
    ];
    for (final k in keys) {
      _refilterUndo.remove(k);
      refiltering.remove(k);
      _rereads.remove(k);
      loading.remove(k);
      _versions[k] = (_versions[k] ?? 0) + 1;
    }
    undo();
    notifyListeners();
    unawaited(saveView());
  }

  /// No type filter on the hall's latest listings (sell, buy and barter together).
  static const allSides = 3;

  /// User 10-29: activating the selected filter again clears it back to all
  /// types; none highlighted means all.
  Future<void> toggleSide(int value) =>
      setSide(side == value ? allSides : value);

  Future<void> setSide(int value) async {
    final before = side;
    if (side != value) refilter(const ['latest'], () => side = before);
    side = value;
    await Future.wait([loadLatest(), saveView()]);
  }

  Future<List<MarketRow>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final generation = port.generation, context = _context;
    final result = await port.read('search', keyword: query.trim());
    if (_disposed || generation != port.generation || context != _context) {
      return const [];
    }
    return result.rows;
  }

  Future<void> browse({String query = '', int? category}) async {
    // Refining filters inside the catalog replaces the step instead of piling up history.
    final inCatalog = itemId == null &&
        mainTab == 0 &&
        (relation.isNotEmpty || keyword.isNotEmpty || categoryId != null);
    if (!inCatalog) _remember();
    final (beforeRelation, beforeId, beforeKeyword, beforeCategory) =
        (relation, relatedId, keyword, categoryId);
    if (inCatalog) {
      refilter(const ['catalog'], () {
        relation = beforeRelation;
        relatedId = beforeId;
        keyword = beforeKeyword;
        categoryId = beforeCategory;
      });
    } else {
      blocks.remove('catalog');
    }
    relation = '';
    relatedId = 0;
    keyword = query;
    categoryId = category;
    itemId = null;
    mainTab = 0;
    notifyListeners();
    await Future.wait([refreshCatalog(), saveView()]);
  }

  Future<void> marketCategory(int id) async {
    browser.categories = blocks['categories']?.rows ?? [];
    mainTab = 1;
    itemId = null;
    notifyListeners();
    await browser.choose(category: id);
  }

  Future<void> moreCatalog() {
    final count = blocks['catalog']?.rows.length ?? 0;
    return load(
      'catalog',
      relation.isEmpty ? 'search' : relation,
      id: relatedId,
      query: keyword,
      category: categoryId ?? 0,
      page:
          (marketNumber(blocks['catalog']?.data['loadedPage'])?.toInt() ??
              count ~/ 20) +
          1,
      append: true,
    );
  }

  Future<void> openItem(
    int id, {
    String? search,
    int tab = 0,
    bool record = true,
  }) async {
    if (_disposed || id <= 0) return;
    if (itemId == id) return refreshItem();
    if (record) _remember();
    for (final key in [
      'item',
      'sell',
      'buy',
      'trend',
      'acquisition',
      'blueprints',
    ]) {
      _versions[key] = (_versions[key] ?? 0) + 1;
      blocks.remove(key);
      failures.remove(key);
      loading.remove(key);
      refiltering.remove(key);
      _refilterUndo.remove(key);
    }
    if (itemId == null) _itemOrigin = mainTab;
    itemId = id;
    itemTab = tab;
    mainTab = 0;
    offerFilters.clear();
    offerSortField = 'price';
    offerSortDesc = true;
    offerLocation = null;
    notifyListeners();
    unawaited(remember(id, search));
    await Future.wait([
      load('item', 'item', id: id),
      loadOffers(id),
      load('trend', 'trend', id: id),
      load('acquisition', 'acquisition', id: id),
    ]);
    if (itemId == id && blocks['item'] != null) {
      blocks['recent:$id'] = blocks['item']!;
    }
  }

  void back() {
    if (_history.isNotEmpty) return _restore(_history.removeLast());
    if (itemId == null) return hall();
    itemId = null;
    mainTab = _itemOrigin;
    notifyListeners();
  }

  void _restore(MarketPlace place) {
    mainTab = place.mainTab;
    categoryId = place.categoryId;
    keyword = place.keyword;
    relation = place.relation;
    relatedId = place.relatedId;
    if (place.itemId case final int id) {
      if (itemId == id) {
        itemTab = place.itemTab;
        notifyListeners();
      } else {
        unawaited(openItem(id, tab: place.itemTab, record: false));
      }
    } else {
      itemId = null;
      notifyListeners();
      final catalog =
          relation.isNotEmpty || keyword.isNotEmpty || categoryId != null;
      if (mainTab == 0 && catalog && blocks['catalog'] == null) {
        unawaited(refreshCatalog());
      }
    }
    unawaited(saveView());
  }

  void hall() {
    _history.clear();
    itemId = null;
    categoryId = null;
    keyword = '';
    relation = '';
    relatedId = 0;
    mainTab = 0;
    unawaited(saveView());
    notifyListeners();
  }

  @override
  void tab(int value) {
    _history.clear();
    itemId = null;
    mainTab = value;
    if (value == 1) {
      unawaited(browser.initialize(blocks['categories']?.rows ?? []));
    }
    notifyListeners();
  }

  void selectItemTab(int value) {
    itemTab = value;
    notifyListeners();
  }

  @override
  Future<void> loadFavorites() async {
    final keys = favorites
        .take(12)
        .expand((id) => ['watch:$id', 'watch-price:$id', 'watch-buy:$id'])
        .toSet();
    blocks.removeWhere(
      (key, _) => key.startsWith('watch') && !keys.contains(key),
    );
    await Future.wait(
      favorites
          .take(12)
          .expand(
            (id) => [
              load('watch:$id', 'item', id: id),
              load('watch-price:$id', 'offers', id: id),
              load('watch-buy:$id', 'offers', id: id, side: 0),
            ],
          ),
    );
  }

  void contextChanged() {
    _history.clear();
    marketMyOrders.clear();
    tradeProfile = null;
    _bestPrices.clear();
    qualityTiers.clear();
    myListings = const [];
    myListingsLoaded = false;
    trades.reset();
    browser.reset();
    final active = _initialized;
    _context++;
    _initialized = false;
    _rereadTimer?.cancel();
    _rereadTimer = null;
    _rereadRound = 0;
    _rereading = false;
    _rereads.clear();
    _categoryRecheck.cancel();
    resetPreferences();
    relation = '';
    relatedId = 0;
    layout = 'cards';
    side = 1;
    _versions.clear();
    blocks.clear();
    failures.clear();
    loading.clear();
    refiltering.clear();
    _refilterUndo.clear();
    itemId = null;
    categoryId = null;
    keyword = '';
    mainTab = 0;
    hallOffset = 0;
    notifyListeners();
    if (active) unawaited(initialize());
  }

  @override
  void dispose() {
    _disposed = true;
    _context++;
    _rereadTimer?.cancel();
    _rereadTimer = null;
    _categoryRecheck.cancel();
    focusRequests.dispose();
    browser.dispose();
    trades.dispose();
    port.dispose();
    super.dispose();
  }
}
