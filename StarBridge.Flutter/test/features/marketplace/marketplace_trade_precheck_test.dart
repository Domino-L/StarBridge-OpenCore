import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_controller.dart';

import 'marketplace_trades_test.dart' show TradesPort;

/// Rejects every write with one SCM account precheck code.
class PrecheckPort extends TradesPort {
  PrecheckPort(this.code);
  final String code;
  @override
  Future<MarketRow> trade(String op, [MarketRow input = const {}]) {
    if (op == 'create') {
      writes++;
      return Future.error(MarketplaceTradeError(code));
    }
    return super.trade(op, input);
  }
}

void main() {
  for (final (code, needle) in [
    ('marketplace.account_unbound', '绑定游戏账号'),
    ('marketplace.trade_time_required', '交易时段'),
    ('marketplace.contact_required', '联系方式'),
    ('marketplace.account_abnormal', '重新验证'),
    ('marketplace.account_banned', '永久封禁'),
  ]) {
    test('$code is a definite, specific rejection', () async {
      final p = PrecheckPort(code);
      final c = MarketplaceTradesController(p);
      final number = await c.submit('create', {
        'orderNumber': 'O1',
        'number': 2,
        'locationId': 1,
        'deliveryMethod': 0,
        'shippingFee': 0,
      });
      expect(number, isNull);
      expect(p.writes, 1);
      expect(c.writeErrorCode, code);
      // Nothing was created, so the dialog may retry with the same draft.
      expect(c.writeUncertain, isFalse);
      expect(c.writeError, contains(needle));
      expect(c.writeError, isNot(contains('服务器未接受')));
      final copy = tradeCopy[c.writeError];
      expect(copy, isNotNull, reason: 'three-language copy for $code');
      expect(RegExp(r'[一-鿿]').hasMatch(copy![2]), isFalse);
      c.dispose();
    });
  }

  test('unknown SCM rejection keeps the generic message', () {
    expect(
      tradeError(const MarketplaceTradeError('marketplace.trade_rejected')),
      contains('服务器未接受'),
    );
  });
}
