import 'dart:convert';
import 'marketplace_widgets.dart' show marketIsChecklist;
import 'marketplace_listings_controller.dart';
import 'marketplace_order_full.dart';
import 'marketplace_port.dart';

bool listingCanCopy(MarketRow row, [MarketOrderFull? orders]) {
  if (marketIsChecklist(row)) return false;
  if (row['displayType'] != 3 && row['side'] != 'barter') return true;
  final full = row['itemsComplete'] == true ? row
      : orders?.cachedOrder('${row['orderNumber'] ?? row['id']}');
  final count = full == null ? marketNumber(row['itemCount'])
      : marketRows(full['items']).length;
  return marketNumber(row['creatorType']) == 1 && count == 1 &&
      (full == null || marketRows(full['wantedItems']).length == 1);
}

MarketRow listingOrderRow(MarketRow row) => {
  ...row,
  'orderNumber': row['orderNumber'] ?? row['id'],
  'itemName': row['itemName'] ?? row['name'],
  'unitPrice': row['unitPrice'] ?? row['price'],
  'remainingQuantity': row['remainingQuantity'] ?? row['quantity'],
  'locationId': row['locationId'] ?? row['location'],
  'thumbnailUrl': row['thumbnailUrl'] ?? row['image'],
};

String listingCopyQuality(MarketRow row) {
  final raw = row['qualityData'];
  try {
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map) return '';
    final value = data[row['side'] == 'buy' || row['creatorType'] == 0 ? 'qualityMin' : 'quality'];
    final quality = marketNumber(value);
    return quality != null && quality.isFinite && quality >= 0 && quality <= 1000 &&
        quality == quality.roundToDouble() ? quality.toInt().toString() : '';
  } on FormatException {
    return '';
  }
}

/// Called only by an explicit Copy action; never by a list build or prefetch.
Future<ListingDraft> duplicateListing(MarketRow row, MarketOrderFull? orders) async {
  final quality = listingCopyQuality(row);
  final draft = ListingDraft(
    item: {'id': row['itemId'], 'name': row['name'], 'thumbnailUrl': row['image'],
      'hasQuality': quality.isNotEmpty},
    side: row['side'] as String? ?? 'sell',
    price: row['side'] == 'barter' ? '' : '${row['price'] ?? ''}',
    quantity: '${row['quantity'] ?? 1}',
    location: '${row['location'] ?? ''}',
    quality: quality,
  );
  if (draft.side != 'barter') return draft;
  final full = await orders?.fullOrder({...listingOrderRow(row), 'displayType': 3});
  final wanted = marketRows(full?['wantedItems']);
  // "每次给出" is not copied: barters published by 0.7.2 / 0.7.2.1 stored the
  // stock count there, and nothing tells an old listing from a new one. The
  // draft keeps the default 1 and the user sets it in the wizard.
  // The current wizard can faithfully represent one wanted item only.
  if (wanted.length == 1) {
    final item = wanted.single;
    draft.wanted = '${item['itemId'] ?? ''}';
    draft.wantedQuantity = '${item['quantity'] ?? 1}';
    draft.wantedItem = {...item, 'id': item['itemId'], 'name': item['itemName']};
  }
  return draft;
}
