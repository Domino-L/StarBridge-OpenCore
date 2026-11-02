// Tier pricing (user 2026-10-23, preview TradingHall/quality-tiers.html):
// prices compare inside a quality tier and, inside a tier, by price per point.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_diagonal.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hall_drawers.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_quality.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_quality.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_quality_widgets.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import 'marketplace_slice4_test.dart' show preview;

final _tiers = <String, Object?>{
  'itemId': 7,
  'hasQuality': true,
  'sell': {'lowest': 1016524, 'quality': 612, 'count': 47, 'known': true},
  'buy': {'highest': null, 'count': 0, 'known': true},
  'tiers': [
    {
      'key': 'legendary',
      'lowest': 2400000,
      'quality': 971,
      'best': {'price': 2400000, 'quality': 971, 'perPoint': 2472},
      'count': 2,
    },
    {
      'key': 'excellent',
      'lowest': 1800000,
      'quality': 812,
      'best': {'price': 1850000, 'quality': 946, 'perPoint': 1956},
      'count': 9,
    },
    {
      'key': 'good',
      'lowest': 1016524,
      'quality': 612,
      'best': {'price': 1050000, 'quality': 790, 'perPoint': 1329},
      'count': 21,
    },
    {'key': 'poor', 'lowest': null, 'count': 0},
    {'key': 'inferior', 'known': false},
  ],
};

class _TierPort implements MarketplacePort {
  int reads = 0;
  @override
  bool get available => true;
  @override
  int get generation => 1;
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
    if (operation == 'qualityTiers' && keyword == '7') reads++;
    return MarketRead(
      operation == 'qualityTiers' ? _tiers : const {'rows': <MarketRow>[]},
      DateTime.utc(2026, 10, 23),
    );
  }

  @override
  Future<MarketRow> preferences([MarketRow? value]) async => {};
  @override
  void dispose() {}
}

MarketRow _offer(String id, int price, num? quality) => {
  'orderNumber': id,
  'unitPrice': '$price',
  if (quality != null) 'qualityData': '{"type":"material","quality":$quality}',
};

/// Motion reduced, as the client's setting or the system's would: the 极品
/// sheen stands still, so the tree settles.
Widget _calm(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);

void main() {
  test('tiers: 极品 from 950, the others keep their ranges', () {
    expect(MarketQualityTier.of(1000), MarketQualityTier.legendary);
    expect(MarketQualityTier.of(950), MarketQualityTier.legendary);
    expect(MarketQualityTier.of(949), MarketQualityTier.excellent);
    expect(MarketQualityTier.of(800), MarketQualityTier.excellent);
    expect(MarketQualityTier.of(600), MarketQualityTier.good);
    expect(MarketQualityTier.of(200), MarketQualityTier.poor);
    expect(MarketQualityTier.of(199), MarketQualityTier.inferior);
    expect(marketPerPoint('1850000', 946)?.round(), 1956);
    expect(marketPerPoint(100, 0), isNull);

    final tiers = MarketQualityTiers.from(_tiers);
    expect(tiers.hasQuality, isTrue);
    expect(tiers.sellCount, 47);
    final excellent = tiers.of(MarketQualityTier.excellent)!;
    expect(excellent.bestDiffers, isTrue, reason: '946 is not the cheapest');
    expect(tiers.of(MarketQualityTier.legendary)!.bestDiffers, isFalse);
    expect(tiers.of(MarketQualityTier.inferior)!.known, isFalse);
  });

  test('offers: same price shows the better quality first; per point; '
      'best value per tier; tier groups', () {
    final c = MarketplaceController(_TierPort());
    addTearDown(c.dispose);
    final rows = [
      _offer('A', 1800000, 812),
      _offer('B', 1850000, 916),
      _offer('C', 1850000, 946),
      _offer('D', 2400000, 971),
      _offer('E', 2400000, null),
      _offer('F', 2400000, null),
    ];
    // SCM's price order, ties broken by quality; no-quality ties stay put.
    expect(c.sortedOffers(rows).map((r) => r['orderNumber']), [
      'A',
      'C',
      'B',
      'D',
      'E',
      'F',
    ]);
    c.offerSortField = 'perPoint';
    c.offerSortDesc = false;
    expect(c.sortedOffers(rows).map((r) => r['orderNumber']), [
      'C', // 1956
      'B', // 2020
      'A', // 2217
      'D', // 2472
      'E',
      'F',
    ]);
    expect(marketBestValueOrders(rows), {'C', 'D'});

    final entries = marketOfferEntries(rows, group: true);
    expect(
      [for (final e in entries) e.header?.name ?? e.row!['orderNumber']],
      ['legendary', 'D', 'excellent', 'A', 'B', 'C', 'E', 'F'],
    );
  });

  test('a tier filters to its range; the ≥ menu replaces it', () async {
    final c = MarketplaceController(_TierPort());
    addTearDown(c.dispose);
    await c.openItem(7);
    await c.setOfferTier(MarketQualityTier.excellent);
    expect(c.offerFilters['minQuality'], '800');
    expect(c.offerFilters['maxQuality'], '949');
    expect(c.offerTier, MarketQualityTier.excellent);
    await c.setOfferFilter('minQuality', '600');
    expect(c.offerFilters.containsKey('maxQuality'), isFalse);
    expect(c.offerTier, isNull);
    await c.setOfferTier(null);
    expect(c.offerFilters.containsKey('minQuality'), isFalse);
  });

  testWidgets('trending: quality items show any-quality and top-tier lines; '
      'others call the price a recent average', (tester) async {
    await tester.pumpWidget(
      preview(
        _calm(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 170,
                height: 252,
                child: MarketCard(
                  {
                    'id': 7,
                    'itemName': '科力晶（单个矿块）',
                    'price': 1016524,
                    'qualityAny': {'lowest': 1016524, 'quality': 612},
                    'qualityTop': {
                      'key': 'legendary',
                      'min': 950,
                      'max': 1000,
                      'lowest': 2400000,
                    },
                  },
                  open: null,
                  trending: true,
                ),
              ),
              const SizedBox(width: 12),
              const SizedBox(
                width: 170,
                height: 228,
                child: MarketCard(
                  {
                    'id': 8,
                    'itemName': 'HG-15 猎人',
                    'price': 1500000,
                    'changePercent': 0,
                  },
                  open: null,
                  trending: true,
                ),
              ),
            ],
          ),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('任意品质'), findsOneWidget);
    expect(find.byType(MarketFoilTag), findsOneWidget);
    expect(find.textContaining('近期均价'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the hover box reads live tiers once and shows the ladder', (
    tester,
  ) async {
    final port = _TierPort();
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    final row = {'id': 7, 'price': 1016524, 'changePercent': 3.2};
    await tester.pumpWidget(
      preview(
        _calm(
          SizedBox(
            width: 340,
            child: Builder(
              builder: (context) =>
                  marketTrendingDrawer(context, context, c, row),
            ),
          ),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(port.reads, 1);
    expect(
      find.byKey(const ValueKey(('market-tier-ladder', 'legendary'))),
      findsOneWidget,
    );
    expect(find.textContaining('档内最划算'), findsNWidgets(2));
    expect(find.text('近期均价'), findsOneWidget);
    expect(find.text('47'), findsOneWidget, reason: 'live listing count');
    await tester.pumpAndSettle();
    expect(port.reads, 1, reason: 'cached for a minute');
    expect(tester.takeException(), isNull);
  });

  test(
    'a cached tier read is shown for a minute, then read again (CX-55)',
    () async {
      var at = DateTime(2026, 10, 23, 12);
      var reads = 0;
      final store = MarketQualityTiersStore(
        read: (id) async {
          reads++;
          return MarketRead(_tiers, at);
        },
        changed: () {},
        now: () => at,
      );
      expect(store.stale(7), isTrue);
      await store.ensure(7);
      expect((reads, store.stale(7)), (1, false));
      await store.ensure(7);
      expect(reads, 1, reason: 'fresh for a minute');
      at = at.add(const Duration(seconds: 61));
      expect(store.stale(7), isTrue);
      expect(
        store.of(7),
        isNotNull,
        reason: 'old figures stay while re-reading',
      );
      await store.ensure(7);
      expect(reads, 2);
    },
  );

  testWidgets('an incomplete tier scan does not claim the best in tier', (
    tester,
  ) async {
    final partial = MarketQualityTiers.from({
      ..._tiers,
      'tiers': [
        {
          'key': 'excellent',
          'lowest': 1800000,
          'quality': 812,
          'best': {'price': 1850000, 'quality': 946, 'perPoint': 1956},
          'count': 90,
          'bestComplete': false,
          'bestScanned': 60,
        },
      ],
    });
    expect(partial.tiers.single.bestComplete, isFalse);
    expect(MarketQualityTiers.from(_tiers).tiers.first.bestComplete, isTrue);
    await tester.pumpWidget(
      preview(
        _calm(SizedBox(width: 340, child: MarketTierLadder(partial))),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('已比较的 60 单中最划算'), findsOneWidget);
    expect(find.textContaining('档内最划算'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('publishing compares inside the tier, by price and per point', (
    tester,
  ) async {
    final tiers = MarketQualityTiers.from(_tiers);
    await tester.pumpWidget(
      preview(
        _calm(
          Builder(
            builder: (context) => Column(
              children: [
                Padding(
                  padding: EdgeInsets.zero,
                  child: marketTierPriceDelta(
                    context,
                    tiers: tiers,
                    price: 2300000,
                    quality: 963,
                  )!,
                ),
                Padding(
                  padding: EdgeInsets.zero,
                  child: marketTierPriceDelta(
                    context,
                    tiers: tiers,
                    price: 2100000,
                    quality: 812,
                  )!,
                ),
              ],
            ),
          ),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('你的价格将成为极品档最低'), findsOneWidget);
    expect(find.textContaining('也是最划算'), findsOneWidget);
    expect(find.textContaining('比同档最低高 300,000'), findsOneWidget);
    expect(find.textContaining('高 32%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('per point compares unrounded and shows decimals below 100 (CX-56)', () {
    expect(marketPerPointFigure(100 / 600), '0.17');
    expect(marketPerPointFigure(12.345), '12.3');
    expect(marketPerPointFigure(2472.4), '2,472');
    final quote = MarketQualityTiers.from({
      ..._tiers,
      'tiers': [
        {
          'key': 'good',
          'lowest': 100,
          'quality': 600,
          'best': {'price': 100, 'quality': 600, 'perPoint': 0},
          'count': 1,
        },
      ],
    }).tiers.single;
    expect(quote.bestPerPoint, closeTo(0.1667, 1e-4), reason: 'not the Host 0');
  });

  testWidgets('a cheaper per point than a rounded-to-0 best is the best, '
      'and nothing divides by zero', (tester) async {
    final tiers = MarketQualityTiers.from({
      ..._tiers,
      'tiers': [
        {
          'key': 'good',
          'lowest': 100,
          'quality': 600,
          'best': {'price': 100, 'quality': 600, 'perPoint': 0},
          'count': 1,
        },
      ],
    });
    await tester.pumpWidget(
      preview(
        _calm(
          Builder(
            builder: (context) => marketTierPriceDelta(
              context,
              tiers: tiers,
              price: 99,
              quality: 600,
            )!,
          ),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('也是最划算'), findsOneWidget);
    expect(find.textContaining('0.17/点'), findsOneWidget);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 0 aUEC tier lowest shows the gap without a percentage', (
    tester,
  ) async {
    final tiers = MarketQualityTiers.from({
      ..._tiers,
      'tiers': [
        {
          'key': 'good',
          'lowest': 0,
          'quality': 650,
          'best': {'price': 0, 'quality': 650, 'perPoint': 0},
          'count': 1,
        },
      ],
    });
    await tester.pumpWidget(
      preview(
        _calm(
          Builder(
            builder: (context) => marketTierPriceDelta(
              context,
              tiers: tiers,
              price: 5000,
              quality: 700,
            )!,
          ),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('比同档最低高 5,000'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('item page: a partial tier says so, and row marks say loaded', (
    tester,
  ) async {
    final quote = MarketQualityTiers.from({
      ..._tiers,
      'tiers': [
        {
          'key': 'excellent',
          'lowest': 1800000,
          'quality': 812,
          'best': {'price': 1850000, 'quality': 946, 'perPoint': 1956},
          'count': 90,
          'bestComplete': false,
          'bestScanned': 60,
        },
      ],
    }).tiers.single;
    await tester.pumpWidget(
      preview(
        _calm(
          SizedBox(
            width: 600,
            child: Column(
              children: [
                MarketTierGroupHeader(
                  MarketQualityTier.excellent,
                  quote: quote,
                ),
                const MarketOfferPerPoint({
                  'orderNumber': 'A',
                  'unitPrice': 1850000,
                  'qualityData': {'type': 'material', 'quality': 946},
                }, best: true),
              ],
            ),
          ),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('已比较 60 单中最划算'), findsOneWidget);
    expect(find.textContaining('已加载中最划算'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the 极品 sheen moves, and stands still with motion reduced', (
    tester,
  ) async {
    Widget tag() => const MarketSlantTag(
      '极品',
      color: Colors.amber,
      mono: '963',
      foil: true,
    );
    await tester.pumpWidget(preview(tag(), AppearanceMode.dark));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(preview(_calm(tag()), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
