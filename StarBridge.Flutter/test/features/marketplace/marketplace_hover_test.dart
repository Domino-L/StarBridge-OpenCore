import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_banner.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hover.dart';

import 'marketplace_slice4_test.dart' show preview;

void main() {
  test('trade window opens and closes in the trader\'s own time zone', () {
    marketRememberZones([
      {'id': 901, 'offsetMinutes': 0},
    ]);
    final row = {
      'timezoneId': 901,
      'tradeStartTime': '19:00',
      'tradeEndTime': '08:00',
      'tradeTime': '[1,1,1,1,1,1,1]',
    };
    expect(marketTradeOpenNow(row, now: DateTime.utc(2026, 10, 20, 20)), isTrue);
    expect(marketTradeOpenNow(row, now: DateTime.utc(2026, 10, 20, 3)), isTrue);
    expect(marketTradeOpenNow(row, now: DateTime.utc(2026, 10, 20, 12)), isFalse);
    expect(marketTradeOpenNow({...row, 'timezoneId': 999}), isNull);
  });

  testWidgets('hover lifts the card and hangs the drawer after a pause', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      preview(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 220,
            height: 120,
            child: MarketHoverCard(
              drawerKey: const ValueKey('drawer'),
              drawer: (_) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MarketDrawerRow('比最低价', '+4.2%'),
                  MarketDrawerActions([
                    MarketSlantButton('购买', onTap: () => tapped++, filled: true),
                  ]),
                ],
              ),
              child: const ColoredBox(color: Colors.black12),
            ),
          ),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(900, 700));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(MarketHoverCard)));
    await tester.pump(const Duration(milliseconds: 60));
    // A quick sweep across the grid does not flash the drawer.
    expect(find.byKey(const ValueKey('drawer')), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drawer')), findsOneWidget);
    expect(find.text('+4.2%'), findsOneWidget);
    // The drawer hangs below the card, never over it.
    final card = tester.getRect(find.byType(MarketHoverCard));
    final drawer = tester.getRect(find.byKey(const ValueKey('drawer')));
    expect(drawer.top, greaterThanOrEqualTo(card.bottom - 2));
    expect(drawer.width, closeTo(card.width, 1));
    // Moving into the drawer keeps it open; its action closes it first.
    await mouse.moveTo(tester.getCenter(find.text('购买')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('drawer')), findsOneWidget);
    await tester.tap(find.text('购买'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
    expect(find.byKey(const ValueKey('drawer')), findsNothing);
    // Leaving closes it after the grace period.
    await mouse.moveTo(tester.getCenter(find.byType(MarketHoverCard)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drawer')), findsOneWidget);
    await mouse.moveTo(const Offset(900, 700));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drawer')), findsNothing);
  });

  testWidgets('keyboard focus opens the same drawer', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      preview(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 220,
            height: 120,
            child: MarketHoverCard(
              drawerKey: const ValueKey('drawer'),
              drawer: (_) => const Text('info'),
              child: InkWell(focusNode: focus, onTap: () {}, child: const SizedBox.expand()),
            ),
          ),
        ),
        AppearanceMode.light,
      ),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('info'), findsOneWidget);
    focus.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('info'), findsNothing);
  });

  testWidgets('heading actions sit on the right edge whatever the meta width', (
    tester,
  ) async {
    for (final width in [1600.0, 900.0, 420.0]) {
      await tester.pumpWidget(
        preview(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  for (final meta in ['刚刚更新', '共 36 件在售 · 刚刚更新'])
                    MarketSectionHeading(
                      '按分类逛',
                      key: ValueKey('h-$meta'),
                      meta: Text(meta),
                      trailing: const Text('进入市场 →', key: ValueKey('act')),
                    ),
                ],
              ),
            ),
          ),
          AppearanceMode.dark,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no overflow at $width');
      for (final meta in ['刚刚更新', '共 36 件在售 · 刚刚更新']) {
        final heading = tester.getRect(find.byKey(ValueKey('h-$meta')));
        final action = tester.getRect(
          find.descendant(
            of: find.byKey(ValueKey('h-$meta')),
            matching: find.byKey(const ValueKey('act')),
          ),
        );
        expect(heading.right - action.right, lessThan(1), reason: '$meta at $width');
      }
    }
  });
}
