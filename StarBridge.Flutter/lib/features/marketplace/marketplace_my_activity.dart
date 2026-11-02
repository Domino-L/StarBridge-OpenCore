import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'bridge_marketplace_listings_port.dart';
import 'marketplace_controller.dart';
import 'marketplace_listing_copy.dart';
import 'marketplace_listings_controller.dart';
import 'marketplace_listings_page.dart';
import 'marketplace_port.dart';
import 'marketplace_records_controller.dart';
import 'marketplace_records_copy.dart';
import 'marketplace_records_page.dart';
import 'marketplace_trades_page.dart';
import 'marketplace_trade_profile.dart';
import 'marketplace_trade_profile_summary.dart';
import 'marketplace_details.dart';
import 'marketplace_activity_rail.dart';
import 'marketplace_trades_controller.dart' show tradeAction;

class MarketplaceMyActivity extends StatefulWidget {
  const MarketplaceMyActivity(this.market, {super.key});
  final MarketplaceController market;
  @override
  State<MarketplaceMyActivity> createState() => _ActivityState();
}

class _ActivityState extends State<MarketplaceMyActivity> {
  MarketplaceListingsController? listings;
  // 0.7.2 G5–G7: 评价 (3) and 举报与拉黑 (4), when the Host offers them.
  MarketplaceRecordsController? records;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    // A request such as 大厅「管理挂单」 opens a specific sub-tab once.
    tab = widget.market.activityTab;
    widget.market.activityTab = 0;
    final port = widget.market.port;
    if (port is BridgeMarketplacePort && port.session.hostCapabilities.contains('marketplace.listings')) {
      listings = MarketplaceListingsController(BridgeMarketplaceListingsPort(port));
    }
    if (port is MarketplaceRecordsPort && (port as MarketplaceRecordsPort).recordsSupported) {
      records = MarketplaceRecordsController(port as MarketplaceRecordsPort);
    }
    widget.market.trades.addListener(_counts);
    listings?.addListener(_counts);
  }
  @override
  void dispose() {
    widget.market.trades.removeListener(_counts);
    listings?.removeListener(_counts);
    listings?.dispose(); records?.dispose(); super.dispose();
  }

  // The rail's counts follow the trades and listings. Their reads may notify
  // while a page builds (a listings refresh in initState), so the rail
  // rebuilds after that frame instead of during it.
  void _counts() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() {}); });
    } else {
      setState(() {});
    }
  }

  Map<String, String> _recordTabs(BuildContext context) => records == null ? const {} : {
    'reviews': recordsText(context, '评价'),
    'reports': recordsText(context, '举报与拉黑'),
  };

  void _open(String key) => setState(() => tab = key == 'reviews' ? 3 : 4);

  @override
  Widget build(BuildContext context) {
    final c = listings;
    final r = records;
    if (c == null && r == null) return MarketplaceTradesPage(widget.market);
    final Widget content;
    if (c != null && (tab == 1 || tab == 2)) {
      content = NotificationListener<ScrollNotification>(onNotification: (event) {
        if (event.metrics.extentAfter < 800) c.loadMore();
        return false;
      }, child: MarketplaceListingsPage(c, key: ValueKey(tab), initialManifests: tab == 2,
        railed: true,
        openTrades: () => setState(() => tab = 0),
        moreTabs: _recordTabs(context),
        openTab: _open,
        editProfile: () async {
          final profile = await editTradeProfile(context, widget.market);
          if (!context.mounted || profile == null) return;
          c.applyTradeProfile(profile, marketTradeTime(context, profile));
        }));
    } else if (r != null && (tab == 3 || tab == 4)) {
      content = tab == 3
          ? MarketplaceReviewsView(r, key: const Key('market-reviews'))
          : MarketplaceReportsBlocksView(r, key: const Key('market-reports-blocks'));
    } else {
      content = MarketplaceTradesPage(widget.market);
    }
    final trades = widget.market.trades;
    // Layout A (user 10-23): the sections on a left rail with their counts,
    // the trading profile as a card under them, the section on the right.
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Builder(
        builder: (context) {
          final waiting = trades.rows.where((row) => tradeAction(row) != null).length;
          return MarketActivityRail(
            key: const Key('market-activity-tab'),
            selected: tab,
            onSelect: (value) => setState(() => tab = value),
            items: [
              (id: 0, label: listingText(context, '交易'), count: waiting > 0 ? '$waiting' : null, hot: waiting > 0),
              if (c != null) ...[
                (id: 1, label: listingText(context, '挂单'),
                  count: '${c.rows.length}${c.limit == null ? '' : ' / ${c.limit}'}', hot: false),
                (id: 2, label: listingText(context, '清单'), count: null, hot: false),
              ],
              if (r != null) ...[
                (id: 3, label: recordsText(context, '评价'), count: null, hot: false),
                (id: 4, label: recordsText(context, '举报与拉黑'), count: null, hot: false),
              ],
            ],
            footer: TradeProfileSummary(widget.market, card: true,
              key: ValueKey(('market-trade-profile-card', widget.market.contextRevision))),
          );
        },
      ),
      const SizedBox(width: 18),
      Expanded(child: content),
    ]);
  }
}
