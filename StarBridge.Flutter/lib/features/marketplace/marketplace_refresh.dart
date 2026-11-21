import 'dart:async';

import 'package:flutter/material.dart';

import 'marketplace_banner.dart';
import 'marketplace_controller.dart';

/// Only the mounted sub-page owns this target; its reads never refresh the hall.
class MarketRefreshTarget extends ChangeNotifier {
  Object? owner;
  int? tab;
  Future<void> Function()? refresh;
  bool Function()? busy;
  bool _disposed = false, _queued = false;

  /// An explicit hall refresh in flight, so 刷新 stays off until every hall
  /// read (my listings, trade profile, trades) is back (CX-HALL-FIX3-REVIEW P2).
  bool hallRefreshing = false;

  void changed() {
    if (_disposed || _queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (!_disposed) notifyListeners();
    });
  }

  void detach(Object value) {
    if (!identical(owner, value)) return;
    owner = null;
    tab = null;
    refresh = null;
    busy = null;
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class MarketRefreshBinding extends StatefulWidget {
  const MarketRefreshBinding({required this.market, required this.tab,
    required this.source, required this.refresh, required this.busy,
    required this.child, super.key});
  final MarketplaceController market;
  final int tab;
  final Listenable source;
  final Future<void> Function() refresh;
  final bool Function() busy;
  final Widget child;
  @override
  State<MarketRefreshBinding> createState() => _BindingState();
}

class _BindingState extends State<MarketRefreshBinding> {
  void _changed() => widget.market.pageRefresh.changed();
  void _bind() {
    widget.market.pageRefresh
      ..owner = this
      ..tab = widget.tab
      ..refresh = widget.refresh
      ..busy = widget.busy
      ..changed();
  }
  @override
  void initState() {
    super.initState();
    widget.source.addListener(_changed);
    _bind();
  }
  @override
  void didUpdateWidget(MarketRefreshBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.source.removeListener(_changed);
    if (oldWidget.market != widget.market) oldWidget.market.pageRefresh.detach(this);
    widget.source.addListener(_changed);
    _bind();
  }
  @override
  void dispose() {
    widget.source.removeListener(_changed);
    widget.market.pageRefresh.detach(this);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => widget.child;
}

extension MarketplaceRefresh on MarketplaceController {
  bool get currentPageLoading {
    if (hasItem) {
      return loading.any((key) => const {
        'item', 'sell', 'buy', 'sell-checklist', 'buy-checklist', 'trend',
        'acquisition',
      }.contains(key));
    }
    if (mainTab == 1) return browser.loading;
    if (mainTab == 5) {
      return favorites.take(watchLimit).any((id) =>
          loading.contains('watch:$id') ||
          loading.contains('watch-price:$id') ||
          loading.contains('watch-buy:$id'));
    }
    if (pageRefresh.tab == mainTab) return pageRefresh.busy?.call() ?? false;
    if (mainTab == 3) return trades.loading;
    if (mainTab != 0) return false;
    if (hasCatalog) return loading.contains('catalog');
    if (pageRefresh.hallRefreshing) return true;
    return loading.any((key) => const {
      'categories', 'trending', 'latest', 'reputation', 'categoryListings', 'timezones',
    }.contains(key));
  }

  Future<void> refreshCurrentPage() async {
    fullOrders.clear();
    if (hasItem) return refreshItem();
    if (mainTab == 1) return browser.reload();
    if (mainTab == 5) return loadWatch();
    if (pageRefresh.tab == mainTab) {
      await pageRefresh.refresh?.call();
      return;
    }
    if (mainTab == 3) return trades.refresh();
    if (mainTab != 0) return;
    if (hasCatalog) return refreshCatalog();
    if (pageRefresh.hallRefreshing) return;
    pageRefresh
      ..hallRefreshing = true
      ..changed();
    try {
      await refreshHall();
    } finally {
      pageRefresh
        ..hallRefreshing = false
        ..changed();
    }
  }

  Future<void> allHallOrders() async {
    browser.reset();
    browser.kind = 'orders';
    if (side == 2) {
      browser.options['displayType'] = '3';
    } else if (side == 0 || side == 1) {
      browser.options['creatorType'] = '$side';
    }
    // Start the intended read before tab() can initialize an unfiltered query.
    final work = browser.reload(reset: true);
    tab(1);
    await work;
  }
}

class MarketCurrentPageHead extends StatelessWidget {
  const MarketCurrentPageHead(this.market, {required this.search, super.key});
  final MarketplaceController market;
  final Widget search;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([market, market.browser, market.pageRefresh]),
    builder: (context, _) => MarketHallHead(market, search: search,
      onRefresh: market.currentPageLoading ? null : market.refreshCurrentPage),
  );
}
