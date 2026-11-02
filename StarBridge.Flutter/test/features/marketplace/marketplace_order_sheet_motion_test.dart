// Slice19: the order details panel joins the suite route used by the trade
// details sheet. Native geometry measured before the change is pinned for the
// standard suite; every suite keeps reader/keyboard closes within two frames,
// pointer closes with their exit, live reduced motion, "view item" and the
// barrier close.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_routes_motion_test.dart' show seed, offer;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

final _close = find.byKey(const Key('market-order-close'));
final _view = find.byKey(const Key('market-order-view-item'));
final _title = find.text('订单详情');

Future<MarketplaceController> _page(
  WidgetTester tester,
  InteractionSuite suite, {
  double width = 1280,
  ValueNotifier<bool>? reduce,
}) async {
  size(tester, Size(width, 900));
  final c = MarketplaceController(TradesPort());
  seed(c);
  // The panel offers item 1 while another item is open, so "view item"
  // visibly switches the page.
  c.itemId = 2;
  c.blocks['sell'] = MarketRead({
    'rows': [
      {
        ...offer,
        'items': [
          {'itemId': 1},
        ],
      },
    ],
    'total': 1,
  }, DateTime.utc(2026, 10, 19));
  final r = reduce ?? ValueNotifier(false);
  await tester.pumpWidget(
    ValueListenableBuilder<bool>(
      valueListenable: r,
      builder: (context, value, _) =>
          scopedApp(MarketplaceItemPage(c), suite, reduce: value),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<ModalRoute<Object?>> _open(WidgetTester tester) async {
  final row = find.byKey(
    const ValueKey<(String, Object)>(('market-offer-row', 'O1')),
  );
  final b = tester.getRect(row);
  await tester.tapAt(Offset(b.left + 120, b.center.dy));
  await tester.pumpAndSettle();
  expect(_title, findsOneWidget);
  return ModalRoute.of(tester.element(_title))!;
}

void main() {
  for (final width in [1280.0, 900.0]) {
    testWidgets('standard suite keeps the measured native panel at $width', (
      tester,
    ) async {
      final c = await _page(tester, InteractionSuite.standard, width: width);
      try {
        await _open(tester);
        final left = width < 980 ? 0.0 : width - 480;
        final right = width;
        expect(tester.getRect(_title).topLeft, Offset(left + 20, 33.5));
        expect(
          tester.getRect(_close),
          Rect.fromLTRB(right - 68, 20, right - 20, 68),
        );
        expect(
          tester.getRect(
            find.descendant(of: _close, matching: find.byType(Icon)),
          ),
          Rect.fromLTRB(right - 54, 34, right - 34, 54),
        );
        expect(
          tester.getRect(_view),
          Rect.fromLTRB(left + 20, 784, right - 20, 832),
        );
        expect(
          tester.getRect(find.byKey(const Key('market-order-confirm'))),
          Rect.fromLTRB(left + 20, 832, right - 20, 880),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    });
  }

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: reader close is one action within two frames', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _page(tester, suite);
      try {
        final route = await _open(tester);
        activate(tester, namedButton(tester, '关闭'));
        await tester.pump();
        await tester.pump();
        expect(route.animation!.value, 0);
        expect(_title, findsNothing);
        expect(c.itemId, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets('${suite.name}: keyboard close lands within two frames', (
      tester,
    ) async {
      final c = await _page(tester, suite);
      try {
        final route = await _open(tester);
        for (var i = 0; i < 12; i++) {
          final focus = FocusManager.instance.primaryFocus?.context;
          if (focus != null &&
              find
                  .ancestor(
                    of: find.byElementPredicate((e) => e == focus),
                    matching: _close,
                  )
                  .evaluate()
                  .isNotEmpty) {
            break;
          }
          if (focus != null &&
              find
                  .descendant(
                    of: _close,
                    matching: find.byElementPredicate((e) => e == focus),
                  )
                  .evaluate()
                  .isNotEmpty) {
            break;
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump();
        expect(route.animation!.value, 0);
        expect(_title, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    });

    testWidgets(
      '${suite.name}: pointer close keeps its exit and live reduction settles it',
      (tester) async {
        final reduce = ValueNotifier(false);
        final c = await _page(tester, suite, reduce: reduce);
        try {
          final route = await _open(tester);
          await tester.tap(_close);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(route.animation!.value, inExclusiveRange(0, 1));
          reduce.value = true;
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 0);
          await tester.pumpAndSettle();
          expect(_title, findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          reduce.dispose();
        }
      },
    );

    testWidgets(
      '${suite.name}: view item closes and opens the item; barrier closes',
      (tester) async {
        final c = await _page(tester, suite);
        try {
          await _open(tester);
          await tester.tapAt(const Offset(40, 450));
          await tester.pumpAndSettle();
          expect(_title, findsNothing);
          expect(c.itemId, 2);
          await _open(tester);
          await tester.tap(_view);
          await tester.pumpAndSettle();
          expect(_title, findsNothing);
          expect(c.itemId, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
  }
}
