import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

void main() {
  test(
    'trade copy covers all three locales including safe errors and expiry',
    () {
      for (final entry in tradeCopy.entries) {
        expect(entry.value.length, 3, reason: entry.key);
        expect(
          entry.value.every((value) => value.trim().isNotEmpty),
          isTrue,
          reason: entry.key,
        );
        expect(
          RegExp(r'[\u4e00-\u9fff]').hasMatch(entry.value[2]),
          isFalse,
          reason: entry.key,
        );
      }
      for (final code in [
        'sign_in_required',
        'forbidden',
        'state_changed',
        'not_participant',
        'busy',
        'trade_rejected',
        'unavailable',
      ]) {
        final key = tradeError(MarketplaceTradeError('marketplace.$code'));
        expect(tradeCopy.containsKey(key), isTrue);
      }
      expect(
        tradeTextFor('en', 'receiptDue', {'time': '20:41:07'}),
        'Confirm receipt within 20:41:07',
      );
      expect(tradeTextFor('hant', '已超时，等待 SCM 处理'), '已逾時，等待 SCM 處理');
    },
  );
  test('SCM amount is unit price, missing values never become zero', () {
    expect(
      tradeItemsTotal({'amount': 1200000, 'number': 2, 'displayType': 1}),
      2400000,
    );
    expect(tradeItemsTotal({'amount': 0, 'number': 2}), 0);
    expect(tradeItemsTotal({'amount': 1200000}), isNull);
    expect(tradeItemsTotal({'number': 2}), isNull);
    expect(tradeItemsTotal({'amount': 1200000, 'number': 0}), isNull);
    expect(
      tradeItemsTotal({'amount': 0, 'number': 2, 'displayType': 3}),
      isNull,
    );
    expect(tradeItemsTotal({'amount': double.infinity, 'number': 2}), isNull);
  });
}
