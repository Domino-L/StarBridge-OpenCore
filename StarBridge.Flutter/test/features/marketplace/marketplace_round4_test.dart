import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';

import 'marketplace_test.dart' show FixturePort, app;

class RelatedPort extends FixturePort {
  bool fail = false;
  String? missing;
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
  }) async {
    if (operation != 'blueprints') {
      return super.read(
        operation,
        id: id,
        keyword: keyword,
        category: category,
        side: side,
        page: page,
        language: language,
      );
    }
    if (fail) throw StateError('transport failed');
    return MarketRead({
      if (missing != null) 'missing': missing,
      'rows': missing != null
          ? <MarketRow>[]
          : [
              {
                'id': 902,
                'blueprintNameCn': '精确材料蓝图',
                'blueprintName': 'Exact material blueprint',
              },
            ],
      'total': missing == null ? 1 : 0,
    }, DateTime.utc(2026, 10, 16));
  }
}

void main() {
  testWidgets('desktop mouse opens recent item from search history', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FixturePort();
    port.prefs = {
      ...port.prefs,
      'recentItems': [17],
    };
    final c = MarketplaceController(port);
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('marketplace-search')));
    await tester.pumpAndSettle();
    expect(find.text('测试物品 17'), findsOneWidget);
    final mouse = await tester.startGesture(
      tester.getCenter(find.text('测试物品 17')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 80));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(c.itemId, 17);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
    'blueprint results retain data on failure and explain missing identity',
    (tester) async {
      final port = RelatedPort();
      final c = MarketplaceController(port);
      await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh')));
      await tester.pumpAndSettle();
      await c.related('blueprints', 17);
      await tester.pumpAndSettle();
      expect(find.text('精确材料蓝图'), findsOneWidget);
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text('精确材料蓝图'), matching: find.byType(ListTile)),
      );
      expect(
        tile.onTap,
        isNull,
      ); // A blueprint ID must never open an item page.
      port.fail = true;
      await c.refreshCatalog();
      await tester.pumpAndSettle();
      expect(find.text('精确材料蓝图'), findsOneWidget);
      expect(tester.takeException(), isNull);
      port.fail = false;
      port.missing = 'materialIdentity';
      await c.refreshCatalog();
      await tester.pumpAndSettle();
      expect(find.text('缺少物品 UUID，无法确定材料对应关系'), findsOneWidget);
      expect(find.text('精确材料蓝图'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test('market routes reach Host without renderer account identifiers', () {
    for (final name in ['marketplace.read', 'marketplace.preferences']) {
      expect(
        () => BridgeRequestPolicy.requireAccountContext(name, null),
        returnsNormally,
      );
    }
    expect(
      () => BridgeRequestPolicy.requireAccountContext(
        'marketplace.purchase',
        null,
      ),
      throwsA(isA<BridgeAccountContextRequiredException>()),
    );
  });
  test(
    'filters and layout survive controller recreation with local preferences',
    () async {
      final port = FixturePort();
      final first = MarketplaceController(port);
      await first.initialize();
      await first.browse(query: 'ore', category: 3);
      await first.setLayout('rows');
      await first.setSide(0);
      first.dispose();
      final next = MarketplaceController(port);
      await next.initialize();
      expect(next.keyword, 'ore');
      expect(next.categoryId, 3);
      expect(next.layout, 'rows');
      expect(next.side, 0);
      expect(next.hasCatalog, isTrue);
      next.dispose();
    },
  );
  test('related filter survives item return and restart; ordinary search clears it', () async {
    final port = FixturePort();
    final c = MarketplaceController(port);
    await c.initialize();
    await c.related('attachments', 17);
    await c.openItem(23);
    c.back();
    expect(c.relation, 'attachments');
    expect(c.relatedId, 17);
    c.dispose();
    final restored = MarketplaceController(port);
    await restored.initialize();
    expect(restored.relation, 'attachments');
    expect(restored.relatedId, 17);
    await restored.browse(query: 'new');
    expect(restored.relation, isEmpty);
    expect(restored.relatedId, 0);
    restored.dispose();
  });
}
