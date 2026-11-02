import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_browser.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_test.dart';

class OverviewPort extends FixturePort {
  bool fail = false;
  Completer<void>? gate;
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
    await gate?.future;
    if (fail) throw StateError('offline');
    return MarketRead({
      'rows': <MarketRow>[],
      'total': operation == 'marketOrders'
          ? 28
          : side == 1
          ? 18
          : side == 0
          ? 9
          : 1,
    }, DateTime.now());
  }
}

void main() {
  test('overview uses aggregate totals, retains them after failure and resets on context change', () async {
    final port = OverviewPort(), browser = MarketplaceBrowser(OverviewPort());
    final model = MarketplaceBrowser(port);
    expect(model.overview, isEmpty);
    await model.refreshOverview();
    expect(model.overview, {'all': 28, 'sell': 18, 'buy': 9, 'barter': 1});
    port.fail = true;
    await model.refreshOverview();
    expect(model.overview['sell'], 18);
    expect(model.overviewFailed, isTrue);
    port.fail = false;
    port.gate = Completer<void>();
    final pending = model.refreshOverview();
    model.reset();
    port.gate!.complete();
    await pending;
    expect(model.overview, isEmpty);
    model.dispose();
    browser.dispose();
  });
}
