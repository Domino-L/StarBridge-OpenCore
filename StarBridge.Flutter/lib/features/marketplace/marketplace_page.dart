import '../../shared/guide/guide_scope.dart';
import '../../app/routing/open_destination_intent.dart';
import 'marketplace_catalog_view.dart';
import 'marketplace_search.dart';
import 'marketplace_trades_page.dart';
import 'marketplace_my_activity.dart';
import 'marketplace_banner.dart';
import 'marketplace_hall_drawers.dart';
import 'marketplace_hall_reads.dart';
import 'marketplace_hall_mine.dart';
import 'marketplace_hover.dart';
import 'marketplace_loading_content.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_row.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_contracts_page.dart';
import 'marketplace_warehouse_page.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_item_page.dart';
import 'marketplace_market_page.dart';
import 'marketplace_port.dart';
import 'marketplace_price_format.dart' show MarketPriceFormatScope;
import '../../design_system/styles/marketplace_palette.dart';
import 'marketplace_hall_watch.dart';
import 'marketplace_watch_page.dart';
import 'marketplace_widgets.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage(this.controller, {super.key});
  final MarketplaceController controller;
  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  // Where the hall is; a change of page dismisses the current message.
  Object? _location;
  void _dismissOnPageChange() {
    final c = widget.controller;
    final location = (
      c.mainTab,
      c.itemId,
      c.relation,
      c.relatedId,
      c.keyword,
      c.categoryId,
    );
    if (_location != null && _location != location) {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
    _location = location;
  }
  MarketplaceController get c => widget.controller;
  final _search = TextEditingController(), _focus = FocusNode();
  late final ScrollController _scroll = _HallScrollController(
    () => c.hallOffset,
  );
  bool _searchFailed = false;
  late int _contextRevision = c.contextRevision;
  @override
  void initState() {
    super.initState();
    c.trades.setVisible(true);
    c.focusRequests.addListener(_focusSearch);
    c.addListener(_contextChanged);
    _scroll.addListener(_rememberScroll);
    if (c.takeFocusRequest()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNow());
    }
  }

  void _contextChanged() {
    _dismissOnPageChange();
    if (_contextRevision == c.contextRevision) {
      return;
    }
    _contextRevision = c.contextRevision;
    _search.clear();
    _searchFailed = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = marketLocale(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(c.changeLocale(locale));
      unawaited(c.initialize());
    });
  }

  void _rememberScroll() {
    c.hallOffset = _scroll.offset;
  }

  void _focusSearch() {
    if (c.takeFocusRequest()) _focusNow();
  }

  void _focusNow() {
    // A request alone does not schedule a frame; ask for one so the focus
    // lands even when nothing else on the page is changing.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        _search.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _search.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    c.trades.setVisible(false);
    c.focusRequests.removeListener(_focusSearch);
    c.removeListener(_contextChanged);
    _scroll.dispose();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _heading(
    String title, {
    DateTime? readAt,
    VoidCallback? refresh,
    String? action,
    VoidCallback? onAction,
    Widget? extra,
  }) {
    final categories = title == marketText(context, 'categories');
    final onSale = categories
        ? (c.blocks['categoryListings']?.rows ?? const <MarketRow>[])
              .map((r) => marketNumber(r['count']) ?? 0)
              .fold<num>(0, (a, b) => a + b)
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: MarketSectionHeading(
        title,
        meta: Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (onSale != null && onSale > 0)
              Text(marketTextN(context, 'onSaleTotal', marketMoney(onSale))),
            if (readAt != null) MarketStamp(readAt),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?extra,
            if (action != null)
              marketButtonAction(
                key: ValueKey(('market-section-action', action)),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontSize: 12.5),
                  ),
                  child: Text(marketText(context, action)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sideSegments() {
    final t = context.tokens;
    return Wrap(
      runSpacing: 4,
      children: [
        for (final entry in [(1, 'sell'), (0, 'buy'), (2, 'barter')])
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Material(
              color: c.side == entry.$1
                  ? t.surfaces.selected.fill
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: c.side == entry.$1
                      ? t.colors.accent.withValues(alpha: .7)
                      : t.surfaces.panel.border,
                ),
              ),
              child: StarBridgeActionRow(
                controlKey: ValueKey(('market-hall-side', entry.$1)),
                inheritContentStyle: true,
                semanticSelected: c.side == entry.$1,
                baseRadius: 6,
                onActivate: (_, _) => c.toggleSide(entry.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Text(
                    marketText(context, entry.$2),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: c.side == entry.$1
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: c.side == entry.$1
                          ? t.colors.accent
                          : t.colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _allOrders() {
    c.tab(1);
    unawaited(c.browser.choose(kind: 'orders'));
  }

  Widget _block(
    String key,
    Widget Function(MarketRead) ready,
    VoidCallback retry,
  ) {
    final read = c.blocks[key];
    if (c.loading.contains(key) && read == null) {
      return MarketSkeleton(kind: key);
    }
    if (c.failures.contains(key) && read == null) {
      return MarketNotice(marketText(context, 'unavailable'), retry: retry);
    }
    if (read == null) return const SizedBox.shrink();
    if (!c.failures.contains(key)) {
      return MarketRefilter(
        active: c.refiltering.contains(key),
        onCancel: () => c.cancelRefilter(key),
        child: ready(read),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarketStale(read.readAt, retry: retry),
        if (key == 'catalog') Expanded(child: ready(read)) else ready(read),
      ],
    );
  }

  /// Submitted at least once this visit (completes "逛逛交易大厅").
  bool _searched = false;

  Widget _searchBox() => MarketplaceSearch(
    c,
    _search,
    _focus,
    onSearched: () {
      if (!_searched && mounted) setState(() => _searched = true);
    },
  );
  Widget _grid(List<MarketRow> rows, {bool trending = false}) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = math.max(
        1,
        (constraints.maxWidth / (trending ? 196 : 236)).floor(),
      );
      final visible = rows
          .take(
            trending ? columns : marketCompleteRowCount(rows.length, columns),
          )
          .toList();
      // Listing cards: the side whose best price decides 最低价 / 最高收购.
      int? sideOf(MarketRow r) =>
          !r.containsKey('seller') || r['displayType'] == 3
          ? null
          : r['creatorType'] == 0
          ? 0
          : 1;
      if (!trending) {
        final wanted = [
          for (final r in visible)
            if (marketItemId(r) != null && sideOf(r) != null)
              (marketItemId(r)!, sideOf(r)!),
        ];
        if (wanted.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(c.ensureBestPrices(wanted));
          });
        }
      }
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: visible.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          // Quality items add the any-quality and top-tier lines.
          mainAxisExtent: trending
              ? (visible.any((r) => r['qualityAny'] is Map) ? 252 : 228)
              : 304,
        ),
        itemBuilder: (_, i) {
          final row = visible[i];
          final id = marketItemId(row), side = sideOf(row);
          return MarketCard(
            row,
            trending: trending,
            watched: c.isWatched(row),
            location: row.containsKey('seller') ? c.locationLabel(row) : null,
            best: id == null || side == null ? null : c.bestPrice(id, side),
            open: id == null ? null : () => c.openItem(id),
            drawer: (drawer) => trending
                ? marketTrendingDrawer(drawer, context, c, row)
                : marketListingDrawer(
                    drawer,
                    context,
                    c,
                    row,
                    best: id == null || side == null
                        ? null
                        : c.bestPrice(id, side),
                    location: c.locationLabel(row),
                  ),
          );
        },
      );
    },
  );

  /// Always-present strip of the user's own listings (live first, hidden dimmed).
  Widget _myListings() => MarketMyListingsStrip(c);

  /// Active listings on SCM for a top-level category (children included).
  Widget _onSale(int category) {
    final count = c.categoryListingCount(category);
    return Text(
      count == null ? ' ' : marketTextN(context, 'onSale', marketMoney(count)),
      maxLines: 1,
      style: TextStyle(
        fontSize: 11,
        color: context.tokens.colors.textSecondary,
      ),
    );
  }

  Widget _hall() => CustomScrollView(
    key: const PageStorageKey('marketplace-hall'),
    controller: _scroll,
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 28),
        sliver: SliverList.list(
          children: [
            if (c.trades.todo.isNotEmpty) TradeTodo(c),
            if (c.myListingsSupported) ...[
              _heading(
                marketText(context, 'myListings'),
                refresh: c.refreshMyOrders,
                action: 'manageListings',
                onAction: c.openMyListings,
              ),
              _myListings(),
            ],
            // 我的关注 sits under 我的挂单 (G3, 0.7.2; preview watch-2).
            if (c.favorites.isNotEmpty) ...[
              _heading(
                marketText(context, 'favorites'),
                refresh: c.loadFavorites,
                extra: Text(
                  [
                    if (c.watchChanged > 0)
                      marketTextN(context, 'watchChangedN', c.watchChanged),
                    marketText(context, 'local'),
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: c.watchChanged > 0
                        ? MarketplacePalette.gold
                        : context.tokens.colors.textSecondary,
                  ),
                ),
                action: 'watchMore',
                onAction: () => c.tab(5),
              ),
              MarketHallWatch(c),
            ],
            _heading(
              marketText(context, 'categories'),
              readAt: c.blocks['categories']?.readAt,
              refresh: () => c.load('categories', 'categories'),
              action: 'enterMarket',
              onAction: () => c.tab(1),
            ),
            _block('categories', (read) {
              final roots =
                  read.rows
                      .where(
                        (row) =>
                            row['parentId'] == 0 || row['parentId'] == null,
                      )
                      .toList()
                    ..sort(
                      (a, b) => ((a['sort'] as int?) ?? 0).compareTo(
                        (b['sort'] as int?) ?? 0,
                      ),
                    );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: roots.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.maxWidth >= 850 ? 9 : 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        mainAxisExtent: constraints.maxWidth >= 850 ? 118 : 66,
                      ),
                      itemBuilder: (_, i) => MarketHoverCard(
                        radius: 9,
                        minDrawerWidth: 220,
                        // Right-hand tiles open leftward so the drawer stays
                        // inside the window.
                        alignEnd:
                            i % (constraints.maxWidth >= 850 ? 9 : 3) >=
                            (constraints.maxWidth >= 850 ? 7 : 2),
                        drawerKey: const ValueKey('market-drawer'),
                        drawer: (drawer) => marketCategoryDrawer(
                          drawer,
                          c,
                          roots[i]['id'] as int,
                        ),
                        child: Material(
                          color: context.tokens.surfaces.panel.fill,
                          borderRadius: BorderRadius.circular(9),
                          clipBehavior: Clip.antiAlias,
                          child: StarBridgeActionRow(
                            inheritContentStyle: true,
                            hoverFace: false,
                            baseRadius: 9,
                            onActivate: (_, _) =>
                                c.marketCategory(roots[i]['id'] as int),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: constraints.maxWidth >= 850
                                  ? Column(
                                      children: [
                                        Expanded(
                                          child: MarketArt(
                                            (roots[i]['picUrl'] ??
                                                    roots[i]['icon'])
                                                as String?,
                                            category: roots[i]['id'] as int,
                                            categoryIcon: true,
                                            tint: [
                                              context.tokens.domainColors.ship,
                                              context.tokens.domainColors.recon,
                                              context
                                                  .tokens
                                                  .domainColors
                                                  .airCombat,
                                              context
                                                  .tokens
                                                  .domainColors
                                                  .logistics,
                                              context
                                                  .tokens
                                                  .domainColors
                                                  .industry,
                                              context
                                                  .tokens
                                                  .domainColors
                                                  .command,
                                              context
                                                  .tokens
                                                  .domainColors
                                                  .medical,
                                            ][i % 7].foreground,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          marketName(
                                            roots[i],
                                            marketLocale(context),
                                            field: 'name',
                                          ),
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        _onSale(roots[i]['id'] as int),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        SizedBox(
                                          width: 46,
                                          height: 46,
                                          child: MarketArt(
                                            (roots[i]['picUrl'] ??
                                                    roots[i]['icon'])
                                                as String?,
                                            category: roots[i]['id'] as int,
                                            categoryIcon: true,
                                            tint: [
                                              context.tokens.domainColors.ship,
                                              context.tokens.domainColors.recon,
                                              context
                                                  .tokens
                                                  .domainColors
                                                  .airCombat,
                                              context
                                                  .tokens
                                                  .domainColors
                                                  .logistics,
                                              context
                                                  .tokens
                                                  .domainColors
                                                  .industry,
                                              context
                                                  .tokens
                                                  .domainColors
                                                  .command,
                                              context
                                                  .tokens
                                                  .domainColors
                                                  .medical,
                                            ][i % 7].foreground,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                marketName(
                                                  roots[i],
                                                  marketLocale(context),
                                                  field: 'name',
                                                ),
                                              ),
                                              _onSale(roots[i]['id'] as int),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }, () => c.load('categories', 'categories')),
            if (c.blocks['trending']?.rows.isNotEmpty != false ||
                c.failures.contains('trending')) ...[
              _heading(
                marketText(context, 'trending'),
                readAt: c.blocks['trending']?.readAt,
                refresh: () => c.load('trending', 'trending'),
                action: 'moreLink',
                onAction: () => c.tab(1),
              ),
              _block(
                'trending',
                (read) => _grid(read.rows, trending: true),
                () => c.load('trending', 'trending'),
              ),
            ],
            _heading(
              marketText(context, 'latest'),
              readAt: c.blocks['latest']?.readAt,
              refresh: c.loadLatest,
              extra: _sideSegments(),
              action: 'allOrders',
              onAction: _allOrders,
            ),
            _block(
              'latest',
              (read) => read.rows.isEmpty
                  ? MarketNotice(marketText(context, 'empty'))
                  : _grid(read.rows),
              c.loadLatest,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: marketTextAction(
                key: const Key('market-hall-top'),
                onPressed: () {
                  _scroll.jumpTo(
                    0,
                  ); // Keyboard and reduced-motion behavior stay immediate.
                },
                child: Text(marketText(context, 'top')),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      // 私信对方 / 联系卖家 leave the hall from dialogs above the shell; this
      // page context reaches the shell's navigation actions.
      c.openDestination = (route) =>
          Actions.maybeInvoke(context, OpenDestinationIntent(route));
      return MarketPriceFormatScope(
        format: c.priceFormat,
        child: MarketplaceLoadingContent(
          controller: c,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1, -1),
                radius: 1,
                colors: [
                  context.tokens.colors.accent.withValues(alpha: .09),
                  Colors.transparent,
                ],
                stops: const [0, .65],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Full-bleed head: flush with the title bar and side navigation.
                MarketHallHead(
                  c,
                  search: _searchBox(),
                  onRefresh: c.loading.isNotEmpty
                      ? null
                      : c.hasItem
                      ? c.refreshItem
                      : c.mainTab == 1
                      ? c.browser.reload
                      : c.mainTab == 3
                      ? c.trades.refresh
                      : c.refreshHall,
                ),
                Expanded(
                  child: GuideSignal(
                    // Opening an item or submitting a search once completes
                    // "逛逛交易大厅"; typing alone does not.
                    id: 'market',
                    when: c.hasItem || _searched,
                    child: GuideAnchor(
                      id: 'market.offers',
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                        child: Column(
                          children: [
                            if (_searchFailed)
                              MarketNotice(
                                marketText(context, 'unavailable'),
                                retry: () => c.browse(query: _search.text),
                              ),
                            if (c.preferencesFailed)
                              MarketNotice(
                                marketText(context, 'preferencesFailed'),
                                retry: c.readPreferences,
                              ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: c.mainTab == 1 && !c.hasItem
                                  ? MarketplaceMarketPage(c)
                                  : c.mainTab == 5 && !c.hasItem
                                  ? MarketplaceWatchPage(c)
                                  : c.mainTab == 3
                                  ? MarketplaceMyActivity(
                                      c,
                                      key: ValueKey(c.contextRevision),
                                    )
                                  // 0.7.2 G1: the approved contracts page.
                                  : c.mainTab == 2
                                  ? MarketplaceContractsPage(
                                      c,
                                      key: ValueKey(c.contextRevision),
                                    )
                                  // 0.7.2 G2: the approved read-only warehouse.
                                  : c.mainTab == 4
                                  ? MarketplaceWarehousePage(
                                      c,
                                      key: ValueKey(c.contextRevision),
                                    )
                                  : c.mainTab != 0
                                  ? MarketNotice(marketText(context, 'soon'))
                                  : c.hasItem
                                  ? MarketplaceItemPage(c)
                                  : c.hasCatalog
                                  ? marketCatalogView(context, c, _block)
                                  : _hall(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// Each reattachment starts from the current hall position. A constructor-time
// offset and the surrounding route's PageStorage are not reliable across
// repeated swaps between the hall and item scrollables.
class _HallScrollController extends ScrollController {
  _HallScrollController(this.readOffset) : super(keepScrollOffset: false);
  final double Function() readOffset;

  @override
  double get initialScrollOffset => readOffset();
}
