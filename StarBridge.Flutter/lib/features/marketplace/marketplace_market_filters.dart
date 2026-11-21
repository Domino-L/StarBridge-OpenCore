import 'package:flutter/material.dart';

import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_browser.dart';
import 'marketplace_display_copy.dart';
import 'marketplace_display_rules.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_port.dart';
import 'marketplace_widgets.dart';
import 'marketplace_browser_copy.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_prefetch.dart';
import 'marketplace_category_tree.dart';
import 'marketplace_dialog_scope.dart';
import 'marketplace_diagonal.dart' show MarketHeadingMark;

class MarketplaceMarketFilters extends StatefulWidget {
  const MarketplaceMarketFilters(
    this.controller, {
    required this.reset,
    super.key,
  });
  final MarketplaceController controller;
  final Future<void> Function(Future<void>) reset;
  @override
  State<MarketplaceMarketFilters> createState() => _FiltersState();
}

class _FiltersState extends State<MarketplaceMarketFilters> {
  MarketplaceBrowser get b => widget.controller.browser;
  Future<void> _reset(Future<void> work) => widget.reset(work);
  Widget _box(Widget child) =>
      MarketSurface(padding: const EdgeInsets.all(12), child: child);
  // Every filter group opens with the same slanted mark and title; the first
  // sits flush with the panel's padding.
  Widget _heading(String label, {bool first = false}) => Padding(
    padding: EdgeInsets.only(top: first ? 0 : 16, bottom: 8),
    child: Row(
      children: [
        Transform.scale(
          scale: .75,
          alignment: Alignment.centerLeft,
          child: MarketHeadingMark(),
        ),
        const SizedBox(width: 6),
        // Long English group titles must not overflow the panel.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.tokens.colors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _choices(
    String label,
    String key,
    Map<String, String> values, {
    bool first = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(label, first: first),
      MarketChoiceGrid(
        children: [
          for (final entry in values.entries)
            MarketToggle(
              fill: true,
              label: Text(entry.value, maxLines: 1, softWrap: false),
              selected: (b.options[key] ?? '') == entry.key,
              onSelected: (_) => _reset(b.filter(key, entry.key)),
            ),
        ],
      ),
    ],
  );
  static InputBorder _square(InputBorder? border) => border is OutlineInputBorder
      ? border.copyWith(borderRadius: BorderRadius.zero)
      : const OutlineInputBorder(borderRadius: BorderRadius.zero);
  Widget _number(String label, String key) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextFormField(
      key: ValueKey((b.category, b.kind, key, b.options[key])),
      initialValue: b.options[key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        // The theme's borders, squared like the rest of the hall.
        border: _square(Theme.of(context).inputDecorationTheme.border),
        enabledBorder: _square(
          Theme.of(context).inputDecorationTheme.enabledBorder,
        ),
        focusedBorder: _square(
          Theme.of(context).inputDecorationTheme.focusedBorder,
        ),
      ),
      onFieldSubmitted: (value) {
        if (value.isEmpty || num.tryParse(value) != null) {
          _reset(b.filter(key, value));
        }
      },
    ),
  );
  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.zero,
    children: [
      // Both tabs browse by category; orders count the current filter's
      // orders (G3, user 2026-11-14).
      _box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MarketCategoryTree(
              categories: b.categories,
              selected: b.category,
              onSelect: (id) => _reset(b.choose(category: id, narrow: true)),
              allLabel: b.kind == 'orders'
                  ? marketBrowserText(context, '全部订单', 'All orders')
                  : marketBrowserText(context, '全部物品', 'All items'),
              allCount: b.kind == 'orders'
                  ? (b.category == 0 ? b.result?.total : null)
                  : widget.controller.blocks['categories']?.total,
              expandedRoots: {
                for (final r in b.path) (r['id'] as num).toInt(),
              },
              childCount: (id) =>
                  b.category == id ? b.result?.data['allTotal'] : null,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: b.kind == 'orders'
              ? [
                  // Side and order type are separate, as on SCM's order search:
                  // a checklist or barter order can be a sell or a buy order.
                  _choices(
                    marketBrowserText(context, '方向', 'Side'),
                    'creatorType',
                    {
                      '': marketBrowserText(context, '全部', 'All'),
                      '1': marketBrowserText(context, '出售', 'Sell'),
                      '0': marketBrowserText(context, '求购', 'Buy'),
                    },
                    first: true,
                  ),
                  _choices(
                    marketBrowserText(context, '类型', 'Type'),
                    'displayType',
                    {
                      '': marketBrowserText(context, '全部', 'All'),
                      '1': marketBrowserText(context, '单件', 'Single'),
                      '2': marketBrowserText(context, '清单', 'Checklist'),
                      '3': marketBrowserText(context, '以物易物', 'Barter'),
                    },
                  ),
                  _choices(
                    marketBrowserText(context, '卖家状态', 'Seller status'),
                    'creatorStatus',
                    {
                      '': marketBrowserText(context, '全部', 'All'),
                      '1': marketBrowserText(context, '在线', 'Online'),
                      '2': marketBrowserText(context, '游戏中', 'In game'),
                    },
                  ),
                  if (marketBundleType(b.options))
                    Text(marketDisplayText(context, 'noBundleSort')),
                  if (!marketBundleType(b.options)) ...[
                  _heading(
                    marketBrowserText(context, '单价（UEC）', 'Unit price (UEC)'),
                  ),
                  if (b.options['displayType'] == null)
                    Text(marketDisplayText(context, 'singleOnly')),
                  Row(
                    children: [
                      Expanded(
                        child: _number(
                          marketBrowserText(context, '最低', 'Min'),
                          'minPrice',
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('–'),
                      ),
                      Expanded(
                        child: _number(
                          marketBrowserText(context, '最高', 'Max'),
                          'maxPrice',
                        ),
                      ),
                    ],
                  ),
                  ],
                  _heading(marketBrowserText(context, '交易地点', 'Location')),
                  SizedBox(
                    height: 30,
                    width: double.infinity,
                    child: marketButtonAction(OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: const RoundedRectangleBorder(),
                        foregroundColor: context.tokens.colors.textSecondary,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: _locations,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              b.location == null
                                  ? marketBrowserText(
                                      context,
                                      '全部地点',
                                      'All locations',
                                    )
                                  : marketName(
                                      b.location!,
                                      marketLocale(context),
                                      field: 'name',
                                    ),
                            ),
                          ),
                          const MarketplaceIcon(
                            MarketplaceGlyph.expand,
                            size: 16,
                          ),
                        ],
                      ),
                    ), key: const Key('market-filter-location')),
                  ),
                  _choices(
                    marketBrowserText(context, '品质', 'Quality'),
                    'hasQuality',
                    {
                      '': marketBrowserText(context, '全部', 'All'),
                      'true': marketBrowserText(
                        context,
                        '只看有品质',
                        'With quality',
                      ),
                    },
                  ),
                  _number(
                    b.options['creatorType'] == '0'
                        ? marketDisplayText(context, 'myQuality')
                        : marketBrowserText(context, '最低品质', 'Minimum quality'),
                    'minQuality',
                  ),
                  if (b.options['creatorType'] == '0') ...[
                    if (b.options['minQuality'] case final quality?)
                      Text(marketDisplayText(context, 'buyCeiling', n: quality)),
                    Text(marketDisplayText(context, 'loadedOnly')),
                  ],
                ]
              : [
                  if (b.category != 0 && marketRows(b.config['filters'])
                      .where((f) => f['type'] != 'field')
                      .isEmpty)
                    Text(
                      marketBrowserText(
                        context,
                        '此分类暂无专属筛选条件',
                        'No category-specific filters are configured.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: context.tokens.colors.textSecondary,
                      ),
                    ),
                  for (final filter in marketRows(b.config['filters']))
                    if (filter['type'] == 'enum')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _heading(
                            marketBrowserLabel(context, filter),
                            first: filter == marketRows(b.config['filters']).first,
                          ),
                          MarketChoiceGrid(
                            children: [
                              for (final option in marketRows(
                                filter['options'],
                              ))
                                MarketToggle(
                                  fill: true,
                                  label: Text(
                                    marketBrowserLabel(context, option),
                                    maxLines: 1,
                                    overflow: fadeOverflow(context),
                                    softWrap: false,
                                  ),
                                  selected:
                                      (b.options['enum:${filter['jsonPath']}'] ??
                                              '')
                                          .split(',')
                                          .contains(option['value']),
                                  onSelected: (selected) {
                                    final key = 'enum:${filter['jsonPath']}';
                                    final values = (b.options[key] ?? '')
                                        .split(',')
                                        .where((v) => v.isNotEmpty)
                                        .toSet();
                                    if (selected) {
                                      values.add(option['value'].toString());
                                    } else {
                                      values.remove(option['value']);
                                    }
                                    _reset(b.filter(key, values.join(',')));
                                  },
                                ),
                            ],
                          ),
                        ],
                      )
                    else if (filter['type'] == 'range') ...[
                      _heading(
                        marketBrowserLabel(context, filter),
                        first: filter == marketRows(b.config['filters']).first,
                      ),
                      _number(
                        marketBrowserText(context, '最低', 'Minimum'),
                        'min:${filter['jsonPath']}',
                      ),
                      _number(
                        marketBrowserText(context, '最高', 'Maximum'),
                        'max:${filter['jsonPath']}',
                      ),
                    ],
                ],
        ),
      ),
    ],
  );
  Future<void> _locations() async {
    final picked = await pickMarketLocation(context, widget.controller.port);
    if (!mounted || picked == null) return;
    b.location = picked['id'] == 0 ? null : picked;
    await _reset(
      b.filter('locationId', picked['id'] == 0 ? null : '${picked['id']}'),
    );
  }
}

/// Returns the chosen location row, {'id': 0} for "all", or null when dismissed.
Future<MarketRow?> pickMarketLocation(
  BuildContext context,
  MarketplacePort port,
) => showDialog<MarketRow>(
  context: context,
  useRootNavigator: MarketplaceDialogScope.useRootNavigator(context),
  builder: (_) => _LocationPicker(port),
);

class _LocationPicker extends StatefulWidget {
  const _LocationPicker(this.port);
  final MarketplacePort port;
  @override
  State<_LocationPicker> createState() => _LocationState();
}

class _LocationState extends State<_LocationPicker> {
  MarketRead? data;
  String query = '';
  int page = 1, version = 0;
  bool failed = false, loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (loading || !marketHasMore(data))) return;
    final request = ++version;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final next = await widget.port.read(
        'locations',
        keyword: query,
        page: more ? page + 1 : 1,
      );
      if (!mounted || request != version) return;
      setState(() {
        data = more && data != null
            ? MarketRead({
                ...next.data,
                if (next.rows.isEmpty) 'pageEnd': true,
                'rows': [...data!.rows, ...next.rows],
              }, next.readAt)
            : next;
        page = more ? page + 1 : 1;
      });
    } on Object {
      if (mounted && request == version) setState(() => failed = true);
    } finally {
      if (mounted && request == version) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(marketBrowserText(context, '交易地点', 'Trade location')),
    content: SizedBox(
      width: 400,
      height: 420,
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: marketBrowserText(context, '搜索地点', 'Search locations'),
            ),
            onSubmitted: (q) {
              query = q;
              _load();
            },
          ),
          marketTextAction(
            key: const Key('market-location-all'),
            onPressed: () => Navigator.pop(context, <String, Object?>{'id': 0}),
            child: Text(marketBrowserText(context, '全部地点', 'All locations')),
          ),
          if (failed)
            marketTextAction(
              key: const Key('market-location-retry'),
              onPressed: _load,
              child: Text(marketText(context, 'retry')),
            ),
          if (loading && data == null) const LinearProgressIndicator(),
          Expanded(
            child: MarketPrefetch(
              read: data,
              loading: loading,
              failed: failed,
              load: () => _load(more: true),
              child: ListView.builder(
                itemCount: data?.rows.length ?? 0,
                itemBuilder: (_, i) => StarBridgeActionRow(
                  inheritContentStyle: true,
                  controlKey: ValueKey(('market-location', data!.rows[i]['id'])),
                  baseRadius: 0,
                  // One named button per location, like the native ListTile.
                  semanticLabel: marketName(
                    data!.rows[i],
                    marketLocale(context),
                    field: 'name',
                  ),
                  onActivate: (_, _) => Navigator.pop(context, data!.rows[i]),
                  child: ExcludeSemantics(
                    child: ListTile(
                      title: Text(
                        marketName(
                          data!.rows[i],
                          marketLocale(context),
                          field: 'name',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (data != null)
            MarketPageStatus(
              read: data!,
              loading: loading,
              failed: failed,
              load: () => _load(more: true),
            ),
        ],
      ),
    ),
    actions: [
      marketTextAction(
        key: const Key('market-location-close'),
        onPressed: () => Navigator.pop(context),
        child: Text(marketBrowserText(context, '关闭', 'Close')),
      ),
    ],
  );
}
