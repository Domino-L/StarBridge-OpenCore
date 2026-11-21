import 'marketplace_listings_controller.dart';
import 'marketplace_port.dart';

/// Manifest prices belong to their lines. Never use a stale single-item price.
extension ListingManifestPrice on MarketplaceListingsController {
  num? priceFor(ListingDraft draft) {
    if (draft.manifestId == null) return draft.amount;
    final manifest = manifests.where((r) => r['id'] == draft.manifestId).firstOrNull;
    final items = marketRows(manifest?['items']);
    if (items.isEmpty) return null;
    num total = 0;
    for (final item in items) {
      // The Host's manifest projection names a line's price `price`.
      final price = marketNumber(item['price'] ?? item['unitPrice']);
      final quantity = marketNumber(item['quantity']);
      if (price == null || !price.isFinite || price <= 0 ||
          quantity == null || !quantity.isFinite || quantity <= 0) {
        return null;
      }
      total += price * quantity;
    }
    return total.isFinite ? total : null;
  }

  String? manifestPriceError(ListingDraft draft) =>
      draft.manifestId != null && priceFor(draft) == null
          ? '清单里有物品没有填单价，请先到 SCM 补上' : null;
}
