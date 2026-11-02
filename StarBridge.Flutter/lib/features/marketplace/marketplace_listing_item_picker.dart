import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_category_tree.dart';
import 'marketplace_copy.dart';
import 'marketplace_listing_copy.dart';
import 'marketplace_listing_publish_widgets.dart';
import 'marketplace_listings_controller.dart';
import 'marketplace_port.dart';

/// Publish wizard step 2, browsed like 市场: the shared category tree on the
/// left, a searchable two-column item grid on the right (live listings first,
/// next page on scroll). Picking an item writes it into [draft].
class ListingItemPicker extends StatefulWidget {
  const ListingItemPicker(
    this.c,
    this.draft, {
    required this.onPicked,
    super.key,
  });
  final MarketplaceListingsController c;
  final ListingDraft draft;
  final VoidCallback onPicked;
  @override
  State<ListingItemPicker> createState() => _ListingItemPickerState();
}

class _ListingItemPickerState extends State<ListingItemPicker> {
  String query = '';
  Timer? _searchDebounce;
  ListingDraft get d => widget.draft;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// Top-level category that contains [id] (0 when browsing everything).
  int _rootOf(MarketplaceListingsController c, int id) {
    var current = id;
    for (var guard = 0; current != 0 && guard < 8; guard++) {
      final row = c.categories
          .where((r) => marketNumber(r['id'])?.toInt() == current)
          .firstOrNull;
      final parent = marketNumber(row?['parentId'])?.toInt() ?? 0;
      if (parent == 0) return current;
      current = parent;
    }
    return current;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final sideColor = listingSideColor(context, d.side);
    final current = c.categories
        .where((r) => marketNumber(r['id'])?.toInt() == c.itemCategory)
        .firstOrNull;
    final needle = query.trim().toLowerCase();
    // Items with live listings first, like 市场's default ordering.
    final shown =
        c.items
            .where(
              (r) => '${r['name']} ${r['itemNameEn'] ?? ''}'
                  .toLowerCase()
                  .contains(needle),
            )
            .toList()
          ..sort(
            (x, y) =>
                ((marketNumber(y['sellCount']) ?? 0) +
                        (marketNumber(y['buyCount']) ?? 0))
                    .compareTo(
                      (marketNumber(x['sellCount']) ?? 0) +
                          (marketNumber(x['buyCount']) ?? 0),
                    ),
          );
    final t = context.tokens;
    return SizedBox(
      height: 380,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 196,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: t.surfaces.panel.border),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.only(right: 10),
                children: [
                  MarketCategoryTree(
                    categories: c.categories,
                    selected: c.itemCategory,
                    accent: sideColor,
                    allLabel: listingText(context, '全部物品'),
                    expandedRoots: {_rootOf(c, c.itemCategory)},
                    onSelect: (id) {
                      _searchDebounce?.cancel();
                      c.searchItems(query, category: id);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  autofocus: true,
                  decoration: listingInputDecoration(
                    context,
                    hint: current == null
                        ? listingText(context, '搜索物品，中英文均可')
                        : listingText(context, '在「{name}」中搜索', {
                            'name':
                                '${(marketLocale(context) == 'en' ? current['nameEn'] : null) ?? current['name'] ?? current['nameEn'] ?? ''}',
                          }),
                    prefix: const MarketplaceIcon(
                      MarketplaceGlyph.search,
                      size: 18,
                    ),
                  ),
                  onChanged: (v) {
                    setState(() => query = v);
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 250),
                      () => c.searchItems(v),
                    );
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 2,
                  child: c.itemsLoading
                      ? LinearProgressIndicator(
                          color: sideColor,
                          backgroundColor: Colors.transparent,
                        )
                      : null,
                ),
                const SizedBox(height: 6),
                // A pick is never dropped silently: when a new search or
                // category hides it, say what is still selected.
                if (d.item['id'] != null &&
                    !shown.any((r) => r['id'] == d.item['id']))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      listingText(context, '已选：{name}（不在当前结果中）', {
                        'name': '${d.item['name'] ?? ''}',
                      }),
                      key: const Key('publish-picked-hidden'),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(fontSize: 12, color: sideColor),
                    ),
                  ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Text(
                            listingText(
                              context,
                              c.itemsLoading ? '正在查找…' : '没有找到物品，换个关键词或分类试试',
                            ),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: t.colors.textSecondary,
                            ),
                          ),
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (event) {
                            if (event.metrics.extentAfter < 160) {
                              c.searchMoreItems();
                            }
                            return false;
                          },
                          child: GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisExtent: 58,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: shown.length,
                            itemBuilder: (context, i) {
                              final r = shown[i];
                              final sells = r['sellCount'],
                                  buys = r['buyCount'];
                              return ListingPickTile(
                                art: r['thumbnailUrl'] as String?,
                                title: '${r['name']}',
                                subtitle:
                                    (marketNumber(sells) ?? 0) +
                                            (marketNumber(buys) ?? 0) ==
                                        0
                                    ? listingText(context, '暂无挂单')
                                    : listingText(
                                        context,
                                        '出售 {sell} · 求购 {buy}',
                                        {
                                          'sell': '${sells ?? 0}',
                                          'buy': '${buys ?? 0}',
                                        },
                                      ),
                                selected: d.item['id'] == r['id'],
                                onTap: () {
                                  setState(() => d.item = r);
                                  widget.onPicked();
                                },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
