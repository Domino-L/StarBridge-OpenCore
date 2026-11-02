import 'package:flutter/foundation.dart';

import 'marketplace_details.dart' show marketMyOrders;
import 'marketplace_port.dart';
import 'marketplace_trades_controller.dart';

/// The signed-in trader's own side of the hall: 我的挂单 and the SCM profile.
mixin MarketplaceAccount on ChangeNotifier {
  MarketplacePort get port;
  MarketplaceTradesController get trades;
  int get contextRevision;
  @protected
  bool get isDisposed;
  void tab(int value);

  /// Reads every page of 我的挂单 so own listings are marked everywhere and
  /// cannot be traded with. Only order numbers are kept; failures keep the
  /// last known set (SCM still rejects a self-trade with a clear message).
  Future<void> refreshMyOrders() async {
    final source = port;
    if (source is! BridgeMarketplacePort ||
        !source.session.hostCapabilities.contains('marketplace.listings')) {
      return;
    }
    final context = contextRevision;
    final found = <String>{};
    final listings = <MarketRow>[];
    try {
      for (var page = 1; page <= 10; page++) {
        final data = await source.listings('read', {'page': page});
        if (isDisposed || context != contextRevision) return;
        final rows = marketRows(data['rows']);
        found.addAll(rows.map((r) => '${r['id']}'));
        listings.addAll(rows);
        final total = marketNumber(data['total']);
        if (rows.isEmpty || total == null || found.length >= total) break;
      }
    } on Object {
      return;
    }
    marketMyOrders
      ..clear()
      ..addAll(found);
    myListings = listings;
    myListingsLoaded = true;
    notifyListeners();
  }

  /// Own listings as last read from 我的挂单 (every page).
  List<MarketRow> myListings = const [];

  /// The signed-in trader's SCM profile (reputation, completed deals, trade
  /// window, listing limit) for the hall banner. Null when unavailable.
  MarketRow? tradeProfile;
  Future<void> loadTradeProfile() async {
    final source = port;
    if (source is! MarketplaceTradeProfilePort ||
        source is BridgeMarketplacePort &&
            !source.session.hostCapabilities.contains('tradeProfile.read')) {
      return;
    }
    final context = contextRevision;
    try {
      final profile = await (source as MarketplaceTradeProfilePort)
          .tradeProfile();
      if (isDisposed || context != contextRevision) return;
      tradeProfile = profile;
      notifyListeners();
    } on Object {
      // The banner shows its neutral state; trading itself is unaffected.
    }
  }

  /// Trades still in progress (same rule as 我的交易「进行中」).
  int get activeTradeCount => trades.rows
      .where(
        (r) => ![3, 4].contains(r['deliveryStatus']) || tradeAction(r) != null,
      )
      .length;

  /// Whether this client can read 我的挂单 (Host advertises listings).
  bool get myListingsSupported {
    final source = port;
    return source is BridgeMarketplacePort &&
        source.session.hostCapabilities.contains('marketplace.listings');
  }

  /// True once 我的挂单 has been read at least once for this account.
  bool myListingsLoaded = false;

  /// Sub-tab 我的交易 should open on next (0 交易, 1 挂单, 2 清单); read once.
  int activityTab = 0;
  void openMyListings() {
    activityTab = 1;
    tab(3);
  }
}
