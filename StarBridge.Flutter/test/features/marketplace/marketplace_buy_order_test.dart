// Buy orders (user 2026-11-07): the quality tag says what the order needs
// ("需要｜极品 ≥975", 方案 A) and the price is judged from the seller's side —
// the higher the bid against the lowest ask that meets the requirement, the
// better ("求购应该算怎么卖能赚更多钱 才是划算").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_buy_value.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_cards.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_order_detail.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_quality.dart';

import 'marketplace_slice4_test.dart' show ListingsFixture, preview;
import 'marketplace_test.dart' show FixturePort;

final _tiers = <String, Object?>{
  'itemId': 7,
  'hasQuality': true,
  'sell': {'lowest': 1016524, 'quality': 612, 'count': 47, 'known': true},
  'buy': {'highest': 2500000, 'count': 3, 'known': true},
  'tiers': [
    {'key': 'legendary', 'lowest': 2400000, 'quality': 971, 'count': 2},
    {'key': 'excellent', 'lowest': 1800000, 'quality': 812, 'count': 9},
    {'key': 'good', 'lowest': 1016524, 'quality': 612, 'count': 21},
    {'key': 'normal', 'lowest': null, 'count': 0},
    {'key': 'poor', 'known': false},
  ],
};

class _Port implements MarketplacePort {
  _Port(this.tiers);
  final Map<String, Object?> tiers;
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
  }) async => MarketRead(
    operation == 'qualityTiers' ? tiers : const {'rows': <MarketRow>[]},
    DateTime.utc(2026, 11, 7),
  );
  @override
  Future<MarketRow> preferences([MarketRow? value]) async => {};
  @override
  void dispose() {}
}

MarketRow _bid(int price, {Map<String, Object?>? quality}) => {
  'orderNumber': 'B$price',
  'creatorType': 0,
  'unitPrice': price,
  'items': [
    {'itemId': 7, 'qualityData': ?quality},
  ],
};

void main() {
  test('a buy order reads its quality as a requirement', () {
    // Stored by SCM as qualityMin, or as quality on older orders.
    expect(
      marketQuality(_bid(1, quality: {'type': 'material', 'qualityMin': 975})),
      '≥975',
    );
    expect(
      marketQuality(_bid(1, quality: {'type': 'material', 'quality': 975})),
      '≥975',
    );
    expect(
      marketQuality({
        'side': 'buy',
        'qualityData': {'type': 'material', 'quality': 640},
      }),
      '≥640',
      reason: 'our own buy listings',
    );
    expect(
      marketQuality({
        'creatorType': 1,
        'qualityData': {'type': 'material', 'quality': 975},
      }),
      '975',
      reason: 'a sell listing states its goods',
    );
    // A stated sell side wins over the data: a stored qualityMin shows ≥ but
    // never 需要 (CX-BUYTAG-REVIEW P2-2).
    final ask = {
      'creatorType': 1,
      'qualityData': {'type': 'material', 'qualityMin': 900},
    };
    expect(marketQualityRequired(ask), isFalse);
    expect(marketQuality(ask), '≥900');
    expect(
      marketQualityRequired({'side': 'sell', ...ask}..remove('creatorType')),
      isFalse,
    );
    expect(
      [
        for (final creator in <Object?>[0, 1, '0', '1', null, 2, 'x', 1.0])
          marketOrderSide({'creatorType': creator}),
      ],
      ['buy', 'sell', 'buy', 'sell', null, null, null, null],
    );
    // Only the exact text counts (CX-BUYTAG-REVIEW-R4 P2-1).
    for (final creator in <Object?>[
      ' 1',
      '+1',
      '01',
      '0x1',
      '1.0',
      ' 0',
      true,
      false,
    ]) {
      expect(
        marketOrderSide({'creatorType': creator}),
        isNull,
        reason: '$creator',
      );
    }
    // A valid creatorType outranks the row's own side (documented choice).
    expect(marketQualityRequired({'creatorType': 1, 'side': 'buy'}), isFalse);
    // No side at all: the data decides.
    expect(
      marketQualityRequired({
        'qualityData': {'type': 'material', 'qualityMin': 900},
      }),
      isTrue,
    );
  });

  testWidgets('the buy tag keeps its tier look behind a fused 需要', (
    tester,
  ) async {
    await tester.pumpWidget(
      preview(
        Column(
          children: [
            MarketQualityBadge(
              _bid(1, quality: {'type': 'material', 'quality': 650}),
            ),
            const MarketQualityBadge({
              'creatorType': 1,
              'qualityData': {'type': 'material', 'quality': 640},
            }),
            const MarketQualityBadge({
              'creatorType': 1,
              'qualityData': {'type': 'material', 'qualityMin': 880},
            }),
          ],
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('market-quality-needs')), findsOneWidget);
    expect(find.text('需要'), findsOneWidget);
    expect(find.textContaining('≥650'), findsOneWidget);
    expect(find.text('640'), findsOneWidget, reason: 'sell tag unchanged');
    expect(
      find.text('≥880'),
      findsOneWidget,
      reason: 'a sell side never needs',
    );
    expect(find.bySemanticsLabel(RegExp('需要 .* ≥650')), findsOneWidget);
  });

  test('bids compare with the lowest ask that meets the requirement', () {
    final tiers = MarketQualityTiers.from(_tiers);
    // ≥960: 极品's cheapest ask is 971, good enough.
    expect(
      marketBidValue(tiers, price: 2500000, minQuality: 960)?.verdict,
      MarketBidVerdict.high,
    );
    expect(
      marketBidValue(tiers, price: 2400000, minQuality: 960)?.verdict,
      MarketBidVerdict.high,
      reason: 'matching the ask is a high bid',
    );
    expect(
      marketBidValue(tiers, price: 2100000, minQuality: 960)?.verdict,
      MarketBidVerdict.near,
    );
    expect(
      marketBidValue(tiers, price: 2000000, minQuality: 960)?.verdict,
      MarketBidVerdict.low,
      reason: '83% of 2.4M is below the 85% line',
    );
    // ≥975: the 971 ask does not meet it and nothing ranks higher.
    expect(marketBidValue(tiers, price: 2500000, minQuality: 975), isNull);
    // ≥700: good's cheapest is 612, so 极佳 from 800 sets the reference.
    expect(
      marketBidValue(tiers, price: 1, minQuality: 700)?.reference,
      1800000,
    );
    // No requirement: the lowest ask of any quality.
    final any = marketBidValue(tiers, price: 1100000);
    expect(any?.reference, 1016524);
    expect(any?.tiered, isFalse);
    expect(marketBidValue(null, price: 1), isNull);
  });

  testWidgets('a bid line says how selling to the order compares', (
    tester,
  ) async {
    final c = MarketplaceController(_Port(_tiers));
    addTearDown(c.dispose);
    Future<void> show(MarketRow row) async {
      await tester.pumpWidget(
        preview(MarketBidValueLine(c, row), AppearanceMode.dark),
      );
      await tester.pumpAndSettle();
    }

    await show(_bid(2600000, quality: {'type': 'material', 'qualityMin': 960}));
    expect(find.text('卖给他：出价高'), findsOneWidget);
    expect(find.textContaining('比满足要求的最低卖价'), findsOneWidget);
    expect(find.textContaining('+8.3%'), findsOneWidget);

    await show(_bid(2100000, quality: {'type': 'material', 'qualityMin': 960}));
    expect(find.text('卖给他：接近卖价'), findsOneWidget);
    expect(find.textContaining('的 88%'), findsOneWidget);

    await show(_bid(1500000, quality: {'type': 'material', 'qualityMin': 960}));
    expect(find.text('卖给他：出价偏低'), findsOneWidget);

    await show(_bid(2500000, quality: {'type': 'material', 'qualityMin': 990}));
    expect(find.text('暂无可比的卖价'), findsOneWidget);
    expect(find.textContaining('卖给他'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // CX-BUYTAG-REVIEW-R2: SCM's item rows inside an order carry no side, so the
  // full detail must hand each line the order's own: a sell checklist's
  // qualityMin shows ≥ but never 需要; a buy checklist's and a barter's wanted
  // goods do need.
  testWidgets('order detail lines take the order side for 需要', (tester) async {
    final c = MarketplaceController(FixturePort());
    addTearDown(c.dispose);
    MarketRow line(int id, Map<String, Object?> quality) => {
      'itemId': id,
      'itemName': '物品$id',
      'quantity': 1,
      'unitPrice': 1000,
      'qualityData': quality,
    };
    Future<void> show(MarketRow order) async {
      await tester.pumpWidget(
        preview(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: SizedBox(height: 900, child: MarketOrderDetail(c, order)),
          ),
          AppearanceMode.dark,
        ),
      );
      // The detail keeps a live loader running; fixed frames, not settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    final needs = find.byKey(const Key('market-quality-needs'));
    await show({
      'orderNumber': 'SL1',
      'creatorType': 1,
      'displayType': 2,
      'itemName': '出售清单',
      'items': [
        line(11, {'type': 'material', 'qualityMin': 900}),
        line(12, {'type': 'material', 'quality': 640}),
      ],
    });
    expect(find.textContaining('≥900'), findsWidgets);
    expect(find.textContaining('640'), findsWidgets);
    expect(needs, findsNothing, reason: 'a sell checklist never needs');

    await show({
      'orderNumber': 'BL1',
      'creatorType': 0,
      'displayType': 2,
      'itemName': '求购清单',
      'items': [
        line(13, {'type': 'material', 'quality': 700}),
      ],
    });
    expect(find.textContaining('≥700'), findsWidgets);
    expect(needs, findsWidgets, reason: 'a buy checklist needs');

    await show({
      'orderNumber': 'BT1',
      'creatorType': 1,
      'displayType': 3,
      'itemName': '以物换物',
      'items': [
        line(14, {'type': 'material', 'quality': 820}),
      ],
      'wantedItems': [
        line(15, {'type': 'material', 'quality': 960}),
      ],
    });
    expect(find.textContaining('820'), findsWidgets);
    expect(find.textContaining('≥820'), findsNothing, reason: 'offered goods');
    expect(find.textContaining('≥960'), findsWidgets);
    expect(needs, findsOneWidget, reason: 'only the wanted line needs');

    // CX-BUYTAG-REVIEW-R3: a parent side SCM sent as text still counts; an
    // absent or invalid one stays unknown, so the line keeps its own fallback
    // (a qualityMin means a requirement) instead of being forced to sell.
    await show({
      'orderNumber': 'BL2',
      'creatorType': '0',
      'displayType': 2,
      'itemName': '求购清单',
      'items': [
        line(16, {'type': 'material', 'quality': 700}),
      ],
    });
    expect(find.textContaining('≥700'), findsWidgets);
    expect(needs, findsWidgets, reason: '"0" is a buy order');
    for (final creator in <Object?>[
      null,
      'missing',
      2,
      'x',
      1.0,
      ' 1',
      '+1',
      '01',
      '0x1',
    ]) {
      await show({
        'orderNumber': 'UL$creator',
        if (creator != 'missing') 'creatorType': creator,
        'displayType': 2,
        'itemName': '清单',
        'items': [
          line(17, {'type': 'material', 'qualityMin': 900}),
          line(18, {'type': 'material', 'quality': 640}),
        ],
      });
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.textContaining('≥900').last,
            matching: find.byType(MarketQualityBadge),
          ),
          matching: needs,
        ),
        findsOneWidget,
        reason: 'unknown side $creator keeps the qualityMin fallback',
      );
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('640').last,
            matching: find.byType(MarketQualityBadge),
          ),
          matching: needs,
        ),
        findsNothing,
        reason: 'an exact quality with no side is no requirement',
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // CX-BUYTAG-REVIEW-R3 P3: the publish dialog's price step shows the item
  // with the draft's side, so a buy draft reads 需要 ≥ like the order will.
  testWidgets('the publish preview of a buy draft needs', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = MarketplaceListingsController(ListingsFixture());
    await c.refresh();
    Future<void> show(String side) async {
      final draft = ListingDraft(
        item: {
          'id': c.items.first['id'],
          'name': c.items.first['name'],
          'hasQuality': true,
        },
        side: side,
        location: '1',
        quality: '975',
      );
      await tester.pumpWidget(
        preview(
          ListingPublishDialog(c, draft, initialStep: 2),
          AppearanceMode.dark,
        ),
      );
      // The 极品 foil keeps shimmering; fixed frames, not settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await show('buy');
    expect(find.byKey(const Key('market-quality-needs')), findsOneWidget);
    expect(find.textContaining('≥975'), findsOneWidget);
    // A fresh dialog: it keeps the draft it opened with.
    await tester.pumpWidget(const SizedBox());
    await show('sell');
    expect(find.byKey(const Key('market-quality-needs')), findsNothing);
    expect(find.textContaining('≥975'), findsNothing);
    expect(find.textContaining('975'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  // CX-BUYTAG-REVIEW-R4 P2-2/P3: the hall card reads side and figure with
  // the detail's functions — a "0" buy order needs, a sell order's stored
  // minimum shows ≥ without 需要, a barter never needs.
  testWidgets('hall cards read side and figure like the detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final needs = find.byKey(const Key('market-quality-needs'));
    Future<void> show(MarketRow row) async {
      await tester.pumpWidget(
        preview(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Center(
              child: SizedBox(
                width: 260,
                height: 340,
                child: MarketCard(row, open: () {}),
              ),
            ),
          ),
          AppearanceMode.dark,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    MarketRow card(
      Object? creator,
      Map<String, Object?> quality, {
      int display = 1,
    }) => {
      'orderNumber': 'C$creator$display',
      'creatorType': creator,
      'displayType': display,
      'itemName': '火神石',
      'seller': 't*****u',
      'point': 0,
      'presence': 'offline',
      'unitPrice': 2500000,
      'remainingQuantity': 1,
      'items': [
        {'itemId': 7, 'qualityData': quality},
      ],
    };

    await show(card('0', {'type': 'material', 'quality': 975}));
    expect(needs, findsOneWidget, reason: 'a "0" buy order needs');
    expect(find.textContaining('≥975'), findsOneWidget);

    await show(card(1, {'type': 'material', 'qualityMin': 900}));
    expect(needs, findsNothing, reason: 'a sell order never needs');
    expect(
      find.textContaining('≥900'),
      findsOneWidget,
      reason: 'like the detail',
    );

    await show(card(' 1', {'type': 'material', 'qualityMin': 900}));
    expect(needs, findsOneWidget, reason: 'unknown side: the data decides');

    await show(card(1, {'type': 'material', 'qualityMin': 900}, display: 3));
    expect(needs, findsNothing, reason: 'a barter never needs');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
