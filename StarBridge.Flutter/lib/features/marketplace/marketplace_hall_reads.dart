import 'marketplace_controller.dart';
import 'marketplace_port.dart';

/// Read-only lookups the hall renders from blocks it has already loaded.
extension MarketHallReads on MarketplaceController {
  /// On-sale listings for a top-level category, or null when unknown.
  int? categoryListingCount(int categoryId) {
    for (final row in blocks['categoryListings']?.rows ?? const <MarketRow>[]) {
      if (marketNumber(row['id'])?.toInt() == categoryId) {
        return marketNumber(row['count'])?.toInt();
      }
    }
    return null;
  }

  /// "微科星 · 新巴贝奇": the level above the station (planet or system) plus
  /// the station, from SCM's location path. Falls back to the quote's name.
  String locationLabel(MarketRow row) {
    final id = marketNumber(row['locationId'])?.toInt();
    final name = row['locationName']?.toString() ?? '';
    for (final location in blocks['locations']?.rows ?? const <MarketRow>[]) {
      if (marketNumber(location['id'])?.toInt() != id) continue;
      final parts = '${location['fullPath'] ?? ''}'
          .split('/')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        return '${parts[parts.length - 2]} · ${parts.last}';
      }
    }
    return name;
  }
}
