// G3 (0.7.2, preview watchlist-preview.html approved 2026-10-21): the 关注
// tab compares each followed item with what it looked like when followed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_watch_page.dart';

import 'marketplace_test.dart' show FixturePort, app;

MarketRead _offers(String price, int total) => MarketRead({
  'rows': [
    {'unitPrice': price, 'itemName': 'Watched $total', 'seller': 'A*****y'},
  ],
  'total': total,
}, DateTime.now());

void main() {
  test('an entry compares now with when followed', () {
    const changed = MarketWatchEntry(
      id: 1,
      loaded: true,
      lowest: 900000,
      count: 5,
      thenPrice: 1000000,
      thenCount: 2,
    );
    expect(changed.changePercent, closeTo(-10, .001));
    expect(changed.newListings, 3);
    expect(changed.changed, isTrue);
    const flat = MarketWatchEntry(
      id: 2,
      loaded: true,
      lowest: 1000000,
      count: 1,
      thenPrice: 1000000,
      thenCount: 3,
    );
    expect(flat.changePercent, 0);
    expect(flat.newListings, 0, reason: 'fewer listings is not "new"');
    expect(flat.changed, isFalse);
    // Unknown on either side is never a change.
    const unknown = MarketWatchEntry(id: 3, loaded: true, lowest: 5);
    expect(unknown.changePercent, isNull);
    expect(unknown.changed, isFalse);
  });

  test(
    'following records a snapshot; undo restores the original one',
    () async {
      final port = FixturePort();
      final c = MarketplaceController(port);
      addTearDown(c.dispose);
      await c.readPreferences();
      c.blocks['watch-price:7'] = _offers('1200000', 4);
      await c.toggleFavorite(7);
      final snapshot = c.watchSnapshot(7)!;
      expect(snapshot['price'], '1200000');
      expect(snapshot['count'], 4);
      expect(port.prefs['watched'], isNotEmpty, reason: 'saved locally');
      await c.toggleFavorite(7);
      expect(c.favorites, isNot(contains(7)));
      expect(c.watchSnapshot(7), isNull, reason: 'unfollowing forgets it');
      // Undo puts back what it looked like when first followed, not "now".
      c.blocks['watch-price:7'] = _offers('900000', 9);
      await c.toggleFavorite(7, snapshot: snapshot);
      expect(c.watchSnapshot(7)!['price'], '1200000');
    },
  );

  testWidgets(
    'the tab lists changed items first and the tab badge counts them',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = FixturePort()
        ..prefs = {
          'revision': 0,
          'favorites': [2, 1],
          'recentItems': <int>[],
          'recentSearches': <String>[],
          'watched': [
            {'id': 1, 'price': '1000000', 'count': 2, 'at': 1},
            {'id': 2, 'price': '500000', 'count': 1, 'at': 2},
          ],
        };
      final c = MarketplaceController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
      );
      await tester.pumpAndSettle();
      c.tab(5);
      await tester.pumpAndSettle();
      expect(find.byType(MarketplaceWatchPage), findsOneWidget);
      c.blocks['watch-price:1'] = _offers('900000', 5); // ▼10% and +3
      c.blocks['watch-price:2'] = _offers('500000', 1); // unchanged
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(c.watchChanged, 1);
      final first = tester.getTopLeft(
        find.byKey(const ValueKey<(String, int)>(('market-watch-entry', 1))),
      );
      final second = tester.getTopLeft(
        find.byKey(const ValueKey<(String, int)>(('market-watch-entry', 2))),
      );
      expect(first.dy, lessThan(second.dy), reason: 'changed first');
      expect(find.text('有变化'), findsOneWidget);
      expect(find.text('▼ 10.0%'), findsOneWidget);
      expect(find.textContaining('+3 新增'), findsOneWidget);
      expect(find.text('1 件有变化'), findsWidgets);

      // "最近关注" keeps the follow order (2 was followed last).
      await tester.tap(
        find.byKey(const ValueKey(('market-watch-sort', 'recent'))),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey<(String, int)>(('market-watch-entry', 2)),
              ),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(
                  const ValueKey<(String, int)>(('market-watch-entry', 1)),
                ),
              )
              .dy,
        ),
      );

      // The red heart unfollows, with an undo.
      await tester.tap(
        find.byKey(const ValueKey<(String, int)>(('market-watch-unfollow', 1))),
      );
      await tester.pumpAndSettle();
      expect(c.favorites, [2]);
      expect(find.text('撤销'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(c.favorites, contains(1));
      expect(c.watchSnapshot(1)!['price'], '1000000');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
