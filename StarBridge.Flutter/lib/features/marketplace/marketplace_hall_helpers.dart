import 'dart:convert';

import 'package:flutter/material.dart';

import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_port.dart';
import 'marketplace_widgets.dart';

Widget marketWatchPrice(BuildContext context, MarketplaceController c, int id) {
  final sell = c.blocks['watch-price:$id'];
  final buy = c.blocks['watch-buy:$id'];
  if (c.failures.contains('watch-price:$id')) {
    return Text(marketText(context, 'unavailable'));
  }
  if (sell == null) return Text(marketText(context, 'loading'));
  if (sell.rows.isNotEmpty) {
    final price = sell.rows.first['unitPrice'];
    return price == null
        ? Text(marketText(context, 'unavailable'))
        // One line under the name: the label, then the price (user 10-27:
        // a right-aligned label above the price sat on the item name).
        : Row(
            key: ValueKey(('market-watch-price', id)),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                marketText(context, 'lowest'),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: MarketPrice(price)),
            ],
          );
  }
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(marketText(context, 'noSell')),
      if (c.failures.contains('watch-buy:$id'))
        Text(marketText(context, 'unavailable'))
      else if (marketNumber(buy?.rows.firstOrNull?['unitPrice'])
          case final num price)
        Text('${marketText(context, 'highest')} ${marketMoney(price)} UEC'),
    ],
  );
}

String marketAttachmentConditions(
  BuildContext context,
  MarketplaceController c,
  MarketRead? read,
) {
  final labels = <String, String>{};
  for (final category in c.blocks['categories']?.rows ?? <MarketRow>[]) {
    final raw = category['filterConfig'];
    try {
      final config = raw is String ? jsonDecode(raw) : raw;
      if (config is! Map) continue;
      for (final filter in marketRows(config['filters'])) {
        for (final option in marketRows(filter['options'])) {
          final label =
              option[marketLocale(context) == 'en' ? 'labelEn' : 'label'];
          if (label is String && label.isNotEmpty) {
            labels[option['value'].toString()] = label;
          }
        }
      }
    } on FormatException {
      /* Unconfigured conditions are omitted. */
    }
  }
  return marketRows(read?.data['filters'])
      .map((filter) {
        final label = labels[filter['subType']];
        if (label == null) return '';
        final min = marketNumber(filter['minSize']),
            max = marketNumber(filter['maxSize']);
        return label +
            (min == null
                ? ''
                : ' S${min.toInt()}${max == null || max == min ? '' : '–S${max.toInt()}'}');
      })
      .where((value) => value.isNotEmpty)
      .join(' · ');
}

/// The page 返回 goes to, named for the button (user 10-29: never a fixed
/// “大厅”): the previous item, the item catalog, or the tab it came from.
String marketBackLabel(BuildContext context, MarketplaceController c) {
  String tabName(int tab) => marketText(context, switch (tab) {
    1 => 'market',
    2 => 'contracts',
    3 => 'mine',
    4 => 'storage',
    5 => 'watchTab',
    _ => 'hall',
  });
  final place = c.backTarget;
  if (place == null) return tabName(c.itemId != null ? c.itemOrigin : 0);
  if (place.itemId case final int id) {
    final row = c.blocks['recent:$id']?.data ??
        (c.itemId == id ? c.blocks['item']?.data : null);
    return row == null
        ? marketText(context, 'thisItem')
        : marketName(row, marketLocale(context));
  }
  final catalog = place.relation.isNotEmpty ||
      place.keyword.isNotEmpty ||
      place.categoryId != null;
  return place.mainTab == 0 && catalog
      ? marketText(context, 'results')
      : tabName(place.mainTab);
}

/// The back button's text: “← 返回” and the page it returns to.
String marketBackText(BuildContext context, MarketplaceController c) =>
    '← ${marketText(context, 'back')} ${marketBackLabel(context, c)}';

/// The name of an item the hall has already read (the open or last-opened
/// item, or a recent one); null when it has not been read yet.
String? marketKnownItemName(
  BuildContext context,
  MarketplaceController c,
  int id,
) {
  final item = c.blocks['item']?.data;
  final row = c.blocks['recent:$id']?.data ??
      (item != null && marketItemId(item) == id ? item : null);
  final name = row == null ? null : marketName(row, marketLocale(context));
  return name == null || name.isEmpty ? null : name;
}

/// A category’s name from the hall’s category list.
String? marketCategoryName(
  BuildContext context,
  MarketplaceController c,
  int id,
) {
  for (final row in c.blocks['categories']?.rows ?? <MarketRow>[]) {
    if (marketNumber(row['id'])?.toInt() != id) continue;
    final name = marketName(row, marketLocale(context), field: 'name');
    return name.isEmpty ? null : name;
  }
  return null;
}

/// Long names are cut for chips; the full name goes to hover and readers.
String marketShort(String text, [int max = 18]) {
  final chars = text.characters;
  return chars.length <= max ? text : '${chars.take(max - 1)}…';
}
