import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/icons/marketplace_icon.dart';
import 'marketplace_browser_copy.dart';
import 'marketplace_market_filters.dart';
import 'marketplace_market_order_row.dart';
import 'marketplace_order_sheet.dart';
import 'marketplace_prefetch.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_unified.dart';
import 'marketplace_banner.dart' show MarketplaceSurfaceColors;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_browser.dart';
import 'marketplace_controller.dart';
import 'marketplace_hall_drawers.dart';
import 'marketplace_copy.dart';
import 'marketplace_hall_reads.dart';
import 'marketplace_port.dart';
import 'marketplace_widgets.dart';

class MarketplaceMarketPage extends StatefulWidget {
  const MarketplaceMarketPage(this.controller, {super.key});
  final MarketplaceController controller;
  @override
  State<MarketplaceMarketPage> createState() => _MarketState();
}

class _MarketState extends State<MarketplaceMarketPage> {
  MarketplaceBrowser get b => widget.controller.browser;
  late final _scroll = _MarketScroll(() => b.offset);
  @override
  void initState() {
    super.initState();
    b.addListener(_queryChanged);
    _scroll.addListener(() {
      if (_scroll.hasClients) b.offset = _scroll.offset;
    });
  }

  @override
  void dispose() {
    b.removeListener(_queryChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _queryChanged() {
    if (b.loading && b.offset == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && b.offset == 0 && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  Future<void> _reset(Future<void> work) async {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await work;
  }

  Future<void> _drawer() async {
    // showGeneralDialog 不带主题，这里带上，抽屉才和页面同色。
    final theme = Theme.of(context);
    await showGeneralDialog<void>(
      context: context,
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: Theme(data: theme, child: child),
      ),
      barrierDismissible: true,
      barrierLabel: marketBrowserText(context, '关闭分类与筛选', 'Close filters'),
      barrierColor: Colors.black54,
      pageBuilder: (dialogContext, _, _) => Align(
        alignment: Alignment.centerLeft,
        child: Material(
          child: SafeArea(
            child: SizedBox(
              width: 300,
              child: ListenableBuilder(
                listenable: b,
                builder: (_, _) => Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            marketBrowserText(
                              context,
                              '分类与筛选',
                              'Categories and filters',
                            ),
                          ),
                        ),
                        StarBridgeNativeIconAction(
                          controlKey: const Key('market-drawer-close'),
                          label: marketBrowserText(context, '关闭', 'Close'),
                          onActivate: (_) => Navigator.pop(dialogContext),
                          icon: const MarketplaceIcon(MarketplaceGlyph.close),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: MarketplaceMarketFilters(
                          widget.controller,
                          reset: _reset,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _order(MarketRow row) =>
      showMarketOrder(context, widget.controller, row);

  Widget _item(MarketRow row, bool cards) => MarketCatalogCard(
    row,
    cards: cards,
    category: b.category,
    open: marketItemId(row) == null
        ? null
        : () => widget.controller.openItem(marketItemId(row)!),
    drawer: (drawer) =>
        marketCatalogDrawer(drawer, context, widget.controller, row),
  );
  // The hall's listing card, unchanged, so an order reads the same in both
  // places (user report, build 11); a click opens the order's details.
  Widget _orderCard(MarketRow row, int index) {
    final c = widget.controller;
    final id = marketItemId(row);
    final side = row['displayType'] == 3
        ? null
        : row['creatorType'] == 0
        ? 0
        : 1;
    final best = id == null || side == null ? null : c.bestPrice(id, side);
    return MarketCard(
      row,
      key: ValueKey(('market-order-card', row['orderNumber'] ?? index)),
      location: c.locationLabel(row),
      best: best,
      watched: c.isWatched(row),
      open: () => _order(row),
      drawer: (drawer) => marketListingDrawer(
        drawer,
        context,
        c,
        row,
        best: best,
        location: c.locationLabel(row),
      ),
    );
  }

  Widget _orderRow(MarketRow row, bool narrow) =>
      MarketplaceMarketOrderRow(row, narrow: narrow, open: () => _order(row));
  // The banner's stat language: label over value, slanted dividers.
  Widget _overview(bool narrow) {
    String? value(Object? v) => v == null ? null : marketMoney(v);
    MarketStat stat(String label, Object? v, [Color? color]) => MarketStat(
      label,
      value(v) ?? marketText(context, 'unavailable'),
      color: v == null ? null : color,
      mono: v != null,
    );
    return MarketSurface(
      child: MarketStatStrip([
        stat(
          marketBrowserText(context, '公开挂单', 'Public orders'),
          b.overview['all'],
          MarketplaceSurfaceColors.gold,
        ),
        stat(
          marketText(context, 'sell'),
          b.overview['sell'],
          context.tokens.colors.accent,
        ),
        stat(
          marketText(context, 'buy'),
          b.overview['buy'],
          MarketplacePalette.buyer,
        ),
        if (!narrow) stat(marketText(context, 'barter'), b.overview['barter']),
        if (!narrow)
          stat(
            marketBrowserText(context, '物品目录', 'Catalogue'),
            widget.controller.blocks['categories']?.total,
          ),
      ]),
    );
  }

  Widget _book(Widget child) => b.kind == 'orders' && b.layout == 'rows'
      ? MarketSurface(child: child)
      : child;
  Widget _content(bool narrow) {
    final data = b.result;
    final sorts = <String, String>{
      if (b.kind == 'orders') ...{
        'time': marketBrowserText(context, '最新发布', 'Newest'),
        'price': marketBrowserText(context, '单价', 'Unit price'),
      } else ...{
        'totalOrderCount': marketBrowserText(context, '挂单最多', 'Most listings'),
        'sellOrderCount': marketBrowserText(
          context,
          '出售最多',
          'Most sell offers',
        ),
        'buyOrderCount': marketBrowserText(context, '求购最多', 'Most buy offers'),
        for (final s in marketRows(b.config['sorts']))
          '${s['jsonPath']}': marketBrowserLabel(context, s),
      },
    };
    final sortKey = b.kind == 'orders' ? 'sortType' : 'sortKey';
    final sort = b.options[sortKey] ?? sorts.keys.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (narrow) ...[
              marketButtonAction(
                OutlinedButton(
                  onPressed: _drawer,
                  child: Text(marketBrowserText(context, '分类与筛选', 'Filters')),
                ),
                key: const Key('market-filters-open'),
              ),
              const SizedBox(width: 8),
            ],
            // Same second-level tabs as the rest of the hall.
            MarketSubTabs([
              for (final entry in [
                ('items', '物品', 'Items'),
                ('orders', '订单', 'Orders'),
              ])
                MarketSubTab(
                  marketBrowserText(context, entry.$2, entry.$3),
                  controlKey: ValueKey(('market-kind', entry.$1)),
                  selected: b.kind == entry.$1,
                  onTap: () => _reset(b.choose(kind: entry.$1)),
                ),
            ]),
            const Spacer(),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: marketLine(context)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButtonHideUnderline(
                child: StarBridgeCompactSelect<String>(
                  identity: 'market-sort',
                  controlKey: const Key('market-sort'),
                  semanticLabel: marketBrowserText(context, '排序', 'Sort'),
                  style: Theme.of(context).textTheme.bodySmall,
                  value:
                      '${sorts.containsKey(sort) ? sort : sorts.keys.first}|${b.options['sortOrder'] ?? 'desc'}',
                  options: [
                    for (final entry in sorts.entries)
                      for (final order in ['desc', 'asc'])
                        StarBridgeSelectOption(
                          value: '${entry.key}|$order',
                          label: entry.value + (order == 'asc' ? ' ↑' : ' ↓'),
                        ),
                  ],
                  onSelected: (v, _) {
                    final parts = v.split('|');
                    b.options['sortOrder'] = parts[1];
                    _reset(b.filter(sortKey, parts[0]));
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            for (final mode in ['cards', 'rows'])
              SizedBox(
                width: 34,
                height: 30,
                child: StarBridgeNativeIconAction(
                  controlKey: ValueKey(('market-layout', mode)),
                  label: marketText(context, mode),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: b.layout == mode
                        ? context.tokens.colors.accent.withValues(alpha: .15)
                        : Colors.transparent,
                  ),
                  onActivate: (_) {
                    b.setLayout(mode);
                    widget.controller.saveView();
                  },
                  icon: MarketplaceIcon(
                    mode == 'cards'
                        ? MarketplaceGlyph.grid
                        : MarketplaceGlyph.rows,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        MarketHeading(
          b.kind == 'orders'
              ? marketBrowserText(context, '全部订单', 'Orders')
              : b.path.isEmpty
              ? marketBrowserText(context, '全部物品', 'All items')
              : marketName(b.path.last, marketLocale(context), field: 'name'),
          titleSize: 18,
          leading: b.path.length > 1
              ? Text(
                  b.path
                      .take(b.path.length - 1)
                      .map(
                        (r) =>
                            marketName(r, marketLocale(context), field: 'name'),
                      )
                      .join(' › '),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.tokens.colors.textSecondary,
                  ),
                )
              : null,
          trailing: Wrap(
            spacing: 8,
            children: [
              if (data != null && (data.data['allTotal'] ?? data.total) != null)
                Text(
                  '${data.data['allTotal'] ?? data.total ?? ''} ${b.kind == 'items' ? marketBrowserText(context, '种物品', 'items') : marketBrowserText(context, '条订单', 'orders')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.tokens.colors.textSecondary,
                  ),
                ),
              if (data != null &&
                  b.kind == 'items' &&
                  data.data['listedTotal'] != null)
                Text(
                  '${data.data['listedTotal']} ${marketBrowserText(context, '种有挂单', 'listed items')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.tokens.colors.textSecondary,
                  ),
                ),
              if (data != null) MarketStamp(data.readAt),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _overview(narrow),
        if (b.overviewFailed)
          Align(
            alignment: Alignment.centerRight,
            child: marketTextAction(
              key: const Key('market-overview-retry'),
              onPressed: b.refreshOverview,
              child: Text(marketText(context, 'retry')),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (b.kind == 'items')
                    MarketToggle(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            marketBrowserText(
                              context,
                              '只看有挂单',
                              'Only listed items',
                            ),
                          ),
                          if (b.listed) ...[
                            const SizedBox(width: 6),
                            const MarketplaceIcon(
                              MarketplaceGlyph.close,
                              size: 14,
                            ),
                          ],
                        ],
                      ),
                      selected: b.listed,
                      onSelected: (v) => _reset(b.toggleListed(v)),
                    ),
                  if (b.keyword.isNotEmpty)
                    InputChip(
                      label: Text(b.keyword),
                      onDeleted: () => _reset(b.choose(keyword: '')),
                    ),
                  for (final entry in b.options.entries.where(
                    (e) => !e.key.startsWith('sort'),
                  ))
                    InputChip(
                      label: Text(_filterLabel(entry.key, entry.value)),
                      onDeleted: () => _reset(b.filter(entry.key, null)),
                    ),
                  if (b.kind == 'items' && b.listed ||
                      b.keyword.isNotEmpty ||
                      b.options.keys.any((k) => !k.startsWith('sort')))
                    marketButtonAction(
                      key: const Key('market-clear-filters'),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontSize: 12.5),
                        ),
                        onPressed: () => _reset(b.clear()),
                        child: Text(marketText(context, 'clearFilters')),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (b.failed)
          if (data != null)
            MarketStale(data.readAt, retry: b.reload)
          else
            MarketNotice(marketText(context, 'unavailable'), retry: b.reload),
        if (b.loading && b.result == null)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _book(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (b.kind == 'orders' && b.layout == 'rows')
                  SizedBox(
                    height: 34,
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontFamily: context.tokens.typography.monoFamily,
                        fontSize: 11,
                        letterSpacing: .66,
                        color: context.tokens.colors.textSecondary,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                marketBrowserText(context, '物品', 'Item'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Text(
                                marketBrowserText(context, '卖家', 'Seller'),
                              ),
                            ),
                            if (!narrow) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  marketBrowserText(
                                    context,
                                    '地点 / 交易时段',
                                    'Location / hours',
                                  ),
                                ),
                              ),
                            ],
                            SizedBox(
                              width: 44,
                              child: Text(
                                marketBrowserText(context, '数量', 'Qty'),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: narrow ? 150 : 190,
                              child: Text(
                                marketBrowserText(context, '单价', 'Price'),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            if (!narrow) ...[
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  marketBrowserText(context, '发布', 'Posted'),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: data == null
                      ? const SizedBox()
                      : MarketPrefetch(
                          read: data,
                          loading: b.loading,
                          failed: b.failed,
                          load: () => b.reload(more: true),
                          child: CustomScrollView(
                            key: const ValueKey('market-results'),
                            controller: _scroll,
                            slivers: [
                              if (data.rows.isEmpty)
                                SliverToBoxAdapter(
                                  child: MarketNotice(
                                    marketText(context, 'empty'),
                                  ),
                                ),
                              if (b.layout == 'cards')
                                SliverGrid.builder(
                                  itemCount: data.rows.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 250,
                                        // Order cards are the hall's cards.
                                        mainAxisExtent: 304,
                                        crossAxisSpacing: 14,
                                        mainAxisSpacing: 14,
                                      ),
                                  itemBuilder: (_, i) => b.kind == 'items'
                                      ? _item(data.rows[i], true)
                                      : _orderCard(data.rows[i], i),
                                )
                              else
                                SliverList.builder(
                                  itemCount: data.rows.length,
                                  itemBuilder: (_, i) => b.kind == 'items'
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: _item(data.rows[i], false),
                                        )
                                      : _orderRow(data.rows[i], narrow),
                                ),
                              SliverToBoxAdapter(
                                child: MarketPageStatus(
                                  read: data,
                                  loading: b.loading,
                                  failed: b.failed,
                                  load: () => b.reload(more: true),
                                ),
                              ),
                              if (b.kind == 'items' &&
                                  b.listed &&
                                  data.data['allTotal'] is num &&
                                  data.total != null)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: MarketRemainder(
                                      count:
                                          (data.data['allTotal'] as num)
                                              .toInt() -
                                          data.total!,
                                      total: (data.data['allTotal'] as num)
                                          .toInt(),
                                      open: () => _reset(b.toggleListed(false)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _filterLabel(String key, String value) {
    if (key == 'creatorType') {
      return marketText(context, value == '0' ? 'buy' : 'sell');
    }
    if (key == 'displayType') {
      return value == '3'
          ? marketText(context, 'barter')
          : marketBrowserText(context, '定价', 'Fixed price');
    }
    if (key == 'creatorStatus') {
      return value == '2'
          ? marketBrowserText(context, '游戏中', 'In game')
          : marketBrowserText(context, '在线', 'Online');
    }
    if (key == 'hasQuality') {
      return marketBrowserText(context, '只看有品质', 'With quality');
    }
    if (key == 'locationId') {
      return b.location == null
          ? marketBrowserText(context, '已选地点', 'Selected location')
          : marketName(b.location!, marketLocale(context), field: 'name');
    }
    for (final f in marketRows(b.config['filters'])) {
      if (key.endsWith(':${f['jsonPath']}')) {
        return '${marketBrowserLabel(context, f)}: ${marketRows(f['options']).where((o) => value.split(',').contains(o['value'])).map((o) => marketBrowserLabel(context, o)).join(', ')}${f['type'] == 'range' ? value : ''}';
      }
    }
    return '${{'minPrice': marketBrowserText(context, '最低价', 'Min price'), 'maxPrice': marketBrowserText(context, '最高价', 'Max price'), 'minQuality': marketBrowserText(context, '最低品质', 'Min quality')}[key] ?? ''}: $value';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: b,
    builder: (_, _) => LayoutBuilder(
      builder: (_, constraints) {
        final narrow = constraints.maxWidth < 900;
        return Theme(
          data: Theme.of(context).copyWith(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft,
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            chipTheme: Theme.of(context).chipTheme.copyWith(
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              labelStyle: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontSize: 12),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!narrow) ...[
                SizedBox(
                  width: 220,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: MarketplaceMarketFilters(
                      widget.controller,
                      reset: _reset,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
              ],
              Expanded(child: _content(narrow)),
            ],
          ),
        );
      },
    ),
  );
}

class _MarketScroll extends ScrollController {
  _MarketScroll(this.read) : super(keepScrollOffset: false);
  final double Function() read;
  @override
  double get initialScrollOffset => read();
}
