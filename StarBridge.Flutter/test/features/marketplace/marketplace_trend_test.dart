// 走势页 layout A (user 2026-10-28, backlog #6): units on the axis, a legend
// that hides a line, "无求购" in words (or no buy column when the range has
// none), a 7/30/60-day range, the daily table beside the chart, and a hover
// tooltip.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trend.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trend_chart.dart';

import '../friends/social_layout_test.dart' show size;
import 'marketplace_slice4_test.dart' show preview;

List<MarketRow> _rows({bool buy = true}) {
  final start = DateTime(2026, 8, 30);
  return [
    for (var i = 0; i < 60; i++)
      {
        'date': start.add(Duration(days: i)).toIso8601String().substring(0, 10),
        'sellPrice': i < 24 ? 1000000 : 1840000,
        'buyPrice': buy && i >= 11 && i <= 17 ? 1150000 : 0,
      },
  ];
}

Future<void> _pump(
  WidgetTester tester,
  List<MarketRow> rows, {
  double width = 1400,
}) async {
  size(tester, Size(width + 40, 1100));
  await tester.pumpWidget(
    preview(
      SizedBox(
        width: width,
        child: SingleChildScrollView(child: MarketplaceTrend(rows)),
      ),
      AppearanceMode.dark,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide: chart and daily table side by side; no dashes for buy', (
    tester,
  ) async {
    await _pump(tester, _rows());
    final chart = tester.getRect(find.byKey(const Key('market-trend-chart')));
    final table = tester.getRect(find.byKey(const Key('market-trend-table')));
    expect(
      table.left,
      greaterThan(chart.right),
      reason: 'table beside the chart',
    );
    expect(table.top, lessThan(chart.bottom));
    expect(find.text('出售挂单均价'), findsOneWidget);
    expect(find.text('求购挂单均价'), findsOneWidget);
    expect(find.text('单位 UEC'), findsOneWidget);
    expect(find.text('无求购'), findsWidgets, reason: 'missing buy said in words');
    expect(find.text('—'), findsNothing);
    expect(find.text('60 天涨跌'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a range without buy listings hides the buy column and line', (
    tester,
  ) async {
    await _pump(tester, _rows(buy: false));
    expect(find.text('这段时间没有求购'), findsOneWidget);
    expect(find.text('求购均价'), findsNothing);
    expect(find.text('无求购'), findsNothing);
    final chart = tester.widget<MarketTrendChart>(
      find.byType(MarketTrendChart),
    );
    expect(chart.showBuy, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legend hides a line; the range trims the days', (tester) async {
    await _pump(tester, _rows());
    await tester.tap(
      find.byKey(const ValueKey(('market-trend-legend', 'buy'))),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MarketTrendChart>(find.byType(MarketTrendChart)).showBuy,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey(('market-trend-range', 7))));
    await tester.pumpAndSettle();
    final chart = tester.widget<MarketTrendChart>(
      find.byType(MarketTrendChart),
    );
    expect(chart.dates, hasLength(7));
    expect(chart.dates.last, '2026-10-28');
    expect(find.text('7 天涨跌'), findsOneWidget);
    expect(
      find.text('这段时间没有求购'),
      findsOneWidget,
      reason: 'the last 7 days have no buy',
    );
    expect(find.byKey(const Key('market-trend-all')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the daily table shows 10 days, then all of them', (
    tester,
  ) async {
    await _pump(tester, _rows());
    expect(find.text('最近 10 天'), findsOneWidget);
    await tester.tap(find.byKey(const Key('market-trend-all')));
    await tester.pumpAndSettle();
    expect(find.text('最近 60 天'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hovering shows that day\'s sell and buy averages', (
    tester,
  ) async {
    await _pump(tester, _rows());
    final rect = tester.getRect(find.byKey(const Key('market-trend-chart')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    // Day 14 of 60 (09-13) has both averages.
    await mouse.moveTo(
      Offset(12 + (rect.width - 90) * 14 / 59 + rect.left, rect.center.dy),
    );
    await tester.pump();
    final tip = find.byKey(const Key('market-trend-tip'));
    expect(tip, findsOneWidget);
    expect(
      find.descendant(of: tip, matching: find.text('2026-09-13')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tip, matching: find.text('1,000,000')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tip, matching: find.text('1,150,000')),
      findsOneWidget,
    );
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(tip, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow: the table goes under the chart', (tester) async {
    await _pump(tester, _rows(), width: 800);
    final chart = tester.getRect(find.byKey(const Key('market-trend-chart')));
    final table = tester.getRect(find.byKey(const Key('market-trend-table')));
    expect(table.top, greaterThan(chart.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no prices at all: the old notice', (tester) async {
    await _pump(tester, [
      {'date': '2026-10-28', 'sellPrice': 0, 'buyPrice': 0},
    ]);
    expect(find.text('还没有价格记录'), findsOneWidget);
    expect(find.byType(MarketTrendChart), findsNothing);
  });
}
