import 'package:flutter/material.dart';

import 'marketplace_copy.dart';
import 'marketplace_port.dart';
import 'marketplace_time.dart';
import 'marketplace_trade_copy.dart';
import 'marketplace_surfaces.dart';

bool tradeReceiptExpired(MarketRow row, {DateTime? now}) =>
    ScmReceiptCountdown(row['receiptDeadline'], now ?? DateTime.now()).expired;

bool tradeReportExpired(MarketRow row, {DateTime? now}) {
  final created = scmInstant(row['createTime']);
  // SCM refuses only when whole days since creation > 7 (8 full days).
  return created != null &&
      !(now ?? DateTime.now()).isBefore(created.add(const Duration(days: 8)));
}

bool tradeCanReport(MarketRow row, {DateTime? now}) =>
    ['buyer', 'seller'].contains(row['actorRole']) &&
    scmInstant(row['createTime']) != null &&
    !tradeReportExpired(row, now: now) && row['hasReported'] != true;

DateTime? tradeApproximateShipment(MarketRow row) =>
    scmInstant(row['receiptDeadline'])?.subtract(const Duration(hours: 48));

MarketRow mergeTradeDetail(MarketRow next, MarketRow? previous) {
  if (previous == null ||
      previous['transactionNumber'] != next['transactionNumber']) {
    return next;
  }
  return {
    ...previous,
    ...next,
    if (next['displayType'] == 2 && marketNumber(next['amount']) == 0 &&
        marketNumber(previous['amount']) != null) 'amount': previous['amount'],
    // Detail report joins are not scoped to the reporter.
    if (previous.containsKey('hasReported')) 'hasReported': previous['hasReported'],
    if (previous.containsKey('reportHandleStatus'))
      'reportHandleStatus': previous['reportHandleStatus'],
  };
}

String tradeQuantity(BuildContext context, MarketRow row) =>
    row['displayType'] == 2
        ? tradeText(context, '× {n} 套', {'n': '${row['number'] ?? ''}'})
        : '×${row['number'] ?? ''}';

String tradeReportStatus(MarketRow row) => switch (row['reportHandleStatus']) {
  0 => '待处理',
  1 => '处理中',
  2 => '成立',
  3 => '不成立',
  _ => '已举报',
};

/// itemDetails are the listing creator's provided goods, even on a buy listing.
(List<MarketRow>, List<MarketRow>) tradeExchange(MarketRow row) {
  final provided = marketRows(row['itemDetails']);
  final wanted = marketRows(row['wantedItems']);
  final owner = (row['creatorType'] == 0 && row['actorRole'] == 'buyer') ||
      (row['creatorType'] == 1 && row['actorRole'] == 'seller');
  return owner ? (provided, wanted) : (wanted, provided);
}

class TradeContents extends StatelessWidget {
  const TradeContents(this.row, {super.key});
  final MarketRow row;

  @override
  Widget build(BuildContext context) {
    final provided = marketRows(row['itemDetails']);
    final wanted = marketRows(row['wantedItems']);
    if (provided.isEmpty && wanted.isEmpty) return const SizedBox.shrink();
    if (row['displayType'] != 2 && row['displayType'] != 3) {
      return const SizedBox.shrink();
    }
    Widget section(String title, List<MarketRow> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tradeText(context, title)),
        for (final item in items)
          Text('${marketName(item, marketLocale(context))}'
              '${marketNumber(item['quantity']) == null ? '' : ' × ${item['quantity']}'}'),
      ],
    );
    final (give, receive) = tradeExchange(row);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: MarketSurface(
        padding: const EdgeInsets.all(12),
        child: row['displayType'] == 2
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                section('清单内容', provided),
                Text(tradeQuantity(context, row)),
              ])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: section('你给出', give)),
                const SizedBox(width: 12),
                Expanded(child: section('你收到', receive)),
              ]),
      ),
    );
  }
}