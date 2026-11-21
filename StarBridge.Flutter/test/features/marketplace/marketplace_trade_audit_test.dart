import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_records_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_records_copy.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_slice4_test.dart' show preview;
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

class AuditPort extends TradesPort {
  final calls = <MarketRow>[];
  int count = 23;
  int? failPage;
  Completer<MarketRow>? ongoingGate;

  @override
  Future<MarketRow> trade(String op, [MarketRow input = const {}]) async {
    calls.add({'operation': op, ...input});
    if (op == 'list' && input['status'] == 1) {
      if (ongoingGate != null) return ongoingGate!.future;
      final page = input['page'] as int;
      if (page == failPage) throw const MarketplaceTradeError('marketplace.unavailable');
      return {
        'total': count,
        'rows': [
          for (var i = (page - 1) * 20; i < page * 20 && i < count; i++)
            {...row, 'transactionNumber': 'A$i', 'deliveryStatus': 1},
        ],
      };
    }
    return super.trade(op, input);
  }
}

void main() {
  testWidgets('TR1/TR2/TR9 checklist contents and unknown barter quantity', (tester) async {
    final MarketRow row = {
      'displayType': 2, 'number': 3, 'itemCount': 2,
      'itemDetails': [
        {'itemId': 1, 'itemName': 'Cargo', 'quantity': 4, 'unitPrice': 200},
      ],
    };
    await tester.pumpWidget(preview(TradeContents(row), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('清单内容'), findsOneWidget);
    expect(find.text('Cargo × 4'), findsOneWidget);
    expect(find.text('× 3 套'), findsOneWidget);
    await tester.pumpWidget(preview(TradeContents({
      ...row, 'displayType': 3, 'actorRole': 'seller', 'creatorType': 1,
      'wantedItems': [{'itemId': 2, 'itemName': 'Wanted'}],
    }), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('你给出'), findsOneWidget);
    expect(find.text('你收到'), findsOneWidget);
    expect(find.text('Wanted'), findsOneWidget);
    expect(find.textContaining('Wanted ×'), findsNothing);
    await tester.pumpWidget(preview(const TradeContents({'displayType': 2}), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('清单内容'), findsNothing);
  });

  test('TR1 exchange direction covers creator type and actor role', () {
    for (final creator in [0, 1]) {
      for (final role in ['buyer', 'seller']) {
        final (give, receive) = tradeExchange({
          'creatorType': creator, 'actorRole': role,
          'itemDetails': [{'itemName': 'provided'}],
          'wantedItems': [{'itemName': 'wanted'}],
        });
        final owner = (creator == 0) == (role == 'buyer');
        expect(give.single['itemName'], owner ? 'provided' : 'wanted');
        expect(receive.single['itemName'], owner ? 'wanted' : 'provided');
      }
    }
    expect(marketThumbnail({'displayType': 3, 'itemCount': 2}), marketChecklistArt);
    expect(marketThumbnail({'displayType': 3, 'creatorType': 1, 'itemCount': 1}), isNull);
    // A barter whose item count is unknown is not shown as one item.
    expect(marketThumbnail({'displayType': 3}), marketChecklistArt);
  });

  test('TR3 reporting window, own list state and handling status', () {
    final now = DateTime.utc(2026, 11, 14);
    for (final state in [1, 2, 3]) {
      expect(tradeCanReport({'actorRole': 'buyer', 'transactionStatus': state,
        'createTime': '2026-11-07 08:00:00'}, now: now), isTrue);
    }
    // SCM refuses only when whole days > 7: 7 days 1 s and 7 days 23:59:59
    // are still allowed; 8 full days is refused (Beijing time, UTC+8).
    expect(tradeCanReport({'actorRole': 'seller', 'createTime': '2026-11-07 07:59:59'}, now: now), isTrue);
    expect(tradeCanReport({'actorRole': 'seller', 'createTime': '2026-11-06 08:00:01'}, now: now), isTrue);
    expect(tradeCanReport({'actorRole': 'seller', 'createTime': '2026-11-06 08:00:00'}, now: now), isFalse);
    expect(tradeCanReport({'actorRole': 'seller', 'createTime': '2026-11-14 08:00:00', 'hasReported': true}, now: now), isFalse);
    final merged = mergeTradeDetail({'transactionNumber': 'T', 'hasReported': true,
      'reportHandleStatus': 2, 'displayType': 2, 'amount': 0}, {
      'transactionNumber': 'T', 'hasReported': false, 'reportHandleStatus': null, 'amount': 100,
    });
    expect(merged['hasReported'], isFalse);
    expect(merged['reportHandleStatus'], isNull);
    expect(merged['amount'], 100);
    expect(tradeItemsTotal({...merged, 'number': 3}), 300);
    expect([for (var i = 0; i < 4; i++) tradeReportStatus({'reportHandleStatus': i})],
      ['待处理', '处理中', '成立', '不成立']);
  });

  test('TR5 ongoing total reads all pages, reviews counted separately; EN forwarded', () async {
    final p = AuditPort()..row = {
      'transactionNumber': 'R', 'actorRole': 'seller', 'creatorType': 1,
      'transactionStatus': 2, 'deliveryStatus': 3,
    };
    // The filtered fixture returns only ongoing records, as SCM does.
    final c = MarketplaceTradesController(p, language: () => 'EN');
    addTearDown(c.dispose);
    // Use a distinct ongoing row shape from the completed ordinary page.
    p.count = 0;
    await c.refresh();
    expect(c.activeCountLabel, '0');
    expect(c.reviewCountLabel, '1+');
    expect(c.reviewsTodo, hasLength(1));
    p.row = {...p.row, 'transactionStatus': 1, 'deliveryStatus': 1};
    p.count = 23;
    await c.refresh();
    expect(c.activeCountLabel, '23');
    expect(c.todo, hasLength(23));
    expect(p.calls.where((r) => r['status'] == 1).last['page'], 2);
    expect(p.calls.every((r) => r['language'] == 'EN'), isTrue);
    expect(p.calls.any((r) => r['operation'] == 'detail'), isFalse);
    p.count = 201;
    await c.refresh();
    expect(c.activeCountLabel, '201+');
    expect(c.ongoing, hasLength(200));
    expect(c.todoCountLabel, '200+');
    p.failPage = 2;
    await c.refresh();
    expect(c.activeCountLabel, '201+');
    expect(c.todo, hasLength(20));
    expect(c.todoCountLabel, '20+');
  });

  test('TR5 account reset discards an in-flight filtered page', () async {
    final p = AuditPort()..ongoingGate = Completer<MarketRow>();
    final c = MarketplaceTradesController(p);
    addTearDown(c.dispose);
    final reading = c.refresh();
    while (!p.calls.any((r) => r['status'] == 1)) {
      await Future<void>.delayed(Duration.zero);
    }
    c.reset();
    p.ongoingGate!.complete({'rows': [p.row], 'total': 1});
    await reading;
    expect(c.rows, isEmpty);
    expect(c.ongoing, isEmpty);
  });

  test('TR6 summaries require both complete sources; failure hides averages', () {
    final list = MarketRecordList()
      ..rows = [{'sourceType': 'trade', 'rating': 5}]
      ..tradeTotal = 1
      ..contractTotal = 1;
    expect(list.reviewsComplete, isFalse);
    list.rows = [...list.rows, {'sourceType': 'contract', 'rating': 3}];
    expect(list.reviewsComplete, isTrue);
    list.failed = true;
    expect(list.reviewsComplete, isFalse);
    for (final key in ['按已加载的 {n} 条', '共 {n} 条评价']) {
      expect(recordsCopy[key], hasLength(3));
    }
  });

  test('TR7 shipment is approximate, absent without receipt deadline', () {
    expect(tradeApproximateShipment({}), isNull);
    expect(tradeApproximateShipment({'receiptDeadline': '2026-11-14 08:00:00'}),
      DateTime.utc(2026, 11, 12));
    expect(tradeAction({'actorRole': 'buyer', 'transactionStatus': 1,
      'deliveryStatus': 2, 'receiptDeadline': '2020-01-01 00:00:00'}), isNull);
  });

  testWidgets('TR10 English item name and TR9 set units', (tester) async {
    await tester.pumpWidget(preview(Builder(builder: (context) =>
      Localizations.override(context: context, locale: const Locale('en'),
        child: Builder(builder: (context) => Column(children: [
          Text(tradeItemName(context, {'itemsName': '矿石', 'itemsNameEn': 'Ore'})),
          Text(tradeQuantity(context, {'displayType': 2, 'number': 3})),
          Text(tradeText(context, '每套价格')),
        ])),
      )), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('Ore'), findsOneWidget);
    expect(find.text('× 3 sets'), findsOneWidget);
    expect(find.text('Price per set'), findsOneWidget);
  });

  test('all new definitive errors have three-language copy', () {
    for (final code in ['report_expired', 'report_exists', 'trade_blocked_self',
      'trade_blocked_other', 'trade_restricted', 'trade_rate_limited',
      'trade_quantity_unavailable', 'trade_listing_unavailable', 'trade_expired']) {
      final key = tradeError(MarketplaceTradeError('marketplace.$code'));
      expect(tradeCopy[key], hasLength(3));
      expect(tradeAccountPrechecks, contains('marketplace.$code'));
    }
  });
}