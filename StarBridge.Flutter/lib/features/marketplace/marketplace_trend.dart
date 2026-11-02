// 走势页 layout A (user 2026-10-28; preview TradingHall/trend-page.html):
// a summary strip, the chart card (title, legend that hides a line, unit,
// 7/30/60-day range) and the daily detail beside it on wide windows, under
// it on narrow ones. "No buy" is said in words, and a range without any buy
// listing hides the buy line and column instead of a column of dashes.
import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_copy.dart';
import 'marketplace_diagonal.dart' show MarketHeadingMark, MarketSlantDivider;
import 'marketplace_port.dart';
import 'marketplace_trend_chart.dart';
import 'marketplace_trend_copy.dart';
import 'marketplace_unified.dart';
import 'marketplace_widgets.dart';

class MarketplaceTrend extends StatefulWidget {
  const MarketplaceTrend(this.rows, {super.key});
  final List<MarketRow> rows;
  @override
  State<MarketplaceTrend> createState() => _MarketplaceTrendState();
}

class _MarketplaceTrendState extends State<MarketplaceTrend> {
  int days = 60;
  bool hideSell = false, hideBuy = false, allRows = false;

  static num? _price(Object? v) {
    final n = marketNumber(v);
    return n == null || n <= 0 ? null : n;
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.rows;
    final hasAny = all.any(
      (r) => _price(r['sellPrice']) != null || _price(r['buyPrice']) != null,
    );
    if (!hasAny) return MarketNotice(marketText(context, 'noTrend'));
    final rows = all.length > days ? all.sublist(all.length - days) : all;
    final dates = [for (final r in rows) r['date']?.toString() ?? ''];
    final sell = [for (final r in rows) _price(r['sellPrice'])];
    final buy = [for (final r in rows) _price(r['buyPrice'])];
    final hasBuy = buy.any((v) => v != null);
    final chart = _ChartCard(
      header: _header(context, hasBuy),
      chart: MarketTrendChart(
        dates: dates,
        sell: sell,
        buy: buy,
        showSell: !hideSell,
        showBuy: hasBuy && !hideBuy,
      ),
    );
    final table = _DailyTable(
      rows: rows,
      hasBuy: hasBuy,
      shown: allRows ? rows.length : 10,
      toggle: rows.length > 10
          ? () => setState(() => allRows = !allRows)
          : null,
      all: allRows,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Strip(sell: sell, days: rows.length),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 900
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: chart),
                    const SizedBox(width: 14),
                    SizedBox(width: 360, child: table),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    chart,
                    const SizedBox(height: 14),
                    // Compact under the chart: numbers stay near their dates.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: table,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, bool hasBuy) {
    final t = context.tokens;
    Widget legend(
      String key,
      Color color,
      bool off,
      VoidCallback? onTap, {
      bool dashed = false,
    }) {
      final face = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 2,
            child: dashed
                ? Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        Container(width: 4, height: 2, color: color),
                        if (i < 2) const SizedBox(width: 2),
                      ],
                    ],
                  )
                : ColoredBox(color: color),
          ),
          const SizedBox(width: 6),
          Text(
            trendText(context, key),
            style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
          ),
        ],
      );
      if (onTap == null) return Opacity(opacity: .45, child: face);
      return Opacity(
        opacity: off ? .45 : 1,
        child: MergeSemantics(
          child: Semantics(
            toggled: !off,
            child: marketButtonAction(
              key: ValueKey(('market-trend-legend', key)),
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: face,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MarketHeadingMark(),
              const SizedBox(width: 8),
              Text(
                trendText(context, 'title'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          legend(
            'sell',
            t.colors.accent,
            hideSell,
            () => setState(() => hideSell = !hideSell),
          ),
          hasBuy
              ? legend(
                  'buy',
                  MarketTrendColors.buy,
                  hideBuy,
                  () => setState(() => hideBuy = !hideBuy),
                  dashed: true,
                )
              : legend(
                  'noBuyInRange',
                  MarketTrendColors.buy,
                  true,
                  null,
                  dashed: true,
                ),
          Text(
            trendText(context, 'unit'),
            style: TextStyle(fontSize: 11, color: t.colors.textDisabled),
          ),
          MarketSubTabs(key: const Key('market-trend-range'), [
            for (final n in const [7, 30, 60])
              MarketSubTab(
                trendText(context, 'days', n: n),
                selected: days == n,
                onTap: () => setState(() {
                  days = n;
                  allRows = false;
                }),
                controlKey: ValueKey(('market-trend-range', n)),
              ),
          ]),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.header, required this.chart});
  final Widget header, chart;
  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 0), child: chart),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
          child: Text(
            trendText(context, 'note'),
            style: TextStyle(
              fontSize: 11,
              color: context.tokens.colors.textDisabled,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.tokens.surfaces.panel.fill,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: context.tokens.surfaces.panel.border),
    ),
    child: child,
  );
}

class _Strip extends StatelessWidget {
  const _Strip({required this.sell, required this.days});
  final List<num?> sell;
  final int days;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final known = sell.whereType<num>().toList();
    if (known.isEmpty) return const SizedBox.shrink();
    num? change(int span) {
      final now = known.last;
      final from = sell.length > span
          ? sell[sell.length - 1 - span]
          : sell.first;
      final base = from ?? known.first;
      return base == 0 ? null : (now - base) / base * 100;
    }

    Widget tile(String label, Widget value) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 20, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: t.colors.textSecondary),
          ),
          const SizedBox(height: 2),
          value,
        ],
      ),
    );
    final mono = TextStyle(
      fontFamily: t.typography.monoFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    Widget pct(num? v) => v == null
        ? Text('—', style: mono)
        : Text(
            v.abs() < .05
                ? trendText(context, 'flat')
                : '${v > 0 ? '▲' : '▼'} ${v.abs().toStringAsFixed(1)}%',
            style: mono.copyWith(
              color: v.abs() < .05
                  ? t.colors.textSecondary
                  : v > 0
                  ? t.colors.success
                  : t.colors.danger,
            ),
          );
    final avg = known.reduce((a, b) => a + b) / known.length;
    final tiles = [
      tile(
        trendText(context, 'now'),
        Text(marketMoney(known.last), style: mono),
      ),
      tile(trendText(context, 'change', n: 7), pct(change(7))),
      if (days > 7)
        tile(trendText(context, 'change', n: days), pct(change(days - 1))),
      tile(
        trendText(context, 'low', n: days),
        Text(marketMoney(known.reduce((a, b) => a < b ? a : b)), style: mono),
      ),
      tile(
        trendText(context, 'high', n: days),
        Text(marketMoney(known.reduce((a, b) => a > b ? a : b)), style: mono),
      ),
      tile(
        trendText(context, 'avg', n: days),
        Text(marketMoney(avg.round()), style: mono),
      ),
    ];
    return _Card(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (i, w) in tiles.indexed) ...[
            if (i > 0) const MarketSlantDivider(height: 28),
            w,
          ],
        ],
      ),
    );
  }
}

class _DailyTable extends StatelessWidget {
  const _DailyTable({
    required this.rows,
    required this.hasBuy,
    required this.shown,
    required this.toggle,
    required this.all,
  });
  final List<MarketRow> rows;
  final bool hasBuy, all;
  final int shown;
  final VoidCallback? toggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mono = TextStyle(
      fontFamily: t.typography.monoFamily,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final muted = TextStyle(fontSize: 11.5, color: t.colors.textDisabled);
    final head = TextStyle(fontSize: 11, color: t.colors.textDisabled);
    Widget price(Object? v, String missing) {
      final n = marketNumber(v);
      return n == null || n <= 0
          ? Text(missing, style: muted, textAlign: TextAlign.right)
          : Text.rich(
              TextSpan(
                text: marketMoney(n),
                children: [
                  TextSpan(
                    text: ' UEC',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: t.colors.textDisabled,
                    ),
                  ),
                ],
              ),
              style: mono,
              textAlign: TextAlign.right,
            );
    }

    Widget change(int i) {
      final now = marketNumber(rows[i]['sellPrice']),
          before = i > 0 ? marketNumber(rows[i - 1]['sellPrice']) : null;
      if (now == null || now <= 0 || before == null || before <= 0) {
        return const SizedBox.shrink();
      }
      final c = (now - before) / before * 100;
      final flat = c.abs() < .05;
      final color = flat
          ? t.colors.textSecondary
          : c > 0
          ? t.colors.success
          : t.colors.danger;
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: flat ? null : color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            flat
                ? trendText(context, 'flat')
                : '${c > 0 ? '▲' : '▼'} ${c.abs().toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 11, color: color),
          ),
        ),
      );
    }

    final count = shown.clamp(0, rows.length);
    final widths = hasBuy
        ? const {
            0: FixedColumnWidth(52),
            2: FlexColumnWidth(.9),
            3: FixedColumnWidth(76),
          }
        : const {0: FixedColumnWidth(52), 2: FixedColumnWidth(76)};
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 6),
            child: Row(
              children: [
                const MarketHeadingMark(),
                const SizedBox(width: 8),
                Text(
                  trendText(context, 'daily'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(trendText(context, 'recent', n: count), style: head),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Table(
              key: const Key('market-trend-table'),
              columnWidths: widths,
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    Text(trendText(context, 'date'), style: head),
                    Text(
                      trendText(context, 'sellShort'),
                      style: head,
                      textAlign: TextAlign.right,
                    ),
                    if (hasBuy)
                      Text(
                        trendText(context, 'buyShort'),
                        style: head,
                        textAlign: TextAlign.right,
                      ),
                    Text(
                      trendText(context, 'vsPrev'),
                      style: head,
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
                for (var i = rows.length - 1; i >= rows.length - count; i--)
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: t.colors.textSecondary.withValues(alpha: .08),
                        ),
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          (rows[i]['date']?.toString() ?? '—').replaceFirst(
                            RegExp(r'^\d{4}-'),
                            '',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: t.colors.textSecondary,
                          ),
                        ),
                      ),
                      price(rows[i]['sellPrice'], trendText(context, 'noSell')),
                      if (hasBuy)
                        price(rows[i]['buyPrice'], trendText(context, 'noBuy')),
                      change(i),
                    ],
                  ),
              ],
            ),
          ),
          if (toggle != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Center(
                child: marketButtonAction(
                  key: const Key('market-trend-all'),
                  TextButton(
                    onPressed: toggle,
                    child: Text(
                      all
                          ? trendText(context, 'less')
                          : trendText(context, 'all', n: rows.length),
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }
}
