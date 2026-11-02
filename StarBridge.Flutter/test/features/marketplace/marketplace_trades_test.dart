import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_controller.dart';

import 'marketplace_test.dart' show FixturePort;

class TradesPort extends FixturePort implements MarketplaceTradePort {
  int writes = 0, reads = 0, revision = 0;
  Completer<MarketRow>? writeGate, tradeReadGate;
  bool fail = false;
  final pages = <int, List<MarketRow>>{};
  final details = <String, Completer<MarketRow>>{};
  MarketRow row = {
    'transactionNumber': 'T1',
    'itemsName': '科力晶',
    'actorRole': 'seller',
    'creatorType': 1,
    'deliveryStatus': 1,
    'transactionStatus': 1,
    'amount': 1200000,
    'number': 1,
  };
  @override
  Future<MarketRow> trade(String op, [MarketRow input = const {}]) async {
    if (op == 'revision') return {'revision': revision};
    if (op == 'list') {
      reads++;
      if (pages.isNotEmpty) {
        return {
          'rows': pages[input['page']] ?? <MarketRow>[],
          'total': pages.values.fold<int>(0, (sum, rows) => sum + rows.length),
        };
      }
      return tradeReadGate?.future ??
          Future.value({
            'rows': [Map<String, Object?>.from(row)],
            'total': 1,
          });
    }
    if (op == 'detail') {
      return details[input['transactionNumber']]?.future ??
          Future.value(Map<String, Object?>.from(row));
    }
    writes++;
    if (fail) throw const MarketplaceTradeError('marketplace.trade_rejected');
    return writeGate?.future ??
        Future.value({'transactionNumber': 'T1', 'confirmed': true});
  }
}

void main() {
  test('read failure retains snapshots; uncertain write needs inspection without resubmission', () async {
    final p = TradesPort();
    final c = MarketplaceTradesController(p);
    await c.refresh();
    await c.open('T1');
    p.tradeReadGate = Completer();
    final refresh = c.refresh();
    p.tradeReadGate!.completeError(
      TimeoutException('private endpoint not exposed'),
    );
    await refresh;
    expect(c.rows, hasLength(1));
    expect(c.detail?['transactionNumber'], 'T1');
    expect(c.error, '暂时读不到交易');
    p.tradeReadGate = null;
    p.writeGate = Completer();
    final write = c.submit('ship', {'transactionNumber': 'T1'});
    p.writeGate!.completeError(TimeoutException('secret'));
    expect(await write, isNull);
    expect(c.writeUncertain, isTrue);
    expect(c.writeError, contains('不要重复提交'));
    await c.refresh();
    expect(c.writeError, contains('不要重复提交'));
    await c.submit('ship', {'transactionNumber': 'T1'});
    expect(p.writes, 1);
    expect(await c.inspectUncertainWrite('T1'), isTrue);
    expect(p.writes, 1);
    expect(c.writeUncertain, isFalse);
    c.dispose();
  });
  test(
    'permission and login rejection are definitive, not unknown writes',
    () async {
      for (final code in ['forbidden', 'sign_in_required']) {
        final p = TradesPort()..writeGate = Completer();
        final c = MarketplaceTradesController(p);
        final write = c.submit('create', {'orderNumber': 'private'});
        p.writeGate!.completeError(MarketplaceTradeError('marketplace.$code'));
        await write;
        expect(c.writeUncertain, isFalse);
        expect(c.writeErrorCode, 'marketplace.$code');
        expect(c.diagnostic, isNot(contains('private')));
        expect(c.writeError, isNot(contains('重新授权')));
        c.dispose();
      }
    },
  );
  test('refresh retains loaded pages and out-of-order details cannot replace selection', () async {
    final p = TradesPort();
    p.pages[1] = [
      {...p.row, 'transactionNumber': 'A'},
    ];
    p.pages[2] = [
      {...p.row, 'transactionNumber': 'B'},
    ];
    final c = MarketplaceTradesController(p);
    await c.refresh();
    await c.refresh(more: true);
    expect(c.rows.length, 2);
    p.pages[1]![0]['deliveryStatus'] = 2;
    await c.refresh();
    expect(c.rows.length, 2);
    expect(c.rows.first['deliveryStatus'], 2);
    p.details['A'] = Completer();
    p.details['B'] = Completer();
    final a = c.open('A'), b = c.open('B');
    p.details['B']!.complete({...p.row, 'transactionNumber': 'B'});
    await b;
    p.details['A']!.complete({...p.row, 'transactionNumber': 'A'});
    await a;
    expect(c.detail?['transactionNumber'], 'B');
    expect(tradeAction({...p.row, 'transactionStatus': 3}), isNull);
    expect(tradeCanCancel({...p.row, 'transactionStatus': 3}), isFalse);
    c.dispose();
  });
  test('all roles and lifecycle states gate actions', () {
    for (final creator in [0, 1]) {
      for (final role in ['buyer', 'seller', 'unknown']) {
        for (var status = 0; status <= 4; status++) {
          final r = <String, Object?>{
            'actorRole': role,
            'creatorType': creator,
            'deliveryStatus': status,
            'transactionStatus': status == 3
                ? 2
                : status == 4
                ? 3
                : 1,
          };
          final expected = role == 'unknown'
              ? null
              : status == 0 && creator == 0 && role == 'buyer'
              ? 'approve'
              : status == 1 && role == 'seller'
              ? 'ship'
              : status == 2 && role == 'buyer'
              ? 'receive'
              : status == 3
              ? 'review'
              : null;
          expect(tradeAction(r), expected, reason: '$creator/$role/$status');
          expect(tradeCanCancel(r), role != 'unknown' && status < 2);
        }
      }
    }
    expect(
      tradeAction({
        'actorRole': 'buyer',
        'deliveryStatus': 3,
        'transactionStatus': 2,
        'buyerCommentId': 12,
      }),
      isNull,
    );
  });
  test('write waits for server, rejects duplicate click, preserves failed snapshot', () async {
    final p = TradesPort();
    final t = MarketplaceTradesController(p);
    await t.refresh();
    await t.open('T1');
    p.writeGate = Completer();
    final pending = t.submit('ship', {'transactionNumber': 'T1'});
    expect(t.pending, isTrue);
    expect(t.detail?['deliveryStatus'], 1);
    expect(await t.submit('ship', {'transactionNumber': 'T1'}), isNull);
    expect(p.writes, 1);
    p.row['deliveryStatus'] = 2;
    p.writeGate!.complete({'transactionNumber': 'T1'});
    expect(await pending, 'T1');
    expect(t.detail?['deliveryStatus'], 2);
    expect(t.pending, isFalse);
    p.writeGate = null;
    p.fail = true;
    expect(await t.submit('cancel', {'transactionNumber': 'T1'}), isNull);
    expect(t.detail?['deliveryStatus'], 2);
    expect(t.error, contains('服务器未接受'));
    t.dispose();
  });
  test(
    'remote invalidation rereads rows and open detail without manual refresh',
    () async {
      final p = TradesPort();
      final c = MarketplaceTradesController(p);
      await c.refresh();
      await c.open('T1');
      await c.checkUpdates();
      p.row['deliveryStatus'] = 2;
      p.revision++;
      final before = p.reads;
      await c.checkUpdates();
      expect(p.reads, before + 1);
      expect(c.rows.single['deliveryStatus'], 2);
      expect(c.detail?['deliveryStatus'], 2);
      expect(c.todo, isEmpty);
      expect(c.notices, 1);
      c.dispose();
    },
  );
  test(
    'old account read and write completion cannot restore private data',
    () async {
      final p = TradesPort();
      final t = MarketplaceTradesController(p);
      p.tradeReadGate = Completer();
      final read = t.refresh();
      t.reset();
      p.tradeReadGate!.complete({
        'rows': [p.row],
        'total': 1,
      });
      await read;
      expect(t.rows, isEmpty);
      p.tradeReadGate = null;
      p.writeGate = Completer();
      final write = t.submit('ship', {'transactionNumber': 'T1'});
      t.reset();
      p.writeGate!.complete({'transactionNumber': 'T1'});
      expect(await write, isNull);
      expect(t.detail, isNull);
      t.dispose();
    },
  );
}
