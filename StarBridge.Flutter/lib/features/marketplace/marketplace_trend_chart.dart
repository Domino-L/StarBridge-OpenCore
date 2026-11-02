// 走势图 (layout A, user 2026-10-28; preview TradingHall/trend-page.html):
// the sell average as a line over a soft area, the buy average dashed, no
// per-day dots, the latest price tagged on the right axis, faint dashed
// grid, and a crosshair with a tooltip on hover.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_copy.dart' show marketLocale;
import 'marketplace_trend_copy.dart';
import 'marketplace_widgets.dart' show marketMoney;

/// Axis and tag label for a price: 万 in Chinese, k/M in English.
String marketTrendAxis(BuildContext context, num value, {int digits = 0}) {
  if (marketLocale(context) == 'en') {
    return value >= 1e6
        ? '${(value / 1e6).toStringAsFixed(digits == 0 ? 1 : 2)}M'
        : '${(value / 1e3).toStringAsFixed(0)}k';
  }
  return '${(value / 1e4).toStringAsFixed(digits)}万';
}

class MarketTrendChart extends StatefulWidget {
  const MarketTrendChart({
    required this.dates,
    required this.sell,
    required this.buy,
    required this.showSell,
    required this.showBuy,
    this.height = 300,
    super.key,
  });
  final List<String> dates;
  final List<num?> sell, buy;
  final bool showSell, showBuy;
  final double height;

  @override
  State<MarketTrendChart> createState() => _MarketTrendChartState();
}

class _MarketTrendChartState extends State<MarketTrendChart> {
  int? hover;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = (
      sell: t.colors.accent,
      buy: MarketTrendColors.buy,
      grid: t.colors.textSecondary.withValues(alpha: .14),
      label: t.colors.textSecondary.withValues(alpha: .75),
      ink: MarketTrendColors.onTag,
      ground: t.surfaces.panel.fill,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final geometry = _Geometry(
          Size(box.maxWidth, widget.height),
          widget.dates.length,
        );
        return MouseRegion(
          onHover: (event) =>
              setState(() => hover = geometry.indexAt(event.localPosition.dx)),
          onExit: (_) => setState(() => hover = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                key: const Key('market-trend-chart'),
                size: Size(box.maxWidth, widget.height),
                painter: _TrendPainter(
                  widget,
                  geometry,
                  hover,
                  colors,
                  (v, {int digits = 0}) =>
                      marketTrendAxis(context, v, digits: digits),
                  TextStyle(
                    fontFamily: t.typography.monoFamily,
                    // The mono face has no CJK glyphs (万); fall back like body text.
                    fontFamilyFallback: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.fontFamilyFallback,
                    fontSize: 10.5,
                    color: colors.label,
                  ),
                ),
              ),
              if (hover case final i?)
                Positioned(
                  top: 6,
                  left: geometry.x(i) > box.maxWidth * .6
                      ? geometry.x(i) - 230
                      : geometry.x(i) + 14,
                  child: _TrendTip(widget, i),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Trend line colours with no token of their own.
abstract final class MarketTrendColors {
  static const buy = MarketplacePalette.trendBuy;
  static const onTag = MarketplacePalette.onAccent;
}

class _Geometry {
  _Geometry(this.size, this.count);
  final Size size;
  final int count;
  static const left = 12.0, right = 78.0, top = 14.0, bottom = 26.0;
  double get width => size.width - left - right;
  double get height => size.height - top - bottom;
  double x(int i) =>
      count < 2 ? left + width / 2 : left + width * i / (count - 1);
  int indexAt(double dx) => count < 2
      ? 0
      : ((dx - left) / width * (count - 1)).round().clamp(0, count - 1);
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(
    this.chart,
    this.g,
    this.hover,
    this.colors,
    this.label,
    this.style,
  );
  final MarketTrendChart chart;
  final _Geometry g;
  final int? hover;
  final ({
    Color sell,
    Color buy,
    Color grid,
    Color label,
    Color ink,
    Color ground,
  })
  colors;
  final String Function(num, {int digits}) label;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      if (chart.showSell) ...chart.sell,
      if (chart.showBuy) ...chart.buy,
    ].whereType<num>().where((v) => v > 0).map((v) => v.toDouble()).toList();
    if (values.isEmpty) return;
    var low = values.reduce(math.min), high = values.reduce(math.max);
    final step = _niceStep(
      high == low ? math.max(high * .1, 1) : (high - low) / 4,
    );
    low = ((low - step * .3) / step).floorToDouble() * step;
    high = ((high + step * .3) / step).ceilToDouble() * step;
    if (low < 0) low = 0;
    double y(num v) =>
        _Geometry.top + g.height * (1 - (v - low) / (high - low));

    // Faint dashed grid with right-side labels.
    final gridPaint = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    for (var v = low; v <= high + 1; v += step) {
      final gy = y(v);
      for (var x = _Geometry.left; x < size.width - _Geometry.right; x += 6) {
        canvas.drawLine(
          Offset(x, gy),
          Offset(math.min(x + 2, size.width - _Geometry.right), gy),
          gridPaint,
        );
      }
      _text(
        canvas,
        label(v),
        Offset(size.width - _Geometry.right + 10, gy - 7),
      );
    }
    // Five dates at most, skipping one that would touch the last.
    final n = chart.dates.length;
    final ticks = {
      0,
      n ~/ 4,
      n ~/ 2,
      n * 3 ~/ 4,
      n - 1,
    }.where((i) => i >= 0 && i < n).toList()..sort();
    for (final i in ticks) {
      if (i != n - 1 && i != 0 && g.x(n - 1) - g.x(i) < 56) continue;
      final text = chart.dates[i].length >= 10
          ? chart.dates[i].substring(5)
          : chart.dates[i];
      final painter = _layout(text);
      final dx = i == 0
          ? g.x(i)
          : i == n - 1
          ? g.x(i) - painter.width
          : g.x(i) - painter.width / 2;
      painter.paint(canvas, Offset(dx, size.height - 16));
    }

    if (chart.showSell) {
      for (final run in _runs(chart.sell)) {
        final line = _line(run, y);
        final area = Path.from(line)
          ..lineTo(g.x(run.last.$1), _Geometry.top + g.height)
          ..lineTo(g.x(run.first.$1), _Geometry.top + g.height)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = ui.Gradient.linear(
              const Offset(0, _Geometry.top),
              Offset(0, _Geometry.top + g.height),
              [
                colors.sell.withValues(alpha: .28),
                colors.sell.withValues(alpha: 0),
              ],
            ),
        );
        canvas.drawPath(
          line,
          Paint()
            ..color = colors.sell.withValues(alpha: .35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawPath(
          line,
          Paint()
            ..color = colors.sell
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    if (chart.showBuy) {
      final paint = Paint()
        ..color = colors.buy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      for (final run in _runs(chart.buy)) {
        for (final metric in _line(run, y).computeMetrics()) {
          for (var d = 0.0; d < metric.length; d += 9) {
            canvas.drawPath(
              metric.extractPath(d, math.min(d + 5, metric.length)),
              paint,
            );
          }
        }
        if (run.length == 1) {
          canvas.drawCircle(
            Offset(g.x(run.first.$1), y(run.first.$2)),
            2.5,
            Paint()..color = colors.buy,
          );
        }
      }
    }

    // The latest sell price: a dot with a halo and a tag on the right axis.
    final last = chart.sell.lastIndexWhere((v) => v != null && v > 0);
    if (chart.showSell && last >= 0) {
      final p = Offset(g.x(last), y(chart.sell[last]!));
      canvas.drawCircle(
        p,
        7,
        Paint()..color = colors.sell.withValues(alpha: .18),
      );
      canvas.drawCircle(p, 3.5, Paint()..color = colors.sell);
      canvas.drawCircle(
        p,
        3.5,
        Paint()
          ..color = colors.ground
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final tagLeft = size.width - _Geometry.right + 4;
      final tag = RRect.fromRectAndRadius(
        Rect.fromLTWH(tagLeft, p.dy - 10, _Geometry.right - 8, 20),
        const Radius.circular(3),
      );
      final guide = Paint()
        ..color = colors.sell.withValues(alpha: .35)
        ..strokeWidth = 1;
      for (var x = p.dx + 6; x < tagLeft; x += 5) {
        canvas.drawLine(
          Offset(x, p.dy),
          Offset(math.min(x + 2, tagLeft), p.dy),
          guide,
        );
      }
      canvas.drawRRect(tag, Paint()..color = colors.sell);
      final text = _layout(
        label(chart.sell[last]!, digits: 1),
        style.copyWith(
          color: colors.ink,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      );
      text.paint(
        canvas,
        Offset(tag.center.dx - text.width / 2, tag.center.dy - text.height / 2),
      );
    }

    if (hover case final i?) {
      canvas.drawLine(
        Offset(g.x(i), _Geometry.top),
        Offset(g.x(i), _Geometry.top + g.height),
        Paint()
          ..color = colors.label.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
      for (final (list, color, show) in [
        (chart.sell, colors.sell, chart.showSell),
        (chart.buy, colors.buy, chart.showBuy),
      ]) {
        final v = list[i];
        if (!show || v == null || v <= 0) continue;
        canvas.drawCircle(Offset(g.x(i), y(v)), 4.5, Paint()..color = color);
        canvas.drawCircle(
          Offset(g.x(i), y(v)),
          4.5,
          Paint()
            ..color = colors.ground
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  Path _line(List<(int, num)> run, double Function(num) y) {
    final path = Path()..moveTo(g.x(run.first.$1), y(run.first.$2));
    for (final (i, v) in run.skip(1)) {
      path.lineTo(g.x(i), y(v));
    }
    return path;
  }

  static List<List<(int, num)>> _runs(List<num?> values) {
    final runs = <List<(int, num)>>[];
    var current = <(int, num)>[];
    for (final (i, v) in values.indexed) {
      if (v != null && v > 0) {
        current.add((i, v));
      } else if (current.isNotEmpty) {
        runs.add(current);
        current = [];
      }
    }
    if (current.isNotEmpty) runs.add(current);
    return runs;
  }

  static double _niceStep(num raw) {
    final p = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final n = raw / p;
    return (n <= 1
            ? 1
            : n <= 2
            ? 2
            : n <= 5
            ? 5
            : 10) *
        p;
  }

  TextPainter _layout(String text, [TextStyle? s]) => TextPainter(
    text: TextSpan(text: text, style: s ?? style),
    textDirection: TextDirection.ltr,
  )..layout();

  void _text(Canvas canvas, String text, Offset at) =>
      _layout(text).paint(canvas, at);

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.chart != chart ||
      old.hover != hover ||
      old.colors != colors ||
      old.g.size != g.size;
}

class _TrendTip extends StatelessWidget {
  const _TrendTip(this.chart, this.i);
  final MarketTrendChart chart;
  final int i;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget row(Color color, String name, num? value, String missing) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 2, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(fontSize: 11.5, color: t.colors.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          value != null && value > 0
              ? Text(
                  marketMoney(value),
                  style: TextStyle(
                    fontFamily: t.typography.monoFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Text(
                  missing,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: t.colors.textDisabled,
                  ),
                ),
        ],
      ),
    );
    final hasBuy = chart.buy.any((v) => v != null && v > 0);
    return IgnorePointer(
      child: Container(
        key: const Key('market-trend-tip'),
        width: 216,
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
        decoration: BoxDecoration(
          color: t.surfaces.panel.fill.withValues(alpha: .97),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.surfaces.panel.border),
          boxShadow: const [
            BoxShadow(
              blurRadius: 18,
              color: MarketplacePalette.trendShadow,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              chart.dates[i],
              style: TextStyle(fontSize: 11, color: t.colors.textSecondary),
            ),
            const SizedBox(height: 2),
            row(
              t.colors.accent,
              trendText(context, 'sell'),
              chart.sell[i],
              trendText(context, 'daySell'),
            ),
            if (hasBuy)
              row(
                MarketTrendColors.buy,
                trendText(context, 'buy'),
                chart.buy[i],
                trendText(context, 'dayBuy'),
              ),
          ],
        ),
      ),
    );
  }
}
