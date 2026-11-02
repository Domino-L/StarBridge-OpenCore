// Slice25: the orders filter's location button and the location picker
// (all locations, location rows, retry, close). Native geometry measured
// before the change is pinned for the standard suite; every suite keeps one
// reader action per control, pointer activation and the chosen result.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_market_filters.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

class _LocationPort extends TradesPort {
  bool failLocations = false;
  int locationReads = 0;
  @override
  Future<MarketRead> read(
    String operation, {
    int id = 0,
    String keyword = '',
    int category = 0,
    int side = 1,
    int page = 1,
    String language = 'CN',
    Map<String, String> options = const {},
  }) {
    if (operation != 'locations') {
      return super.read(
        operation,
        id: id,
        keyword: keyword,
        category: category,
        side: side,
        page: page,
        language: language,
        options: options,
      );
    }
    locationReads++;
    if (failLocations) return Future.error(StateError('fixture'));
    return Future.value(
      MarketRead({
        'rows': [
          {'id': 1, 'name': '新巴贝奇'},
          {'id': 2, 'name': '洛里维尔'},
        ],
        'pageEnd': true,
      }, DateTime.utc(2026, 10, 20)),
    );
  }
}

final _button = find.byKey(const Key('market-filter-location'));
final _all = find.byKey(const Key('market-location-all'));
final _retry = find.byKey(const Key('market-location-retry'));
final _close = find.byKey(const Key('market-location-close'));
Finder _row(int id) =>
    find.byKey(ValueKey<(String, Object?)>(('market-location', id)));

Future<(MarketplaceController, _LocationPort)> _filters(
  WidgetTester tester,
  InteractionSuite suite, {
  bool fail = false,
}) async {
  size(tester, const Size(1280, 900));
  final port = _LocationPort()..failLocations = fail;
  final c = MarketplaceController(port);
  c.browser.kind = 'orders';
  await tester.pumpWidget(
    scopedApp(
      SizedBox(
        width: 300,
        height: 860,
        child: MarketplaceMarketFilters(c, reset: (w) => w),
      ),
      suite,
    ),
  );
  await tester.pumpAndSettle();
  return (c, port);
}

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'standard suite keeps the measured native geometry (fail=$fail)',
      (tester) async {
        final (c, _) = await _filters(
          tester,
          InteractionSuite.standard,
          fail: fail,
        );
        try {
          expect(
            tester.getRect(_button),
            const Rect.fromLTRB(503, 281, 777, 311),
          );
          expect(
            tester.getRect(
              find.descendant(of: _button, matching: find.byType(Icon)),
            ),
            const Rect.fromLTRB(753, 288, 769, 304),
          );
          await tester.tap(_button);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(_all),
            const Rect.fromLTRB(606, 267.5, 674, 315.5),
          );
          expect(
            tester.getRect(_close),
            const Rect.fromLTRB(792, 667.5, 840, 715.5),
          );
          if (fail) {
            expect(
              tester.getRect(_retry),
              const Rect.fromLTRB(616, 315.5, 664, 363.5),
            );
          } else {
            expect(
              tester.getRect(_row(1)),
              const Rect.fromLTRB(440, 315.5, 840, 371.5),
            );
            expect(
              tester.getRect(_row(2)),
              const Rect.fromLTRB(440, 371.5, 840, 427.5),
            );
            expect(
              tester.getRect(find.text('新巴贝奇')),
              const Rect.fromLTRB(456, 331.5, 816, 355.5),
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
  }

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: reader picks a location and all locations', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (c, _) = await _filters(tester, suite);
      try {
        activate(tester, namedButton(tester, '全部地点'));
        await tester.pumpAndSettle();
        activate(tester, namedButton(tester, '洛里维尔'));
        await tester.pumpAndSettle();
        expect(_close, findsNothing);
        expect(c.browser.location?['id'], 2);
        expect(c.browser.options['locationId'], '2');
        await tester.tap(_button);
        await tester.pumpAndSettle();
        activate(tester, namedButton(tester, '全部地点'));
        await tester.pumpAndSettle();
        expect(_close, findsNothing);
        expect(c.browser.location, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets('${suite.name}: pointer row, retry and close', (tester) async {
      final semantics = tester.ensureSemantics();
      final (c, port) = await _filters(tester, suite, fail: true);
      try {
        await tester.tap(_button);
        await tester.pumpAndSettle();
        expect(port.locationReads, 1);
        port.failLocations = false;
        activate(tester, namedButton(tester, '重试'));
        await tester.pumpAndSettle();
        expect(port.locationReads, 2);
        expect(_row(1), findsOneWidget);
        await tester.tap(_close);
        await tester.pumpAndSettle();
        expect(_close, findsNothing);
        expect(c.browser.location, isNull);
        await tester.tap(_button);
        await tester.pumpAndSettle();
        await tester.tap(_row(1));
        await tester.pumpAndSettle();
        expect(c.browser.location?['id'], 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });
  }
}
