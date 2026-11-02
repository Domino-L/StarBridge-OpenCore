import 'marketplace_port.dart';
import 'marketplace_listings_controller.dart';
import 'marketplace_details.dart';

/// SCM search rows use itemName/sellOrderCount/qualityInfo; the wizard reads
/// name/sellCount/hasQuality. Convert once here so every picker sees real data.
MarketRow listingPickable(MarketRow row) {
  String? text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;
  final quality = row['qualityInfo'];
  final qualityText = quality?.toString().trim() ?? '';
  return {
    ...row,
    'name': text(row['name']) ?? text(row['itemName']) ?? text(row['itemNameEn']) ?? '',
    'sellCount': row['sellCount'] ?? row['sellOrderCount'],
    'buyCount': row['buyCount'] ?? row['buyOrderCount'],
    'hasQuality': row['hasQuality'] ??
        (qualityText.isNotEmpty && qualityText != 'null' && qualityText != '{}'),
  };
}

/// Uses the same authenticated bridge and account generation as trading.
class BridgeMarketplaceListingsPort implements MarketplaceListingsPort, MarketplaceListingLookup {
  BridgeMarketplaceListingsPort(this.port);
  final BridgeMarketplacePort port;
  @override
  Future<List<MarketRow>> searchItems(String query, {int category = 0, int page = 1}) async =>
      (await port.read('search', keyword: query, category: category, page: page)).rows.map(listingPickable).toList();
  @override
  Future<List<MarketRow>> categories() async => (await port.read('categories')).rows;
  @override
  Future<MarketRow> nextPage(int page) => port.listings('read', {'page': page});
  @override
  Future<MarketRow> read() async {
    final generation = port.generation;
    final data = await port.listings('read');
    // The profile only feeds the limit and trade window; its failure must not hide the listings.
    MarketRow? profile;
    try {
      profile = await port.tradeProfile();
    } on MarketplaceTradeError catch (e) {
      if (e.code == 'marketplace.context_changed') rethrow;
    } on FormatException {
      // Older Host without tradeProfile, or a transient read failure.
    }
    marketRememberZones((await port.read('timezones')).rows);
    final items = await port.read('search');
    final locations = await port.read('locations');
    if (generation != port.generation) {
      throw const MarketplaceTradeError('marketplace.context_changed');
    }
    return {...data, 'items': items.rows.map(listingPickable).toList(), 'locations': locations.rows,
      'limit': profile?['orderLimit'], 'tradeProfile': profile};
  }
  @override
  Future<void> write(String operation, MarketRow input) async {
    final result = await port.listings(operation, input);
    if (result['confirmed'] != true) {
      throw const MarketplaceTradeError('marketplace.unknown');
    }
  }
}
