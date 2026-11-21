import 'marketplace_port.dart';
import 'marketplace_time.dart';
import 'marketplace_widgets.dart' show marketIsChecklist, marketChecklistArt;

bool marketSingleListing(MarketRow row) =>
    !marketIsChecklist(row) && row['displayType'] != 3 && row['side'] != 'barter';

/// Capacity used, as SCM counts it: every undeleted order of the account
/// (sell, buy, checklist, barter, shown or hidden; ScMarket-java 3195c178
/// `OrdersServiceImpl` create check via `countByCreatorId`), i.e. the
/// own-orders page total (CX-HALL-FIX4-REVIEW P2).
int? marketListingCount(List<MarketRow> rows, int? total) => total;

bool marketListingFull(List<MarketRow> rows, int? total, int? limit) =>
    total != null && limit != null && total >= limit;

bool marketListingExpired(MarketRow row, {DateTime? now}) {
  final expiry = scmInstant(row['expiry']);
  return expiry != null && !expiry.isAfter(now ?? DateTime.now());
}

String? marketListingImage(MarketRow row) => marketIsChecklist(row)
    ? marketChecklistArt : row['image'] as String?;
