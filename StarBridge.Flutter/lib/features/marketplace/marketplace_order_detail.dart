import 'marketplace_trade_chat_entry.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_details.dart';
import 'marketplace_diagonal.dart';
import 'marketplace_hall_mine.dart' show marketSideColor;
import 'marketplace_hall_reads.dart';
import 'marketplace_port.dart';
import 'marketplace_surfaces.dart' show MarketSurface, marketLine;
import 'marketplace_unified.dart';
import 'marketplace_widgets.dart';

const _copy = <String, List<String>>{
  'sell': ['出售', '出售', 'Selling'],
  'buy': ['求购', '求購', 'Buying'],
  'barter': ['以物易物', '以物易物', 'Barter'],
  'checklist': ['清单', '清單', 'Bundle'],
  'ongoing': ['有进行中的交易', '有進行中的交易', 'Trade in progress'],
  'unitPrice': ['单价', '單價', 'Unit price'],
  'left': ['剩余', '剩餘', 'Left'],
  'total': ['全部总价', '全部總價', 'All of it'],
  'market': ['行情对比', '行情對比', 'Against the market'],
  'bestSell': ['当前最低卖价', '目前最低賣價', 'Lowest ask now'],
  'bestBuy': ['当前最高收购', '目前最高收購', 'Highest bid now'],
  'reference': ['近期均价', '近期均價', 'Recent average'],
  'isBest': ['就是当前最优价', '就是目前最優價', 'This is the best price'],
  'above': ['高', '高', 'above'],
  'below': ['低', '低', 'below'],
  'trader': ['交易方', '交易方', 'Trader'],
  'tradeTime': ['交易时段', '交易時段', 'Trading hours'],
  'openNow': ['现在可交易', '現在可交易', 'Trading now'],
  'closedNow': ['不在交易时段', '不在交易時段', 'Outside trading hours'],
  'place': ['交易地点', '交易地點', 'Location'],
  'contents': ['清单内容', '清單內容', 'In this bundle'],
  'offered': ['提供', '提供', 'Offers'],
  'wanted': ['想要', '想要', 'Wants'],
  'remark': ['备注', '備註', 'Note'],
  'others': ['同物品其他报价', '同物品其他報價', 'Other offers for this item'],
  'noOthers': ['暂时没有其他报价', '暫時沒有其他報價', 'No other offers right now'],
  'loading': ['读取中…', '讀取中…', 'Loading…'],
  'unavailable': ['暂不可用', '暫不可用', 'Unavailable'],
  'order': ['订单号', '訂單號', 'Order'],
  'published': ['发布', '發布', 'Published'],
};

String _t(BuildContext context, String key) {
  final values = _copy[key]!;
  final locale = marketLocale(context);
  return values[locale == 'en'
      ? 2
      : locale == 'hant'
      ? 1
      : 0];
}

/// The body of an order's detail sheet: what it is, what it costs against the
/// market, who trades and when, what is inside, and the item's other offers.
/// Reads are public and lazy; a failed read only hides its own figure.
class MarketOrderDetail extends StatefulWidget {
  const MarketOrderDetail(this.c, this.row, {super.key});
  final MarketplaceController c;
  final MarketRow row;
  @override
  State<MarketOrderDetail> createState() => _OrderDetailState();
}

class _OrderDetailState extends State<MarketOrderDetail> {
  MarketRow get row => widget.row;
  MarketRead? _trend, _offers;
  bool _offersFailed = false;

  int? get _id => marketItemId(row);
  bool get _single => row['displayType'] != 2 && row['displayType'] != 3;
  int get _side => row['creatorType'] == 0 ? 0 : 1;

  @override
  void initState() {
    super.initState();
    final id = _id;
    if (id == null || !_single) return;
    unawaited(widget.c.ensureBestPrices([(id, _side)]));
    unawaited(_read());
  }

  Future<void> _read() async {
    final port = widget.c.port;
    final id = _id!;
    Future<MarketRead?> quiet(Future<MarketRead> read) async {
      try {
        return await read;
      } on Object {
        return null;
      }
    }

    final results = await Future.wait([
      quiet(port.read('trend', id: id)),
      quiet(port.read('offers', id: id, side: _side)),
    ]);
    if (!mounted) return;
    setState(() {
      _trend = results[0];
      _offers = results[1];
      _offersFailed = results[1] == null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) => ListView(
      padding: EdgeInsets.zero,
      children: [
        _hero(context),
        const SizedBox(height: 14),
        _price(context),
        if (_single && _id != null) _market(context),
        _trader(context),
        if (row['displayType'] == 2 || row['displayType'] == 3)
          _contents(context),
        if (row['remark'] case final String note when note.trim().isNotEmpty)
          _section(
            context,
            'remark',
            Text(
              note.trim(),
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        if (_single && _id != null) _others(context),
        _meta(context),
      ],
    ),
  );

  Widget _section(BuildContext context, String title, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Transform.scale(
              scale: .75,
              alignment: Alignment.centerLeft,
              child: MarketHeadingMark(),
            ),
            const SizedBox(width: 6),
            Text(
              _t(context, title),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.tokens.colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );

  Widget _hero(BuildContext context) {
    final t = context.tokens;
    final side = row['displayType'] == 3
        ? 'barter'
        : row['creatorType'] == 0
        ? 'buy'
        : 'sell';
    final quality = marketQuality(row);
    final best = _id == null || !_single
        ? null
        : widget.c.bestPrice(_id!, _side);
    final price = marketNumber(row['unitPrice']);
    final leading =
        best != null &&
        price != null &&
        (_side == 0 ? price >= best : price <= best);
    final tags = [
      MarketSlantTag(
        _t(context, side),
        color: marketSideColor(context, side),
        solid: true,
      ),
      if (marketIsChecklist(row) && side != 'barter')
        MarketSlantTag(_t(context, 'checklist'), color: t.colors.textSecondary),
      if (quality != null) MarketQualityBadge(row, prefixed: true),
      if (leading)
        MarketSlantTag(
          marketText(context, _side == 0 ? 'tagHighestBid' : 'tagLowest'),
          color: t.colors.success,
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          height: 104,
          child: MarketArt(
            marketThumbnail(row),
            category: marketCategoryOf(row),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 4, runSpacing: 4, children: tags),
              const SizedBox(height: 8),
              Text(
                marketName(row, marketLocale(context)),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  fontWeight: t.typography.emphasisWeight,
                ),
              ),
              if (row['hasOngoingTransactions'] == true) ...[
                const SizedBox(height: 6),
                MarketSlantTag(_t(context, 'ongoing'), color: t.colors.warning),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _price(BuildContext context) {
    final t = context.tokens;
    final quantity = marketNumber(
      row['remainingQuantity'] ?? row['availableQuantity'],
    );
    final price = marketNumber(row['unitPrice']);
    if (row['displayType'] == 3) {
      return MarketSurface(
        padding: EdgeInsets.zero,
        child: MarketStatStrip([
          MarketStat(
            _t(context, 'unitPrice'),
            _t(context, 'barter'),
            mono: false,
          ),
          MarketStat(
            _t(context, 'left'),
            quantity == null ? '—' : '×${quantity.toInt()}',
          ),
        ]),
      );
    }
    return MarketSurface(
      padding: EdgeInsets.zero,
      child: MarketStatStrip([
        MarketStat(
          _t(context, 'unitPrice'),
          price == null ? '—' : '¤ ${marketMoney(price)}',
          color: MarketplacePalette.gold,
        ),
        MarketStat(
          _t(context, 'left'),
          quantity == null ? '—' : '×${quantity.toInt()}',
        ),
        if (price != null && quantity != null && quantity > 1)
          MarketStat(
            _t(context, 'total'),
            '¤ ${marketPrice(context, price * quantity)}',
            color: t.colors.textPrimary,
          ),
      ]),
    );
  }

  Widget _market(BuildContext context) {
    final t = context.tokens;
    final price = marketNumber(row['unitPrice']);
    final best = widget.c.bestPrice(_id!, _side);
    final trend = _trend?.data;
    final reference = marketNumber(
      trend?[_side == 0 ? 'buyVWAP' : 'sellVWAP'] ?? trend?['overallPrice'],
    );
    Widget line(String label, num? value, {bool best = false}) {
      String? note;
      Color? tone;
      if (value != null && price != null && value > 0) {
        final diff = (price - value) / value * 100;
        if (best && diff.abs() < .05) {
          note = _t(context, 'isBest');
          tone = t.colors.success;
        } else if (diff.abs() >= .05) {
          final higher = diff > 0;
          note = marketLocale(context) == 'en'
              ? '${diff.abs().toStringAsFixed(1)}% ${_t(context, higher ? 'above' : 'below')}'
              : '${_t(context, higher ? 'above' : 'below')} ${diff.abs().toStringAsFixed(1)}%';
          // Good for the person looking: a cheaper ask, a higher bid.
          final good = _side == 0 ? higher : !higher;
          tone = good ? t.colors.success : t.colors.warning;
        }
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12.5, color: t.colors.textSecondary),
              ),
            ),
            Text(
              value == null
                  ? _t(context, 'loading')
                  : '¤ ${marketMoney(value)}',
              style: TextStyle(
                fontFamily: value == null ? null : t.typography.monoFamily,
                fontSize: 13,
                color: value == null
                    ? t.colors.textSecondary
                    : MarketplacePalette.gold,
              ),
            ),
            if (note != null) ...[
              const SizedBox(width: 8),
              MarketSlantTag(note, color: tone!),
            ],
          ],
        ),
      );
    }

    return _section(
      context,
      'market',
      Column(
        children: [
          line(
            _t(context, _side == 0 ? 'bestBuy' : 'bestSell'),
            best,
            best: true,
          ),
          if (_trend != null) line(_t(context, 'reference'), reference),
        ],
      ),
    );
  }

  Widget _trader(BuildContext context) {
    final t = context.tokens;
    final open = marketTradeOpenNow(row);
    final hours = marketTradeTime(context, row);
    final place = widget.c.locationLabel(row);
    Widget fact(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              _t(context, label),
              style: TextStyle(fontSize: 12.5, color: t.colors.textSecondary),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
    return _section(
      context,
      'trader',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarketTrader(row),
          // 0.7.2 G9: SCM trade chat with the order's owner, order attached.
          if (widget.c.tradeChat != null &&
              !marketIsMine(row) &&
              row['orderNumber'] is String)
            Align(
              alignment: Alignment.centerLeft,
              child: marketButtonAction(
                TextButton(
                  onPressed: () => contactOrderOwner(context, widget.c, row),
                  child: Text(
                    tradeChatEntryText(
                      context,
                      row['creatorType'] == 0 ? '联系买家' : '联系卖家',
                    ),
                  ),
                ),
                key: const Key('market-order-contact'),
              ),
            ),
          const SizedBox(height: 6),
          fact(
            'tradeTime',
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(hours, style: const TextStyle(fontSize: 13)),
                if (open != null)
                  MarketSlantTag(
                    _t(context, open ? 'openNow' : 'closedNow'),
                    color: open ? t.colors.success : t.colors.textSecondary,
                  ),
              ],
            ),
          ),
          fact(
            'place',
            Text(
              place.isNotEmpty ? place : marketLocation(context, row),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemLine(BuildContext context, MarketRow item) {
    final t = context.tokens;
    final price = marketNumber(item['unitPrice']);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: marketLine(context))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: MarketArt(
              item['thumbnailUrl'] as String?,
              category: marketCategoryOf(item),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  marketName(item, marketLocale(context)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                if (marketQuality(item) != null) ...[
                  const SizedBox(height: 3),
                  MarketQualityBadge(item),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '×${marketNumber(item['quantity'])?.toInt() ?? 1}',
                style: TextStyle(fontSize: 12.5, color: t.colors.textSecondary),
              ),
              if (price != null)
                Text(
                  '¤ ${marketPrice(context, price)}',
                  style: TextStyle(
                    fontFamily: t.typography.monoFamily,
                    fontSize: 12,
                    color: MarketplacePalette.gold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contents(BuildContext context) {
    final offered = marketRows(row['items']);
    final wanted = marketRows(row['wantedItems']);
    if (row['displayType'] == 3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(
            context,
            'offered',
            Column(children: [for (final i in offered) _itemLine(context, i)]),
          ),
          _section(
            context,
            'wanted',
            Column(children: [for (final i in wanted) _itemLine(context, i)]),
          ),
        ],
      );
    }
    return _section(
      context,
      'contents',
      Column(children: [for (final i in offered) _itemLine(context, i)]),
    );
  }

  Widget _others(BuildContext context) {
    final t = context.tokens;
    final rows = (_offers?.rows ?? const <MarketRow>[])
        .where((r) => r['orderNumber'] != row['orderNumber'])
        .take(5)
        .toList();
    final Widget body;
    if (_offers == null) {
      body = Text(
        _t(context, _offersFailed ? 'unavailable' : 'loading'),
        style: TextStyle(fontSize: 12.5, color: t.colors.textSecondary),
      );
    } else if (rows.isEmpty) {
      body = Text(
        _t(context, 'noOthers'),
        style: TextStyle(fontSize: 12.5, color: t.colors.textSecondary),
      );
    } else {
      body = Column(
        children: [
          for (final (i, r) in rows.indexed)
            Container(
              key: ValueKey(('market-order-other', r['orderNumber'] ?? i)),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: marketLine(context))),
              ),
              child: Row(
                children: [
                  Expanded(child: MarketTrader(r, compact: true)),
                  const SizedBox(width: 8),
                  Text(
                    '×${marketNumber(r['remainingQuantity'] ?? r['availableQuantity'])?.toInt() ?? '—'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: t.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: Text(
                      '¤ ${marketPrice(context, r['unitPrice'])}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: t.typography.monoFamily,
                        fontSize: 13,
                        color: MarketplacePalette.gold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return _section(context, 'others', body);
  }

  Widget _meta(BuildContext context) {
    final t = context.tokens;
    final style = TextStyle(fontSize: 11.5, color: t.colors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (row['orderNumber'] case final Object number)
            SelectableText(
              '${_t(context, 'order')} $number',
              style: style.copyWith(fontFamily: t.typography.monoFamily),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${_t(context, 'published')} ', style: style),
              DefaultTextStyle.merge(
                style: style,
                child: MarketPublished(row['createTime']),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
