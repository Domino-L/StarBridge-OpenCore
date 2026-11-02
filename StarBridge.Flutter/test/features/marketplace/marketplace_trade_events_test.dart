import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_controller.dart';

import 'marketplace_trade_polling_test.dart' show PollingPort;

class EventPort extends PollingPort implements MarketplaceTradeEvents {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get tradeChanges => changes.stream;
}

void main() {
  testWidgets(
    'push refreshes immediately without revision polling; fallback remains',
    (tester) async {
      final p = EventPort();
      final c = MarketplaceTradesController(p)..setVisible(true);
      addTearDown(p.changes.close);
      await c.start();
      await c.open('T1');
      p.row['deliveryStatus'] = 2;
      p.changes.add(null);
      await tester.pump();
      expect(c.rows.single['deliveryStatus'], 2);
      expect(c.detail?['deliveryStatus'], 2);
      expect(p.reads, 2);
      await tester.pump(const Duration(seconds: 2));
      expect(p.revisionReads, 0);
      expect(p.reads, 2);
      await tester.pump(const Duration(seconds: 28));
      expect(p.reads, 2);
      await tester.pump(const Duration(seconds: 90));
      expect(p.reads, 3);
      expect(
        p.detailReads,
        2,
        reason: 'unchanged probe does not reread detail',
      );
      expect(p.writes, 0);
      c.dispose();
    },
  );

  testWidgets('push during read is coalesced and reset retires subscription', (
    tester,
  ) async {
    final p = EventPort();
    final c = MarketplaceTradesController(p);
    addTearDown(p.changes.close);
    await c.start();
    final gate = Completer<MarketRow>();
    p.tradeReadGate = gate;
    p.changes.add(null);
    p.changes.add(null);
    p.changes.add(null);
    expect(p.reads, 2);
    p.tradeReadGate = null;
    gate.complete({
      'rows': [p.row],
      'total': 1,
    });
    await tester.pump();
    expect(p.reads, 3);
    c.reset();
    p.changes.add(null);
    await tester.pump();
    expect(p.reads, 3);
  });

  testWidgets('push cannot bypass authorization denial', (tester) async {
    final p = EventPort()..readFailure = 'marketplace.forbidden';
    final c = MarketplaceTradesController(p);
    addTearDown(c.dispose);
    addTearDown(p.changes.close);
    await c.start();
    p.changes.add(null);
    await tester.pump(const Duration(seconds: 60));
    expect(p.reads, 1);
    expect(p.writes, 0);
  });
}
